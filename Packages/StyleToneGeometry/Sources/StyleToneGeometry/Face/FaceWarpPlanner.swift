import Foundation
import StyleToneCore

/// Pure displacement planner for the face slim/jaw pass.
///
/// The planner is a pure function of `PortraitAnalysis`, `FaceParameters` and
/// the mesh density. It performs no image I/O, no logging and no allocation
/// proportional to image pixels; the hot loop is `O(gridWidth * gridHeight *
/// faces * guards)` and stays well inside a 30 fps frame budget at preview
/// density (32x32).
struct FaceWarpPlanner: Sendable {
    let configuration: FaceWarpConfiguration

    private struct Candidate {
        let index: Int
        let area: Float
        let confidence: Float
        let face: FaceObservation
    }

    private static let strengthEpsilon: Float = 1e-6

    /// Builds the plan for one frame.
    ///
    /// - Throws: ``GeometryError/invalidGrid(width:height:)`` when the mesh
    ///   density is smaller than 2 vertices per axis.
    func makePlan(
        analysis: PortraitAnalysis,
        parameters: FaceParameters,
        gridWidth: Int,
        gridHeight: Int
    ) throws -> FaceWarpPlan {
        guard gridWidth >= 2, gridHeight >= 2 else {
            throw GeometryError.invalidGrid(width: gridWidth, height: gridHeight)
        }
        let vertexCount = gridWidth * gridHeight
        let gridSpacing = max(
            1 / Float(gridWidth - 1),
            1 / Float(gridHeight - 1)
        )
        // Every cell corner around a feature must be inside the guard core for
        // bilinear sampling at the feature point to be exactly zero. One full
        // mesh cell (plus a small float cushion) is therefore the minimum
        // margin; the configured margin can only make protection stronger.
        let protectionMargin = max(
            configuration.featureProtectionMargin,
            gridSpacing * 1.05
        )
        let slim = Self.clampStrength(parameters.slim)
        let jaw = Self.clampStrength(parameters.jaw)
        guard slim > Self.strengthEpsilon || jaw > Self.strengthEpsilon else {
            return makeEmptyPlan(
                warnings: [],
                gridWidth: gridWidth,
                gridHeight: gridHeight
            )
        }

        var warnings: [FaceWarpWarning] = []
        var candidates: [Candidate] = []
        candidates.reserveCapacity(analysis.faces.count)

        for (index, face) in analysis.faces.enumerated() {
            let rawConfidence = face.confidence
            let confidence = rawConfidence.isFinite ? rawConfidence : 0
            let box = face.boundingBox
            guard box.x.isFinite,
                  box.y.isFinite,
                  box.width.isFinite,
                  box.height.isFinite,
                  box.width > 0,
                  box.height > 0
            else {
                warnings.append(.degenerateFace(faceIndex: index))
                continue
            }
            if confidence < configuration.minimumFaceConfidence {
                warnings.append(
                    .lowConfidence(faceIndex: index, confidence: confidence)
                )
                continue
            }
            let clamped = box.clamped()
            let area = Float(clamped.width * clamped.height)
            if area < configuration.minimumFaceAreaFraction {
                warnings.append(
                    .faceTooSmall(faceIndex: index, areaFraction: area)
                )
                continue
            }
            candidates.append(
                Candidate(
                    index: index,
                    area: area,
                    confidence: confidence,
                    face: face
                )
            )
        }

        guard !candidates.isEmpty else {
            warnings.append(analysis.faces.isEmpty ? .noFace : .noUsableFace)
            return makeEmptyPlan(
                warnings: warnings,
                gridWidth: gridWidth,
                gridHeight: gridHeight
            )
        }

        // "Multiple faces by area": the largest face is always processed, and
        // small background faces are dropped only when the configured count is
        // exceeded. Ties prefer higher confidence, then the analyzer order.
        candidates.sort { lhs, rhs in
            if lhs.area != rhs.area {
                return lhs.area > rhs.area
            }
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.index < rhs.index
        }
        if candidates.count > configuration.maximumFaceCount {
            warnings.append(
                .faceCountLimited(
                    detected: candidates.count,
                    processed: configuration.maximumFaceCount
                )
            )
            candidates.removeLast(candidates.count - configuration.maximumFaceCount)
        }
        if analysis.faces.count > 1 {
            warnings.append(.multipleFaces(count: analysis.faces.count))
        }

        var offsets = [SIMD2<Float>](repeating: .zero, count: vertexCount)
        var coverage = [Float](repeating: 0, count: vertexCount)
        var metrics: [FaceWarpFaceMetrics] = []
        metrics.reserveCapacity(candidates.count)

        for candidate in candidates {
            let outcome = FaceGeometryExtractor.extract(
                face: candidate.face,
                faceIndex: candidate.index,
                configuration: configuration,
                protectionMargin: protectionMargin
            )
            warnings.append(contentsOf: outcome.warnings)
            guard let geometry = outcome.geometry else {
                continue
            }

            let faceWidth = geometry.faceWidth
            let cap = min(
                configuration.maximumCombinedDisplacementFraction * faceWidth,
                configuration.maximumAbsoluteDisplacement
            )
            let slimPeak = slim * configuration.slimDisplacementFraction * faceWidth
            let jawPeak = jaw * configuration.jawDisplacementFraction * faceWidth
            var peak: Float = 0

            for yIndex in 0 ..< gridHeight {
                let y = Float(yIndex) / Float(gridHeight - 1)
                let row = yIndex * gridWidth
                for xIndex in 0 ..< gridWidth {
                    let x = Float(xIndex) / Float(gridWidth - 1)
                    guard let vertexContribution = contribution(
                        at: SIMD2<Float>(x, y),
                        geometry: geometry,
                        slimPeak: slimPeak,
                        jawPeak: jawPeak,
                        cap: cap
                    ) else {
                        continue
                    }
                    let index = row + xIndex
                    offsets[index] += vertexContribution.offset
                    coverage[index] += vertexContribution.coverage
                    peak = max(peak, abs(vertexContribution.offset.x))
                }
            }

            metrics.append(
                FaceWarpFaceMetrics(
                    faceIndex: geometry.faceIndex,
                    confidence: geometry.confidence,
                    areaFraction: geometry.areaFraction,
                    centerX: geometry.centerX,
                    eyeY: geometry.eyeY,
                    chinY: geometry.chinY,
                    halfWidth: geometry.halfWidth,
                    isContourEstimated: geometry.isContourEstimated,
                    peakDisplacement: peak
                )
            )
        }

        if metrics.isEmpty {
            warnings.append(.noUsableFace)
        }

        // Adjacent faces can share a few vertices (very close subjects). Blend
        // instead of summing so overlapping faces cannot double the strength.
        var maximum: Float = 0
        var deformedVertexCount = 0
        for index in offsets.indices {
            if coverage[index] > 1 {
                offsets[index] = offsets[index] * (1 / coverage[index])
            }
            let value = offsets[index]
            let magnitude = (value.x * value.x + value.y * value.y).squareRoot()
            guard magnitude.isFinite else {
                offsets[index] = .zero
                continue
            }
            if magnitude > 0 {
                deformedVertexCount += 1
            }
            maximum = max(maximum, magnitude)
        }

        return FaceWarpPlan(
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            offsets: offsets,
            faces: metrics,
            warnings: warnings,
            maximumDisplacement: maximum,
            deformedVertexCount: deformedVertexCount
        )
    }

