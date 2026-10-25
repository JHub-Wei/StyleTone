import Foundation
import StyleToneCore

/// Pure planner for the WP-15 background protection constraint.
///
/// The planner is a pure function of `PortraitAnalysis` and the field assembled
/// by the preceding face/body/legs passes. It performs no image I/O and no
/// logging. Its hot loops are `O(vertices × lines)` on the coarse warp grid, so
/// the cost is dominated by reading the analysis masks; see
/// `Background/PERFORMANCE.md`.
///
/// The protection model is:
///
/// 1. **Structure detection** – the WP-05 `backgroundEdgeMask` is sampled onto a
///    structure grid twice the warp grid. Peak coverage keeps thin lines, mean
///    coverage keeps texture; long horizontal/vertical runs become lines and
///    line pairs close into rectangles.
/// 2. **Subject support** – the person mask (or a face/body bounding-box
///    fallback) defines where the subject is allowed to move at full strength.
/// 3. **Retention** – every structure and the generic background get a
///    retention factor; the constrained offset is
///    `source × background × line × edge × rectangle` retention.
/// 4. **Rigid lines** – a detected line core is forced to the line's own mean
///    displacement (scaled by the line retention), so the line can translate a
///    little but cannot bend.
struct BackgroundProtectionPlanner: Sendable {
    /// Tunables and safety rails.
    let configuration: BackgroundProtectionConfiguration

