import Foundation
import StyleToneCore

/// Builds a feathered protection mask for eyes, eyebrows, pupils and lips.
///
/// A production skin mask already excludes facial features, but retouch must
/// stay safe when a caller supplies a coarse mask (for example the ellipse
/// fixture used by integration tests). The guard is derived only from
/// normalised landmarks; no identity or skin-tone information is used.
enum FeatureGuardMask {
    static func make(analysis: PortraitAnalysis, imageSize: PixelSize) -> [UInt8]? {
        guard imageSize.isPositive,
              analysis.faces.isEmpty == false
        else {
            return nil
        }
        let (pixelCount, overflow) = imageSize.width.multipliedReportingOverflow(
            by: imageSize.height
        )
        guard !overflow, pixelCount > 0 else { return nil }

        var mask = [UInt8](repeating: 0, count: pixelCount)
        var didDraw = false

        for face in analysis.faces {
            let rect = face.boundingBox.clamped()
            let faceWidth = rect.width * Double(imageSize.width)
            let faceHeight = rect.height * Double(imageSize.height)
            guard faceWidth >= 2, faceHeight >= 2 else { continue }
            let padding = max(
                2,
                Int((0.018 * min(faceWidth, faceHeight)).rounded())
            )

            for kind in [FaceLandmarkKind.leftEye, .rightEye] {
                let points = face.points(for: kind)
                if fillContour(
                    points: points,
                    padding: Double(padding),
                    imageSize: imageSize,
                    mask: &mask
                ) {
                    didDraw = true
                }
            }

            let lips = face.points(for: .outerLips)
            if fillContour(
                points: lips,
                padding: Double(padding),
                imageSize: imageSize,
                mask: &mask
            ) {
                didDraw = true
            }

            for kind in [FaceLandmarkKind.leftEyebrow, .rightEyebrow] {
                let points = face.points(for: kind)
                if fillPolyline(
                    points: points,
                    radius: Double(max(1, padding / 2)),
                    imageSize: imageSize,
                    mask: &mask
                ) {
                    didDraw = true
                }
            }

            for kind in [FaceLandmarkKind.leftPupil, .rightPupil] {
                let points = face.points(for: kind)
                for point in points {
                    fillCircle(
                        center: point,
                        radius: Double(padding),
                        imageSize: imageSize,
                        mask: &mask
                    )
                    didDraw = true
                }
            }
        }

        guard didDraw else { return nil }
        return feather(mask, width: imageSize.width, height: imageSize.height)
    }

    // MARK: - Rasterisation

    @discardableResult
    private static func fillContour(
        points: [NormalizedPoint],
        padding: Double,
        imageSize: PixelSize,
        mask: inout [UInt8]
    ) -> Bool {
        guard points.count >= 3 else { return false }
        var pixelPoints = points.map {
            let point = $0.clamped()
            return SIMD2<Double>(
                point.x * Double(imageSize.width),
                point.y * Double(imageSize.height)
            )
        }

        var centroid = SIMD2<Double>(0, 0)
        for point in pixelPoints {
            centroid += point
        }
        centroid /= Double(pixelPoints.count)
        var meanRadius = 0.0
        for point in pixelPoints {
            meanRadius += length(point - centroid)
        }
        meanRadius /= Double(pixelPoints.count)
        let scale = 1 + padding / max(meanRadius, 0.5)
        for index in pixelPoints.indices {
            pixelPoints[index] = centroid + (pixelPoints[index] - centroid) * scale
        }

        let width = imageSize.width
        let height = imageSize.height
        let minX = max(
            0,
            Int(pixelPoints.map { $0.x }.min()?.rounded(.down) ?? 0)
        )
        let maxX = min(
            width - 1,
            Int(pixelPoints.map { $0.x }.max()?.rounded(.up) ?? 0)
        )
        let minY = max(
            0,
            Int(pixelPoints.map { $0.y }.min()?.rounded(.down) ?? 0)
        )
        let maxY = min(
            height - 1,
            Int(pixelPoints.map { $0.y }.max()?.rounded(.up) ?? 0)
        )
        guard minX <= maxX, minY <= maxY else { return false }

        var intersections: [Double] = []
        intersections.reserveCapacity(8)
        var didFill = false
        for y in minY ... maxY {
            let scanY = Double(y) + 0.5
            intersections.removeAll(keepingCapacity: true)
            for index in pixelPoints.indices {
                let first = pixelPoints[index]
                let second = pixelPoints[(index + 1) % pixelPoints.count]
                guard (first.y <= scanY && second.y > scanY)
                    || (second.y <= scanY && first.y > scanY)
                else {
                    continue
                }
                let denominator = second.y - first.y
                guard abs(denominator) > 1e-9 else { continue }
                let x = first.x + (scanY - first.y) * (second.x - first.x) / denominator
                intersections.append(x)
            }
            guard intersections.count >= 2 else { continue }
            intersections.sort()
            var pairIndex = 0
            while pairIndex + 1 < intersections.count {
                let startX = intersections[pairIndex]
                let endX = intersections[pairIndex + 1]
                let start = max(minX, Int(startX.rounded(.down)))
                let end = min(maxX, Int(endX.rounded(.up)))
                if start <= end {
                    for x in start ... end {
                        let center = Double(x) + 0.5
                        if center >= startX, center <= endX {
                            mask[y * width + x] = 255
                            didFill = true
                        }
                    }
                }
                pairIndex += 2
            }
        }
        return didFill
    }

