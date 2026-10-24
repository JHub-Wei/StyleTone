import Foundation
import StyleToneCore

/// Axis-aligned protection region around one facial feature.
///
/// The region is a hard core (protection `1`) plus a smoothstep feather to zero.
/// Distances are normalized image units, matching the mesh field.
struct FaceProtectionGuard: Sendable, Equatable {
    let minX: Float
    let maxX: Float
    let minY: Float
    let maxY: Float
    let feather: Float

    /// Protection weight at `point`: `1` inside the core, `0` beyond the feather.
    func protection(at point: SIMD2<Float>) -> Float {
        let dx = max(max(minX - point.x, 0), point.x - maxX)
        let dy = max(max(minY - point.y, 0), point.y - maxY)
        if dx <= 0, dy <= 0 {
            return 1
        }
        guard feather > 0 else {
            return 0
        }
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance < feather else {
            return 0
        }
        let t = distance / feather
        return 1 - t * t * (3 - 2 * t)
    }
}

/// Symmetric face geometry derived from one observation.
///
/// The profile itself only depends on `|x - centerX|` and on the vertical
/// position between the eye line and the chin, so the resulting field is
/// mirror-symmetric by construction. Feature guards are mirrored around the
/// same axis, which keeps symmetry even when the detected landmarks are not
/// perfectly symmetric.
struct FaceWarpGeometry: Sendable {
    let faceIndex: Int
    let confidence: Float
    let areaFraction: Float
    let centerX: Float
    let eyeY: Float
    let chinY: Float
    let halfWidth: Float
    let guards: [FaceProtectionGuard]
    let isContourEstimated: Bool

    /// Full face width used by strength and cap calculations.
    var faceWidth: Float {
        halfWidth * 2
    }

    /// Vertical distance from the eye line to the chin.
    var faceHeight: Float {
        max(chinY - eyeY, 0)
    }

    /// Combined feature protection at `point`, `0...1`.
    func protection(at point: SIMD2<Float>) -> Float {
        var value: Float = 0
        for guardRegion in guards {
            let candidate = guardRegion.protection(at: point)
            if candidate > value {
                value = candidate
            }
            if value >= 1 {
                return 1
            }
        }
        return value
    }
}

/// Extracts symmetric displacement metrics and feature guards from one face.
///
/// The extractor never throws: a face it cannot use safely yields a warning and
/// no geometry, which keeps the pass a no-op for that face instead of failing
/// the whole frame.
enum FaceGeometryExtractor {
    struct Outcome {
        let geometry: FaceWarpGeometry?
        let warnings: [FaceWarpWarning]
    }

    static func extract(
        face: FaceObservation,
        faceIndex: Int,
        configuration: FaceWarpConfiguration,
        protectionMargin: Float
    ) -> Outcome {
        let rawBox = face.boundingBox
        guard rawBox.x.isFinite,
              rawBox.y.isFinite,
              rawBox.width.isFinite,
              rawBox.height.isFinite,
              rawBox.width > 0,
              rawBox.height > 0
        else {
            return Outcome(
                geometry: nil,
                warnings: [.degenerateFace(faceIndex: faceIndex)]
            )
        }
        let box = rawBox.clamped()
        guard box.width > 1e-5, box.height > 1e-5 else {
            return Outcome(
                geometry: nil,
                warnings: [.degenerateFace(faceIndex: faceIndex)]
            )
        }

        // Eye centres define both the symmetry axis and the upper boundary of
        // the deformation. Without them the safest choice is to skip the face.
        let leftEye = centroid(points(.leftEye, face: face, box: box))
            ?? centroid(points(.leftPupil, face: face, box: box))
        let rightEye = centroid(points(.rightEye, face: face, box: box))
            ?? centroid(points(.rightPupil, face: face, box: box))
        guard let leftEye, let rightEye else {
            return Outcome(
                geometry: nil,
                warnings: [.insufficientLandmarks(faceIndex: faceIndex)]
            )
        }

        let nose = points(.nose, face: face, box: box)
        let outerLips = points(.outerLips, face: face, box: box)
        let innerLips = points(.innerLips, face: face, box: box)
        guard !nose.isEmpty || !outerLips.isEmpty || !innerLips.isEmpty else {
            return Outcome(
                geometry: nil,
                warnings: [.insufficientLandmarks(faceIndex: faceIndex)]
            )
        }

        let centerX = (leftEye.x + rightEye.x) * 0.5
        let eyeY = (leftEye.y + rightEye.y) * 0.5
        let boxWidth = Float(box.width)
        let boxHeight = Float(box.height)
        let boxCenterX = Float(box.x + box.width * 0.5)
        guard abs(centerX - boxCenterX) <= boxWidth * 0.5,
              eyeY > Float(box.y),
              eyeY < Float(box.maxY)
        else {
            return Outcome(
                geometry: nil,
                warnings: [.degenerateFace(faceIndex: faceIndex)]
            )
        }

        let contour = points(.faceContour, face: face, box: box)
        var halfWidth = boxWidth * 0.5
        var chinY = Float(box.maxY)
        var isContourEstimated = false
        if contour.count >= 5 {
            var distances: [Float] = []
            distances.reserveCapacity(contour.count)
            var contourMaxY: Float = 0
            for point in contour {
                distances.append(abs(point.x - centerX))
                contourMaxY = max(contourMaxY, point.y)
            }
            distances.sort()
            let percentileIndex = min(
                Int(Float(distances.count) * 0.9),
                distances.count - 1
            )
            halfWidth = max(halfWidth, distances[percentileIndex])
            halfWidth = min(halfWidth, boxWidth * 0.75)
            let minimumChin = eyeY + boxHeight * 0.2
            chinY = min(max(contourMaxY, minimumChin), Float(box.maxY))
        } else {
            isContourEstimated = true
        }

        let faceHeight = chinY - eyeY
        guard faceHeight >= max(0.01, boxHeight * 0.15), halfWidth >= 0.005 else {
            return Outcome(
                geometry: nil,
                warnings: [.degenerateFace(faceIndex: faceIndex)]
            )
        }

        var guards: [FaceProtectionGuard] = []
        guards.reserveCapacity(14)
        appendGuards(
            for: points(.leftEye, face: face, box: box),
            centerX: centerX,
            faceWidth: halfWidth * 2,
            faceHeight: faceHeight,
            protectionMargin: protectionMargin,
            configuration: configuration,
            into: &guards
        )
        appendGuards(
            for: points(.rightEye, face: face, box: box),
            centerX: centerX,
            faceWidth: halfWidth * 2,
            faceHeight: faceHeight,
            protectionMargin: protectionMargin,
            configuration: configuration,
            into: &guards
        )
        appendGuards(
            for: points(.leftEyebrow, face: face, box: box),
            centerX: centerX,
            faceWidth: halfWidth * 2,
            faceHeight: faceHeight,
            protectionMargin: protectionMargin,
            configuration: configuration,
            into: &guards
        )
        appendGuards(
            for: points(.rightEyebrow, face: face, box: box),
            centerX: centerX,
            faceWidth: halfWidth * 2,
            faceHeight: faceHeight,
            protectionMargin: protectionMargin,
            configuration: configuration,
            into: &guards
        )
        appendGuards(
            for: nose,
            centerX: centerX,
            faceWidth: halfWidth * 2,
            faceHeight: faceHeight,
            protectionMargin: protectionMargin,
            configuration: configuration,
            into: &guards
        )
        appendGuards(
            for: outerLips,
            centerX: centerX,
            faceWidth: halfWidth * 2,
            faceHeight: faceHeight,
            protectionMargin: protectionMargin,
            configuration: configuration,
            into: &guards
        )
        appendGuards(
            for: innerLips,
            centerX: centerX,
            faceWidth: halfWidth * 2,
            faceHeight: faceHeight,
            protectionMargin: protectionMargin,
            configuration: configuration,
            into: &guards
        )

        let warnings: [FaceWarpWarning] = isContourEstimated
            ? [.missingFaceContour(faceIndex: faceIndex)]
            : []
        let confidence = face.confidence.isFinite ? face.confidence : 0
        return Outcome(
            geometry: FaceWarpGeometry(
                faceIndex: faceIndex,
                confidence: confidence,
                areaFraction: boxWidth * boxHeight,
                centerX: centerX,
                eyeY: eyeY,
                chinY: chinY,
                halfWidth: halfWidth,
                guards: guards,
                isContourEstimated: isContourEstimated
            ),
            warnings: warnings
        )
    }