    /// Builds the plan for one field.
    ///
    /// - Parameters:
    ///   - field: Field assembled by the geometry passes. Must be valid.
    ///   - analysis: Frozen portrait analysis, including optional masks.
    /// - Returns: A plan whose ``BackgroundProtectionPlan/constrainedOffsets``
    ///   replace the field offsets.
    /// - Throws: ``GeometryError`` for an invalid field, or
    ///   `CancellationError` when the enclosing task is cancelled.
    func makePlan(
        field: WarpField,
        analysis: PortraitAnalysis
    ) throws -> BackgroundProtectionPlan {
        try field.validate()
        try Task.checkCancellation()
        let gridWidth = field.width
        let gridHeight = field.height
        let vertexCount = gridWidth * gridHeight
        guard !field.isZero() else {
            return .empty(gridWidth: gridWidth, gridHeight: gridHeight)
        }

        var warnings: [BackgroundProtectionWarning] = []
        let imageSize = analysis.imageSize
        let aspect: Float = imageSize.width > 0 && imageSize.height > 0
            ? Float(imageSize.height) / Float(imageSize.width)
            : 1

        // 1. Structure detection from the WP-05 edge mask.
        var lines: [BackgroundStructureLine] = []
        var rectangles: [BackgroundStructureRectangle] = []
        var structureGrid: BackgroundMaskGrid?
        var structureDimension = 0

        if let mask = analysis.backgroundEdgeMask {
            if imageSize.isPositive,
               mask.width != imageSize.width || mask.height != imageSize.height {
                warnings.append(
                    .maskSizeMismatch(
                        expected: imageSize,
                        actual: PixelSize(width: mask.width, height: mask.height)
                    )
                )
            }
            structureDimension = resolveStructureDimension(
                gridWidth: gridWidth,
                gridHeight: gridHeight
            )
            let grid = try BackgroundMaskSampler.sample(
                mask: mask,
                width: structureDimension,
                height: structureDimension,
                threshold: configuration.minimumEdgeValue,
                desiredStride: configuration.maskSamplingStride,
                maximumSamples: configuration.maximumMaskSamples
            )
            if grid.isEmpty {
                warnings.append(.edgeMaskEmpty)
            } else {
                structureGrid = grid
                let outcome = BackgroundStructureDetector(configuration: configuration)
                    .detect(
                        maximums: grid.maximums,
                        means: grid.means,
                        dimension: structureDimension
                    )
                lines = outcome.lines
                rectangles = outcome.rectangles
                if outcome.detectedLineCount > outcome.lines.count {
                    warnings.append(
                        .lineDetectionLimited(
                            detected: outcome.detectedLineCount,
                            kept: outcome.lines.count
                        )
                    )
                }
                if outcome.detectedRectangleCount > outcome.rectangles.count {
                    warnings.append(
                        .rectangleDetectionLimited(
                            detected: outcome.detectedRectangleCount,
                            kept: outcome.rectangles.count
                        )
                    )
                }
                if lines.isEmpty, rectangles.isEmpty {
                    warnings.append(.noStructureDetected)
                }
            }
        } else {
            warnings.append(.edgeMaskUnavailable)
        }
        try Task.checkCancellation()

        // 2. Subject support.
        let support = try makeSubjectSupport(
            analysis: analysis,
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            aspect: aspect,
            warnings: &warnings
        )

        // 3. Per-vertex protection weights.
        var edgeEvidence = edgeEvidenceGrid(
            structureGrid: structureGrid,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )
        edgeEvidence = spreadEdgeEvidence(
            edgeEvidence,
            width: gridWidth,
            height: gridHeight
        )

        var lineProtection = [Float](repeating: 0, count: vertexCount)
        var lineRigidityWeights = [Float](repeating: 0, count: vertexCount)
        var edgeProtection = [Float](repeating: 0, count: vertexCount)
        var rectangleProtection = [Float](repeating: 0, count: vertexCount)
        var combinedProtection = [Float](repeating: 0, count: vertexCount)
        var constrained = field.offsets

        for y in 0 ..< gridHeight {
            let ny = Float(y) / Float(gridHeight - 1)
            let row = y * gridWidth
            for x in 0 ..< gridWidth {
                let nx = Float(x) / Float(gridWidth - 1)
                let point = SIMD2<Float>(nx, ny)
                let index = row + x

                let edgeWeight = smoothstep(
                    configuration.edgeProtectionLow,
                    configuration.edgeProtectionHigh,
                    edgeEvidence[index]
                ) * configuration.edgeProtectionStrength

                var lineWeight: Float = 0
                for line in lines {
                    let falloff = lineFalloff(line, at: point, aspect: aspect)
                    let weighted = falloff * line.strength
                    if weighted > lineWeight {
                        lineWeight = weighted
                    }
                }
                lineRigidityWeights[index] = clamp01(lineWeight)

                var rectangleWeight: Float = 0
                for rectangle in rectangles where shouldFill(rectangle) {
                    let inside = insideDistance(
                        rectangle.rect,
                        point: point,
                        aspect: aspect
                    )
                    guard inside >= 0 else { continue }
                    let ramp = smoothstep(0, configuration.rectangleFillRamp, inside)
                    let weighted = ramp *
                        configuration.rectangleFillProtection *
                        rectangle.strength
                    if weighted > rectangleWeight {
                        rectangleWeight = weighted
                    }
                }

                let gate = 1 - clamp01(support[index])
                let lineP = clamp01(lineWeight) * gate
                let edgeP = clamp01(edgeWeight) * gate
                let rectangleP = clamp01(rectangleWeight) * gate
                lineProtection[index] = lineP
                edgeProtection[index] = edgeP
                rectangleProtection[index] = rectangleP

                // Multiplicative retention: each protection term can only
                // reduce the displacement.
                var retention = 1 - (1 - configuration.backgroundRetention) * gate
                retention *= 1 - (1 - configuration.lineRetention) * lineP
                retention *= 1 - (1 - configuration.edgeRetention) * edgeP
                retention *= 1 - (1 - configuration.rectangleRetention) * rectangleP
                retention = clamp01(retention)
                constrained[index] = field.offsets[index] * retention

                combinedProtection[index] = 1 -
                    (1 - lineP) * (1 - edgeP) * (1 - rectangleP)
            }
        }
        try Task.checkCancellation()

        // 4. Rigid-line constraint: every core vertex of a line gets the same
        // displacement (the line's mean source displacement times the line
        // retention). Blended with the damped field at the line feather.
        if !lines.isEmpty, configuration.lineRigidity > 0 {
            var targetSum = [SIMD2<Float>](repeating: .zero, count: vertexCount)
            var targetWeight = [Float](repeating: 0, count: vertexCount)

            for line in lines {
                var weightedSum = SIMD2<Float>(0, 0)
                var weightSum: Float = 0
                for y in 0 ..< gridHeight {
                    let ny = Float(y) / Float(gridHeight - 1)
                    let row = y * gridWidth
                    for x in 0 ..< gridWidth {
                        let nx = Float(x) / Float(gridWidth - 1)
                        let point = SIMD2<Float>(nx, ny)
                        let weight = lineFalloff(line, at: point, aspect: aspect) *
                            (1 - clamp01(support[row + x]))
                        guard weight >= 0.5 else { continue }
                        weightedSum += field.offsets[row + x] * weight
                        weightSum += weight
                    }
                }
                guard weightSum > 0 else { continue }
                let target = (weightedSum * (1 / weightSum)) * configuration.lineRetention

                for y in 0 ..< gridHeight {
                    let ny = Float(y) / Float(gridHeight - 1)
                    let row = y * gridWidth
                    for x in 0 ..< gridWidth {
                        let nx = Float(x) / Float(gridWidth - 1)
                        let point = SIMD2<Float>(nx, ny)
                        let weight = lineFalloff(line, at: point, aspect: aspect) *
                            (1 - clamp01(support[row + x]))
                        guard weight >= 0.35 else { continue }
                        targetSum[row + x] += target * weight
                        targetWeight[row + x] += weight
                    }
                }
            }

            for index in 0 ..< vertexCount {
                guard targetWeight[index] > 0 else { continue }
                // Rigidity uses the *ungated* line falloff: the visible
                // background side of a line stays rigid even when the subject
                // support is already tapering off at the silhouette. Inside the
                // subject (support > 0.85) the line follows the subject instead.
                let backgroundSide = 1 - smoothstep(0.35, 0.85, support[index])
                let blend = smoothstep(0.35, 0.90, lineRigidityWeights[index]) *
                    backgroundSide * configuration.lineRigidity
                guard blend > 0 else { continue }
                let target = targetSum[index] * (1 / targetWeight[index])
                let damped = constrained[index]
                constrained[index] = damped + (target - damped) * blend
            }
        }

        let metrics = makeMetrics(
            source: field.offsets,
            constrained: constrained,
            support: support,
            lineProtection: lineProtection,
            edgeProtection: edgeProtection,
            rectangleProtection: rectangleProtection,
            lines: lines,
            rectangles: rectangles,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )

        return BackgroundProtectionPlan(
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            sourceOffsets: field.offsets,
            constrainedOffsets: constrained,
            protectionWeights: combinedProtection,
            subjectSupport: support,
            lines: lines,
            rectangles: rectangles,
            metrics: metrics,
            warnings: warnings
        )
    }

