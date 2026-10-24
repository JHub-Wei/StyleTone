import CoreGraphics
import Foundation
import StyleToneCore
import StyleToneImaging

/// Result of the skin-probability model.
struct SkinMaskResult {
    let mask: MaskBuffer
    let coverage: Double
    let meanProbability: Double
    let lowConfidence: Bool
}

/// Builds a skin-probability mask from face ellipses and adaptive YCbCr
/// statistics.
///
/// The model is deliberately skin-agnostic: it learns the chroma centre of the
/// pixels inside each face and scores similarity to that centre. It never
/// classifies a skin tone and never compares faces. Eyes, eyebrows and lips are
/// excluded from the mask so retouching cannot smear them.
struct SkinMaskBuilder {
    struct Configuration: Sendable, Equatable {
        /// Minimum probability that counts as skin for coverage metrics.
        var skinThreshold: Double
        /// Width of the ellipse edge feather, as a fraction of the radius.
        var featherWidth: Double

        init(skinThreshold: Double = 0.35, featherWidth: Double = 0.12) {
            self.skinThreshold = min(max(skinThreshold, 0), 1)
            self.featherWidth = min(max(featherWidth, 0.01), 0.5)
        }
    }

    private struct ChromaStatistics {
        let luma: Double
        let cb: Double
        let cr: Double
        let sigmaLuma: Double
        let sigmaCb: Double
        let sigmaCr: Double
    }

    private struct Ellipse {
        let centerX: Double
        let centerY: Double
        let radiusX: Double
        let radiusY: Double

        func normalizedRadius(x: Double, y: Double) -> Double {
            let dx = (x - centerX) / max(radiusX, 0.0001)
            let dy = (y - centerY) / max(radiusY, 0.0001)
            return (dx * dx + dy * dy).squareRoot()
        }

        func exclusionWeight(x: Double, y: Double) -> Double {
            let radius = normalizedRadius(x: x, y: y)
            if radius <= 0.70 { return 0 }
            if radius >= 1.10 { return 1 }
            return (radius - 0.70) / 0.40
        }
    }

    let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Convenience for tests and callers that already hold an `ImageAsset`.
    func build(image: ImageAsset, faces: [FaceObservation]) throws -> SkinMaskResult? {
        guard !faces.isEmpty else { return nil }
        let linear = try ColorPipeline().linearize(image)
        return try build(linearImage: linear, faces: faces)
    }

    func build(linearImage: LinearImage, faces: [FaceObservation]) throws -> SkinMaskResult? {
        guard !faces.isEmpty else { return nil }
        let width = linearImage.width
        let height = linearImage.height
        guard width > 0, height > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: width * height)
        var skinPixelCount = 0
        var faceAreaCount = 0
        var probabilitySum = 0.0

        for face in faces {
            try Task.checkCancellation()
            let region = makeFaceRegion(face: face, width: width, height: height)
            guard let region else { continue }
            let statistics = sampleStatistics(
                linearImage: linearImage,
                ellipse: region.ellipse
            )
            let exclusions = makeExclusions(
                face: face,
                width: width,
                height: height
            )

            let minX = max(0, Int((region.ellipse.centerX - region.ellipse.radiusX).rounded(.down)))
            let maxX = min(width - 1, Int((region.ellipse.centerX + region.ellipse.radiusX).rounded(.up)))
            let minY = max(0, Int((region.ellipse.centerY - region.ellipse.radiusY).rounded(.down)))
            let maxY = min(height - 1, Int((region.ellipse.centerY + region.ellipse.radiusY).rounded(.up)))
            guard minX <= maxX, minY <= maxY else { continue }

            for y in minY ... maxY {
                let pixelY = Double(y) + 0.5
                let row = y * width
                for x in minX ... maxX {
                    let pixelX = Double(x) + 0.5
                    let radius = region.ellipse.normalizedRadius(x: pixelX, y: pixelY)
                    guard radius < 1 else { continue }
                    faceAreaCount += 1

                    let pixel = linearImage.pixels[row + x]
                    guard pixel.w >= 0.5 else { continue }
                    let ycbcr = yCbCr(from: pixel)
                    if ycbcr.x < 0.06 { continue }

                    var probability = skinProbability(ycbcr: ycbcr, statistics: statistics)
                    let spatialWeight = radius <= 1 - configuration.featherWidth
                        ? 1
                        : (1 - radius) / configuration.featherWidth
                    probability *= spatialWeight

                    for exclusion in exclusions {
                        probability *= exclusion.exclusionWeight(x: pixelX, y: pixelY)
                        if probability <= 0 { break }
                    }

                    let value = min(max(probability, 0), 1)
                    probabilitySum += value
                    if value >= configuration.skinThreshold {
                        skinPixelCount += 1
                    }
                    let byte = UInt8(min(max(Int((value * 255).rounded()), 0), 255))
                    if byte > bytes[row + x] {
                        bytes[row + x] = byte
                    }
                }
            }
        }