    @discardableResult
    private static func fillPolyline(
        points: [NormalizedPoint],
        radius: Double,
        imageSize: PixelSize,
        mask: inout [UInt8]
    ) -> Bool {
        guard points.count >= 2 else { return false }
        let pixelPoints = points.map {
            let point = $0.clamped()
            return SIMD2<Double>(
                point.x * Double(imageSize.width),
                point.y * Double(imageSize.height)
            )
        }
        var didFill = false
        for index in 0 ..< (pixelPoints.count - 1) {
            if fillCapsule(
                start: pixelPoints[index],
                end: pixelPoints[index + 1],
                radius: radius,
                imageSize: imageSize,
                mask: &mask
            ) {
                didFill = true
            }
        }
        return didFill
    }

    @discardableResult
    private static func fillCapsule(
        start: SIMD2<Double>,
        end: SIMD2<Double>,
        radius: Double,
        imageSize: PixelSize,
        mask: inout [UInt8]
    ) -> Bool {
        let width = imageSize.width
        let height = imageSize.height
        let minX = max(0, Int((min(start.x, end.x) - radius).rounded(.down)))
        let maxX = min(width - 1, Int((max(start.x, end.x) + radius).rounded(.up)))
        let minY = max(0, Int((min(start.y, end.y) - radius).rounded(.down)))
        let maxY = min(height - 1, Int((max(start.y, end.y) + radius).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return false }

        let segment = end - start
        let segmentLengthSquared = lengthSquared(segment)
        var didFill = false
        for y in minY ... maxY {
            let centerY = Double(y) + 0.5
            for x in minX ... maxX {
                let centerX = Double(x) + 0.5
                let point = SIMD2<Double>(centerX, centerY)
                let distanceSquared: Double
                if segmentLengthSquared <= 1e-9 {
                    distanceSquared = lengthSquared(point - start)
                } else {
                    let projection = min(
                        max(dot(point - start, segment) / segmentLengthSquared, 0),
                        1
                    )
                    let closest = start + segment * projection
                    distanceSquared = lengthSquared(point - closest)
                }
                if distanceSquared <= radius * radius {
                    mask[y * width + x] = 255
                    didFill = true
                }
            }
        }
        return didFill
    }

    private static func fillCircle(
        center: NormalizedPoint,
        radius: Double,
        imageSize: PixelSize,
        mask: inout [UInt8]
    ) {
        let width = imageSize.width
        let height = imageSize.height
        let clampedCenter = center.clamped()
        let centerX = clampedCenter.x * Double(width)
        let centerY = clampedCenter.y * Double(height)
        let minX = max(0, Int((centerX - radius).rounded(.down)))
        let maxX = min(width - 1, Int((centerX + radius).rounded(.up)))
        let minY = max(0, Int((centerY - radius).rounded(.down)))
        let maxY = min(height - 1, Int((centerY + radius).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }
        let radiusSquared = radius * radius
        for y in minY ... maxY {
            let dy = Double(y) + 0.5 - centerY
            for x in minX ... maxX {
                let dx = Double(x) + 0.5 - centerX
                if dx * dx + dy * dy <= radiusSquared {
                    mask[y * width + x] = 255
                }
            }
        }
    }

    // MARK: - Geometry helpers

    @inline(__always)
    private static func length(_ value: SIMD2<Double>) -> Double {
        (value.x * value.x + value.y * value.y).squareRoot()
    }

    @inline(__always)
    private static func lengthSquared(_ value: SIMD2<Double>) -> Double {
        value.x * value.x + value.y * value.y
    }

    @inline(__always)
    private static func dot(_ first: SIMD2<Double>, _ second: SIMD2<Double>) -> Double {
        first.x * second.x + first.y * second.y
    }

    // MARK: - Feathering

    private static func feather(
        _ mask: [UInt8],
        width: Int,
        height: Int
    ) -> [UInt8] {
        guard width > 0, height > 0, mask.count == width * height else {
            return mask
        }
        var horizontal = [UInt8](repeating: 0, count: mask.count)
        for y in 0 ..< height {
            let row = y * width
            for x in 0 ..< width {
                let left = Int(mask[row + max(x - 1, 0)])
                let center = Int(mask[row + x])
                let right = Int(mask[row + min(x + 1, width - 1)])
                horizontal[row + x] = UInt8((left + center + right) / 3)
            }
        }

        var vertical = [UInt8](repeating: 0, count: mask.count)
        for y in 0 ..< height {
            let row = y * width
            let previous = max(y - 1, 0) * width
            let next = min(y + 1, height - 1) * width
            for x in 0 ..< width {
                vertical[row + x] = UInt8(
                    (Int(horizontal[previous + x]) +
                        Int(horizontal[row + x]) +
                        Int(horizontal[next + x])) / 3
                )
            }
        }
        return vertical
    }
}