    /// Converts a landmark region to guarded points inside the image.
    ///
    /// Points far outside the (slightly expanded) bounding box are ignored so a
    /// single stray landmark cannot drag the symmetry axis or a guard.
    private static func points(
        _ kind: FaceLandmarkKind,
        face: FaceObservation,
        box: NormalizedRect
    ) -> [SIMD2<Float>] {
        let marginX = Float(box.width * 0.15)
        let marginY = Float(box.height * 0.15)
        let minX = Float(box.x) - marginX
        let maxX = Float(box.maxX) + marginX
        let minY = Float(box.y) - marginY
        let maxY = Float(box.maxY) + marginY
        var result: [SIMD2<Float>] = []
        for point in face.points(for: kind) {
            guard point.x.isFinite, point.y.isFinite else { continue }
            let x = Float(point.x)
            let y = Float(point.y)
            guard x >= minX, x <= maxX, y >= minY, y <= maxY else { continue }
            result.append(
                SIMD2<Float>(
                    min(max(x, 0), 1),
                    min(max(y, 0), 1)
                )
            )
        }
        return result
    }

    private static func centroid(_ points: [SIMD2<Float>]) -> SIMD2<Float>? {
        guard !points.isEmpty else { return nil }
        var sum = SIMD2<Float>(0, 0)
        for point in points {
            sum += point
        }
        return sum * (1 / Float(points.count))
    }

    /// Adds a guard and its mirror image around `centerX`.
    private static func appendGuards(
        for points: [SIMD2<Float>],
        centerX: Float,
        faceWidth: Float,
        faceHeight: Float,
        protectionMargin: Float,
        configuration: FaceWarpConfiguration,
        into guards: inout [FaceProtectionGuard]
    ) {
        guard let first = points.first else { return }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        let featureWidth = maxX - minX
        let featureHeight = maxY - minY
        let padX = max(
            protectionMargin,
            max(faceWidth * 0.03, featureWidth * 0.25)
        )
        let padY = max(
            protectionMargin,
            max(faceHeight * 0.025, featureHeight * 0.35)
        )
        let feather = configuration.featureProtectionFeather
        let guardedMinX = minX - padX
        let guardedMaxX = maxX + padX
        let guardedMinY = minY - padY
        let guardedMaxY = maxY + padY

        guards.append(
            FaceProtectionGuard(
                minX: guardedMinX,
                maxX: guardedMaxX,
                minY: guardedMinY,
                maxY: guardedMaxY,
                feather: feather
            )
        )

        let mirroredMinX = 2 * centerX - guardedMaxX
        let mirroredMaxX = 2 * centerX - guardedMinX
        guard abs(mirroredMinX - guardedMinX) > 1e-6 else {
            return
        }
        guards.append(
            FaceProtectionGuard(
                minX: mirroredMinX,
                maxX: mirroredMaxX,
                minY: guardedMinY,
                maxY: guardedMaxY,
                feather: feather
            )
        )
    }
}