        let mask = try MaskBuffer(width: width, height: height, bytes: Data(bytes))
        let coverage = faceAreaCount > 0 ? Double(skinPixelCount) / Double(faceAreaCount) : 0
        let meanProbability = faceAreaCount > 0 ? probabilitySum / Double(faceAreaCount) : 0
        return SkinMaskResult(
            mask: mask,
            coverage: coverage,
            meanProbability: meanProbability,
            lowConfidence: coverage < 0.20 || meanProbability < 0.40
        )
    }

    private struct FaceRegion {
        let ellipse: Ellipse
    }

    private func makeFaceRegion(face: FaceObservation, width: Int, height: Int) -> FaceRegion? {
        let box = face.boundingBox.clamped()
        guard box.width > 0.001, box.height > 0.001 else { return nil }
        let centerX = (box.x + box.width / 2) * Double(width)
        let centerY = (box.y + box.height * 0.52) * Double(height)
        let radiusX = max(2, box.width * Double(width) * 0.52)
        let radiusY = max(2, box.height * Double(height) * 0.62)
        return FaceRegion(
            ellipse: Ellipse(
                centerX: centerX,
                centerY: centerY,
                radiusX: radiusX,
                radiusY: radiusY
            )
        )
    }

    private func sampleStatistics(
        linearImage: LinearImage,
        ellipse: Ellipse
    ) -> ChromaStatistics {
        let width = linearImage.width
        let height = linearImage.height
        let innerRadiusX = ellipse.radiusX * 0.78
        let innerRadiusY = ellipse.radiusY * 0.78
        let minX = max(0, Int((ellipse.centerX - innerRadiusX).rounded(.down)))
        let maxX = min(width - 1, Int((ellipse.centerX + innerRadiusX).rounded(.up)))
        let minY = max(0, Int((ellipse.centerY - innerRadiusY).rounded(.down)))
        let maxY = min(height - 1, Int((ellipse.centerY + innerRadiusY).rounded(.up)))

        var lumaValues: [Double] = []
        var cbValues: [Double] = []
        var crValues: [Double] = []
        let step = max(1, Int(min(innerRadiusX, innerRadiusY) / 24.0))

        if minX <= maxX, minY <= maxY {
            for y in stride(from: minY, through: maxY, by: step) {
                let pixelY = Double(y) + 0.5
                let row = y * width
                for x in stride(from: minX, through: maxX, by: step) {
                    let pixelX = Double(x) + 0.5
                    let radius = ellipse.normalizedRadius(x: pixelX, y: pixelY)
                    guard radius < 0.80 else { continue }
                    let pixel = linearImage.pixels[row + x]
                    guard pixel.w >= 0.5 else { continue }
                    let ycbcr = yCbCr(from: pixel)
                    guard ycbcr.x >= 0.05 else { continue }
                    lumaValues.append(Double(ycbcr.x))
                    cbValues.append(Double(ycbcr.y))
                    crValues.append(Double(ycbcr.z))
                }
            }
        }

        guard lumaValues.count >= 32 else {
            return ChromaStatistics(
                luma: 0.62,
                cb: 0.40,
                cr: 0.60,
                sigmaLuma: 0.18,
                sigmaCb: 0.045,
                sigmaCr: 0.045
            )
        }

        let luma = median(lumaValues)
        let cb = median(cbValues)
        let cr = median(crValues)
        return ChromaStatistics(
            luma: luma,
            cb: cb,
            cr: cr,
            sigmaLuma: max(0.10, medianAbsoluteDeviation(lumaValues, center: luma) * 1.4826),
            sigmaCb: max(0.028, medianAbsoluteDeviation(cbValues, center: cb) * 1.4826),
            sigmaCr: max(0.028, medianAbsoluteDeviation(crValues, center: cr) * 1.4826)
        )
    }

    private func yCbCr(from pixel: SIMD4<Float>) -> SIMD3<Float> {
        let srgb = ImageStatistics.encodedSRGB(pixel)
        let luma = ImageStatistics.luma(srgb)
        let cb = 0.564 * (srgb.z - luma) + 0.5
        let cr = 0.713 * (srgb.x - luma) + 0.5
        return SIMD3<Float>(
            ImageStatistics.clamp01(luma),
            ImageStatistics.clamp01(cb),
            ImageStatistics.clamp01(cr)
        )
    }

    private func skinProbability(
        ycbcr: SIMD3<Float>,
        statistics: ChromaStatistics
    ) -> Double {
        let luma = Double(ycbcr.x)
        let cb = Double(ycbcr.y)
        let cr = Double(ycbcr.z)

        let dLuma = (luma - statistics.luma) / max(statistics.sigmaLuma, 0.06)
        let dCb = (cb - statistics.cb) / max(statistics.sigmaCb, 0.02)
        let dCr = (cr - statistics.cr) / max(statistics.sigmaCr, 0.02)
        let adaptive = exp(-0.5 * (dCb * dCb + dCr * dCr + 0.35 * dLuma * dLuma))

        let canonicalCb = (cb - 0.40) / 0.10
        let canonicalCr = (cr - 0.60) / 0.075
        let canonical = exp(-0.5 * (canonicalCb * canonicalCb + canonicalCr * canonicalCr))

        // Neutral pixels (grey, white, black) sit at Cb == Cr == 0.5. Without
        // this gate the adaptive model would happily call them skin.
        let chromaDistance = abs(cb - 0.5) + abs(cr - 0.5)
        let chromaGate = min(1, max(0, (chromaDistance - 0.015) / 0.035))
        return min(1, adaptive * (0.55 + 0.45 * canonical) * chromaGate)
    }

    private func makeExclusions(
        face: FaceObservation,
        width: Int,
        height: Int
    ) -> [Ellipse] {
        var exclusions: [Ellipse] = []
        let box = face.boundingBox.clamped()
        let boxWidth = box.width * Double(width)
        let boxHeight = box.height * Double(height)
        let centerX = (box.x + box.width / 2) * Double(width)
        let top = box.y * Double(height)

        addLandmarkExclusion(
            kind: .leftEye,
            face: face,
            width: width,
            height: height,
            minimumPoints: 2,
            to: &exclusions
        )
        addLandmarkExclusion(
            kind: .rightEye,
            face: face,
            width: width,
            height: height,
            minimumPoints: 2,
            to: &exclusions
        )
        addLandmarkExclusion(
            kind: .leftEyebrow,
            face: face,
            width: width,
            height: height,
            minimumPoints: 2,
            to: &exclusions
        )
        addLandmarkExclusion(
            kind: .rightEyebrow,
            face: face,
            width: width,
            height: height,
            minimumPoints: 2,
            to: &exclusions
        )
        addLandmarkExclusion(
            kind: .outerLips,
            face: face,
            width: width,
            height: height,
            minimumPoints: 3,
            to: &exclusions
        )

        if face.points(for: .leftEye).count < 2 {
            exclusions.append(
                Ellipse(
                    centerX: centerX - boxWidth * 0.19,
                    centerY: top + boxHeight * 0.40,
                    radiusX: max(3, boxWidth * 0.13),
                    radiusY: max(2, boxHeight * 0.08)
                )
            )
        }
        if face.points(for: .rightEye).count < 2 {
            exclusions.append(
                Ellipse(
                    centerX: centerX + boxWidth * 0.19,
                    centerY: top + boxHeight * 0.40,
                    radiusX: max(3, boxWidth * 0.13),
                    radiusY: max(2, boxHeight * 0.08)
                )
            )
        }
        if face.points(for: .outerLips).count < 3 {
            exclusions.append(
                Ellipse(
                    centerX: centerX,
                    centerY: top + boxHeight * 0.74,
                    radiusX: max(3, boxWidth * 0.22),
                    radiusY: max(2, boxHeight * 0.10)
                )
            )
        }
        return exclusions
    }

    private func addLandmarkExclusion(
        kind: FaceLandmarkKind,
        face: FaceObservation,
        width: Int,
        height: Int,
        minimumPoints: Int,
        to exclusions: inout [Ellipse]
    ) {
        let points = face.points(for: kind)
        guard points.count >= minimumPoints else { return }
        var minX = 1.0
        var maxX = 0.0
        var minY = 1.0
        var maxY = 0.0
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let centerX = (minX + maxX) / 2 * Double(width)
        let centerY = (minY + maxY) / 2 * Double(height)
        let radiusX = max(2, (maxX - minX) / 2 * Double(width))
        let radiusY = max(2, (maxY - minY) / 2 * Double(height))
        let padding = max(1.5, max(radiusX, radiusY) * 0.18)
        exclusions.append(
            Ellipse(
                centerX: centerX,
                centerY: centerY,
                radiusX: radiusX + padding,
                radiusY: radiusY + padding
            )
        )
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func medianAbsoluteDeviation(_ values: [Double], center: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let deviations = values.map { abs($0 - center) }
        return median(deviations)
    }
}