    // MARK: - Edge evidence

    private func edgeEvidenceGrid(
        structureGrid: BackgroundMaskGrid?,
        gridWidth: Int,
        gridHeight: Int
    ) -> [Float] {
        guard let structureGrid else {
            return [Float](repeating: 0, count: gridWidth * gridHeight)
        }
        var evidence = [Float](repeating: 0, count: gridWidth * gridHeight)
        for y in 0 ..< gridHeight {
            let ny = Float(y) / Float(gridHeight - 1)
            let row = y * gridWidth
            for x in 0 ..< gridWidth {
                let nx = Float(x) / Float(gridWidth - 1)
                let point = SIMD2<Float>(nx, ny)
                let thin = structureGrid.maximum(at: point) *
                    configuration.edgeThinGain
                let texture = structureGrid.mean(at: point) *
                    configuration.edgeTextureGain
                evidence[row + x] = clamp01(max(thin, texture))
            }
        }
        return evidence
    }

    private func spreadEdgeEvidence(
        _ values: [Float],
        width: Int,
        height: Int
    ) -> [Float] {
        let spread = configuration.edgeSpreadWeight
        guard spread > 0, width >= 2, height >= 2 else { return values }
        var result = values
        let diagonalSpread = spread * 0.60
        for y in 0 ..< height {
            let row = y * width
            for x in 0 ..< width {
                let index = row + x
                var best = values[index]
                if x > 0 {
                    best = max(best, values[index - 1] * spread)
                }
                if x + 1 < width {
                    best = max(best, values[index + 1] * spread)
                }
                if y > 0 {
                    best = max(best, values[index - width] * spread)
                }
                if y + 1 < height {
                    best = max(best, values[index + width] * spread)
                }
                if x > 0, y > 0 {
                    best = max(best, values[index - width - 1] * diagonalSpread)
                }
                if x + 1 < width, y > 0 {
                    best = max(best, values[index - width + 1] * diagonalSpread)
                }
                if x > 0, y + 1 < height {
                    best = max(best, values[index + width - 1] * diagonalSpread)
                }
                if x + 1 < width, y + 1 < height {
                    best = max(best, values[index + width + 1] * diagonalSpread)
                }
                result[index] = clamp01(best)
            }
        }
        return result
    }