    /// One vertex contribution.
    ///
    /// The displacement is horizontal and points towards the symmetry axis:
    /// on the left side of the face content moves right, on the right side it
    /// moves left. `offset` already contains the spatial envelope; `coverage`
    /// is used only to blend overlapping faces.
    private func contribution(
        at point: SIMD2<Float>,
        geometry: FaceWarpGeometry,
        slimPeak: Float,
        jawPeak: Float,
        cap: Float
    ) -> (offset: SIMD2<Float>, coverage: Float)? {
        guard geometry.halfWidth > 0, geometry.faceHeight > 0 else {
            return nil
        }

        let dx = point.x - geometry.centerX
        let horizontal = abs(dx) / geometry.halfWidth
        guard horizontal < 1.35 else {
            return nil
        }
        let vertical = (point.y - geometry.eyeY) / geometry.faceHeight
        guard vertical > 0, vertical < 1.25 else {
            return nil
        }

        // Lateral envelope: zero on the centre line (nose/lips), full across
        // the cheek, fading just outside the face contour.
        let lateral = Self.smoothstep(0.22, 0.62, horizontal)
            * (1 - Self.smoothstep(0.98, 1.22, horizontal))
        guard lateral > 0 else {
            return nil
        }

        // Hairline/forehead protection: no displacement on or above the eye
        // line, ramping in below it. The lower ramp keeps the jaw from pulling
        // the neck after the chin.
        let top = Self.smoothstep(0.02, 0.20, vertical)
        let bottom = 1 - Self.smoothstep(1.02, 1.24, vertical)
        guard top > 0, bottom > 0 else {
            return nil
        }

        // Cheek band (slim) and jaw band (jaw) overlap smoothly.
        let slimWeight = Self.smoothstep(0.08, 0.30, vertical)
            * (1 - Self.smoothstep(0.80, 1.05, vertical))
        let jawWeight = Self.smoothstep(0.42, 0.70, vertical)
            * (1 - Self.smoothstep(1.05, 1.24, vertical))

        // Eyes, eyebrows, nose and lips (including teeth) are hard-zero inside
        // their guard, with a smooth falloff back to the deformation field.
        let safety = 1 - geometry.protection(at: point)
        guard safety > 0 else {
            return nil
        }

        let envelope = lateral * top * bottom * safety
        let unclamped = slimPeak * slimWeight + jawPeak * jawWeight
        let magnitude = min(unclamped, cap) * envelope
        guard magnitude > 0 else {
            return nil
        }

        let direction: Float
        if dx < 0 {
            direction = 1
        } else if dx > 0 {
            direction = -1
        } else {
            return nil
        }

        return (
            offset: SIMD2<Float>(direction * magnitude, 0),
            coverage: max(slimWeight, jawWeight) * envelope
        )
    }

    private func makeEmptyPlan(
        warnings: [FaceWarpWarning],
        gridWidth: Int,
        gridHeight: Int
    ) -> FaceWarpPlan {
        FaceWarpPlan(
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            offsets: [SIMD2<Float>](
                repeating: .zero,
                count: gridWidth * gridHeight
            ),
            faces: [],
            warnings: warnings,
            maximumDisplacement: 0,
            deformedVertexCount: 0
        )
    }

    private static func clampStrength(_ value: Double) -> Float {
        guard value.isFinite else { return 0 }
        return Float(min(max(value, 0), 1))
    }

    private static func smoothstep(
        _ edge0: Float,
        _ edge1: Float,
        _ value: Float
    ) -> Float {
        guard edge1 > edge0 else {
            return value < edge0 ? 0 : 1
        }
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