    // MARK: - Geometry helpers

    private func lineFalloff(
        _ line: BackgroundStructureLine,
        at point: SIMD2<Float>,
        aspect: Float
    ) -> Float {
        let distance = distanceToLine(line, point: point, aspect: aspect)
        let core = configuration.lineCoreRadius
        let outer = core + configuration.lineFeather
        guard distance <= outer else { return 0 }
        return 1 - smoothstep(core, outer, distance)
    }

    private func distanceToLine(
        _ line: BackgroundStructureLine,
        point: SIMD2<Float>,
        aspect: Float
    ) -> Float {
        let px = point.x
        let py = point.y * aspect
        switch line.orientation {
        case .horizontal:
            let lineY = line.position * aspect
            let clampedX = min(max(px, line.start), line.end)
            let dx = px - clampedX
            let dy = py - lineY
            return (dx * dx + dy * dy).squareRoot()
        case .vertical:
            let lineX = line.position
            let startY = line.start * aspect
            let endY = line.end * aspect
            let clampedY = min(max(py, startY), endY)
            let dx = px - lineX
            let dy = py - clampedY
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    /// Distance from a point to a rectangle boundary, positive inside. The
    /// distance is in image-width units so the fill ramp is isotropic.
    private func insideDistance(
        _ rect: NormalizedRect,
        point: SIMD2<Float>,
        aspect: Float
    ) -> Float {
        let left = Float(rect.minX)
        let right = Float(rect.maxX)
        let top = Float(rect.minY) * aspect
        let bottom = Float(rect.maxY) * aspect
        let px = point.x
        let py = point.y * aspect
        let horizontal = min(px - left, right - px)
        let vertical = min(py - top, bottom - py)
        return min(horizontal, vertical)
    }

    private func shouldFill(_ rectangle: BackgroundStructureRectangle) -> Bool {
        let area = rectangle.rect.width * rectangle.rect.height
        return area <= Double(configuration.maximumRectangleFillAreaFraction)
    }

    // MARK: - Subject support

    private func makeSubjectSupport(
        analysis: PortraitAnalysis,
        gridWidth: Int,
        gridHeight: Int,
        aspect: Float,
        warnings: inout [BackgroundProtectionWarning]
    ) throws -> [Float] {
        let count = gridWidth * gridHeight
        var personSupport = [Float](repeating: 0, count: count)
        var hasPersonSupport = false

        if let mask = analysis.personMask {
            let grid = try BackgroundMaskSampler.sample(
                mask: mask,
                width: gridWidth,
                height: gridHeight,
                threshold: 0,
                desiredStride: configuration.subjectMaskSamplingStride,
                maximumSamples: configuration.maximumMaskSamples
            )
            let strongCount = grid.means.filter { $0 >= 0.5 }.count
            let coverage = count > 0 ? Float(strongCount) / Float(count) : 0
            if coverage >= configuration.subjectMaskEmptyCoverage {
                hasPersonSupport = true
                for index in 0 ..< count {
                    personSupport[index] = smoothstep(
                        configuration.personMaskLowerGate,
                        configuration.personMaskUpperGate,
                        grid.means[index]
                    )
                }
            } else {
                warnings.append(.subjectMaskEmpty)
            }
        } else {
            warnings.append(.subjectMaskUnavailable)
        }

        let fallback = fallbackSupport(
            analysis: analysis,
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            aspect: aspect
        )
        guard fallback.hasRegion else {
            if !hasPersonSupport {
                warnings.append(.subjectRegionUnavailable)
            }
            return personSupport
        }

        var support = personSupport
        for index in 0 ..< count where fallback.values[index] > support[index] {
            support[index] = fallback.values[index]
        }
        return support
    }

    private func fallbackSupport(
        analysis: PortraitAnalysis,
        gridWidth: Int,
        gridHeight: Int,
        aspect: Float
    ) -> (values: [Float], hasRegion: Bool) {
        var values = [Float](repeating: 0, count: gridWidth * gridHeight)
        var hasRegion = false

        for face in analysis.faces {
            let box = face.boundingBox.clamped()
            guard box.width > 0, box.height > 0 else { continue }
            let expansionX = box.width * Double(configuration.faceSupportExpansion)
            let expansionY = box.height * Double(configuration.faceSupportExpansion)
            let expanded = NormalizedRect(
                x: box.x - expansionX,
                y: box.y - expansionY,
                width: box.width + 2 * expansionX,
                height: box.height + 2 * expansionY
            ).clamped()
            applyFallbackBox(
                expanded,
                values: &values,
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                aspect: aspect
            )
            hasRegion = true
        }

        if let body = analysis.body, !body.joints.isEmpty {
            var minX = Double.greatestFiniteMagnitude
            var minY = Double.greatestFiniteMagnitude
            var maxX = -Double.greatestFiniteMagnitude
            var maxY = -Double.greatestFiniteMagnitude
            for point in body.joints.values {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
            if minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite,
               maxX > minX, maxY > minY {
                let margin = Double(configuration.bodySupportMargin)
                let expanded = NormalizedRect(
                    x: minX - margin,
                    y: minY - margin,
                    width: (maxX - minX) + 2 * margin,
                    height: (maxY - minY) + 2 * margin
                ).clamped()
                applyFallbackBox(
                    expanded,
                    values: &values,
                    gridWidth: gridWidth,
                    gridHeight: gridHeight,
                    aspect: aspect
                )
                hasRegion = true
            }
        }
        return (values, hasRegion)
    }

    private func applyFallbackBox(
        _ box: NormalizedRect,
        values: inout [Float],
        gridWidth: Int,
        gridHeight: Int,
        aspect: Float
    ) {
        let feather = configuration.subjectSupportFeather
        let left = Float(box.minX)
        let right = Float(box.maxX)
        let top = Float(box.minY)
        let bottom = Float(box.maxY)
        for y in 0 ..< gridHeight {
            let py = Float(y) / Float(gridHeight - 1)
            let row = y * gridWidth
            for x in 0 ..< gridWidth {
                let px = Float(x) / Float(gridWidth - 1)
                let outsideX = max(left - px, px - right)
                let outsideY = max(top - py, py - bottom)
                let dx = max(outsideX, 0)
                let dy = max(outsideY, 0) * aspect
                let distance = (dx * dx + dy * dy).squareRoot()
                let weight = 1 - smoothstep(0, feather, distance)
                if weight > values[row + x] {
                    values[row + x] = weight
                }
            }
        }
    }

    // MARK: - Metrics

    private func makeMetrics(
        source: [SIMD2<Float>],
        constrained: [SIMD2<Float>],
        support: [Float],
        lineProtection: [Float],
        edgeProtection: [Float],
        rectangleProtection: [Float],
        lines: [BackgroundStructureLine],
        rectangles: [BackgroundStructureRectangle],
        gridWidth: Int,
        gridHeight: Int
    ) -> BackgroundProtectionMetrics {
        let count = source.count
        guard count > 0 else {
            return .empty(vertexCount: 0)
        }
        let riskThreshold = configuration.riskDisplacementThreshold

        var maximumBefore: Float = 0
        var maximumAfter: Float = 0
        var movedVertexCount = 0
        var backgroundCount = 0
        var protectedBackgroundCount = 0
        var protectionSum: Float = 0
        var backgroundBeforeSum: Float = 0
        var backgroundAfterSum: Float = 0
        var subjectBeforeSum: Float = 0
        var subjectAfterSum: Float = 0
        var structureMaximumBefore: Float = 0
        var structureMaximumAfter: Float = 0
        var riskyVertexCount = 0
        var residualRiskyVertexCount = 0

        for index in 0 ..< count {
            let before = magnitude(source[index])
            let after = magnitude(constrained[index])
            maximumBefore = max(maximumBefore, before)
            maximumAfter = max(maximumAfter, after)
            if before > 0 {
                movedVertexCount += 1
            }

            let combination = 1 -
                (1 - lineProtection[index]) *
                (1 - edgeProtection[index]) *
                (1 - rectangleProtection[index])

            if support[index] < 0.5 {
                backgroundCount += 1
                protectionSum += combination
                backgroundBeforeSum += before
                backgroundAfterSum += after
                if combination >= 0.5 {
                    protectedBackgroundCount += 1
                }
                // Only the structure core counts for residual displacement and
                // risk; the feathered shoulder is expected to move a little.
                if combination >= 0.75 {
                    structureMaximumBefore = max(structureMaximumBefore, before)
                    structureMaximumAfter = max(structureMaximumAfter, after)
                    if before >= riskThreshold {
                        riskyVertexCount += 1
                    }
                    if after >= riskThreshold {
                        residualRiskyVertexCount += 1
                    }
                }
            }
            if support[index] >= 0.9 {
                subjectBeforeSum += before
                subjectAfterSum += after
            }
        }

        var maximumDeviationBefore: Float = 0
        var maximumDeviationAfter: Float = 0
        for line in lines {
            maximumDeviationBefore = max(
                maximumDeviationBefore,
                sampledLineDeviation(
                    line,
                    offsets: source,
                    support: support,
                    gridWidth: gridWidth,
                    gridHeight: gridHeight
                )
            )
            maximumDeviationAfter = max(
                maximumDeviationAfter,
                sampledLineDeviation(
                    line,
                    offsets: constrained,
                    support: support,
                    gridWidth: gridWidth,
                    gridHeight: gridHeight
                )
            )
        }

        return BackgroundProtectionMetrics(
            vertexCount: count,
            detectedLineCount: lines.count,
            detectedRectangleCount: rectangles.count,
            backgroundVertexFraction: Float(backgroundCount) / Float(count),
            protectedBackgroundVertexFraction: backgroundCount > 0
                ? Float(protectedBackgroundCount) / Float(backgroundCount)
                : 0,
            meanStructureProtection: backgroundCount > 0
                ? protectionSum / Float(backgroundCount)
                : 0,
            maximumDisplacementBefore: maximumBefore,
            maximumDisplacementAfter: maximumAfter,
            backgroundRetention: backgroundBeforeSum > 0
                ? backgroundAfterSum / backgroundBeforeSum
                : 1,
            subjectRetention: subjectBeforeSum > 0
                ? subjectAfterSum / subjectBeforeSum
                : 1,
            maximumStructureDisplacementBefore: structureMaximumBefore,
            maximumStructureDisplacementAfter: structureMaximumAfter,
            maximumLineDeviationBefore: maximumDeviationBefore,
            maximumLineDeviationAfter: maximumDeviationAfter,
            riskyVertexCount: riskyVertexCount,
            residualRiskyVertexCount: residualRiskyVertexCount,
            movedVertexCount: movedVertexCount
        )
    }

    private func sampledLineDeviation(
        _ line: BackgroundStructureLine,
        offsets: [SIMD2<Float>],
        support: [Float],
        gridWidth: Int,
        gridHeight: Int
    ) -> Float {
        let sampleCount = max(9, gridWidth + gridHeight)
        var normals = [Float]()
        normals.reserveCapacity(sampleCount)
        for sample in 0 ..< sampleCount {
            let t = sampleCount > 1
                ? Float(sample) / Float(sampleCount - 1)
                : 0
            let along = line.start + (line.end - line.start) * t
            let point = line.orientation == .vertical
                ? SIMD2<Float>(line.position, along)
                : SIMD2<Float>(along, line.position)
            // Only the visible background part of a line is a protection
            // target; a line hidden behind/inside the subject is expected to
            // move with the subject.
            let supportAtPoint = interpolatedValue(
                support,
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                at: point
            )
            guard supportAtPoint < 0.5 else { continue }
            let offset = interpolatedOffset(
                offsets,
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                at: point
            )
            normals.append(
                line.orientation == .vertical ? offset.x : offset.y
            )
        }
        guard normals.count >= 3 else { return 0 }
        return deviation(normals)
    }

    private func interpolatedValue(
        _ values: [Float],
        gridWidth: Int,
        gridHeight: Int,
        at point: SIMD2<Float>
    ) -> Float {
        guard gridWidth >= 2, gridHeight >= 2,
              values.count == gridWidth * gridHeight else {
            return 0
        }
        let x = min(max(point.x, 0), 1) * Float(gridWidth - 1)
        let y = min(max(point.y, 0), 1) * Float(gridHeight - 1)
        let x0 = min(Int(x), gridWidth - 2)
        let y0 = min(Int(y), gridHeight - 2)
        let x1 = x0 + 1
        let y1 = y0 + 1
        let tx = x - Float(x0)
        let ty = y - Float(y0)
        let top = values[y0 * gridWidth + x0] * (1 - tx) +
            values[y0 * gridWidth + x1] * tx
        let bottom = values[y1 * gridWidth + x0] * (1 - tx) +
            values[y1 * gridWidth + x1] * tx
        return top * (1 - ty) + bottom * ty
    }

    /// Bilinear field interpolation at a normalized position, matching the
    /// renderer's clamp-to-edge sampling.
    private func interpolatedOffset(
        _ offsets: [SIMD2<Float>],
        gridWidth: Int,
        gridHeight: Int,
        at point: SIMD2<Float>
    ) -> SIMD2<Float> {
        guard gridWidth >= 2, gridHeight >= 2,
              offsets.count == gridWidth * gridHeight else {
            return .zero
        }
        let x = min(max(point.x, 0), 1) * Float(gridWidth - 1)
        let y = min(max(point.y, 0), 1) * Float(gridHeight - 1)
        let x0 = min(Int(x), gridWidth - 2)
        let y0 = min(Int(y), gridHeight - 2)
        let x1 = x0 + 1
        let y1 = y0 + 1
        let tx = x - Float(x0)
        let ty = y - Float(y0)
        let topLeft = offsets[y0 * gridWidth + x0]
        let topRight = offsets[y0 * gridWidth + x1]
        let bottomLeft = offsets[y1 * gridWidth + x0]
        let bottomRight = offsets[y1 * gridWidth + x1]
        let top = topLeft * (1 - tx) + topRight * tx
        let bottom = bottomLeft * (1 - tx) + bottomRight * tx
        return top * (1 - ty) + bottom * ty
    }

    private func deviation(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        var sum: Float = 0
        for value in values {
            sum += value
        }
        let mean = sum / Float(values.count)
        var maximum: Float = 0
        for value in values {
            maximum = max(maximum, abs(value - mean))
        }
        return maximum
    }

    // MARK: - Small helpers

    private func resolveStructureDimension(gridWidth: Int, gridHeight: Int) -> Int {
        if configuration.structureGridDimension > 0 {
            return configuration.structureGridDimension
        }
        let automatic = max(gridWidth, gridHeight) * 2
        return min(
            max(automatic, configuration.minimumStructureGridDimension),
            configuration.maximumStructureGridDimension
        )
    }

    private func magnitude(_ offset: SIMD2<Float>) -> Float {
        (offset.x * offset.x + offset.y * offset.y).squareRoot()
    }

    private func clamp01(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        guard edge1 > edge0 else {
            return value < edge0 ? 0 : 1
        }
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
