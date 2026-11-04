import CoreGraphics
import Foundation
import StyleToneCore
import StyleToneLearning

// MARK: - Shared

enum PairEditMath {
    static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    static func reduction(original: Double, edited: Double, floor: Double = 0.02) -> Double {
        guard original.isFinite, edited.isFinite, original > floor else { return 0 }
        return clamp((original - edited) / original, 0, 1)
    }

    static func relativeChange(original: Double, edited: Double, floor: Double = 0.01) -> Double {
        guard original.isFinite, edited.isFinite, original > floor else { return 0 }
        return (edited - original) / original
    }
}

// MARK: - Face

struct FaceShape {
    let widthRatio: Double
    let jawRatio: Double
    let confidence: Double
}

enum FaceEditMetrics {
    static func shape(of face: FaceObservation?) -> FaceShape? {
        guard let face else { return nil }
        let contour = face.points(for: .faceContour)
        if contour.count >= 6 {
            let minX = contour.map(\.x).min() ?? 0
            let maxX = contour.map(\.x).max() ?? 0
            let minY = contour.map(\.y).min() ?? 0
            let maxY = contour.map(\.y).max() ?? 0
            let height = maxY - minY
            let width = maxX - minX
            guard height > 0.01, width > 0.01 else { return nil }

            let jawY = minY + height * 0.70
            let jaw = contour.filter { $0.y >= jawY }
            let jawWidth = (jaw.map(\.x).max() ?? maxX) - (jaw.map(\.x).min() ?? minX)
            guard jawWidth > 0.005 else { return nil }
            return FaceShape(
                widthRatio: width / height,
                jawRatio: jawWidth / height,
                confidence: Double(face.confidence)
            )
        }

        let box = face.boundingBox
        guard box.height > 0.01, box.width > 0.01 else { return nil }
        return FaceShape(
            widthRatio: box.width / box.height,
            jawRatio: box.width / box.height * 0.72,
            confidence: Double(face.confidence) * 0.7
        )
    }

    static func compare(
        original: FaceObservation?,
        edited: FaceObservation?
    ) -> (slim: Double, jaw: Double, confidence: Double)? {
        guard let lhs = shape(of: original),
              let rhs = shape(of: edited)
        else {
            return nil
        }

        let slim = PairEditMath.clamp(
            PairEditMath.reduction(original: lhs.widthRatio, edited: rhs.widthRatio) * 30,
            0,
            1
        )
        let jaw = PairEditMath.clamp(
            PairEditMath.reduction(original: lhs.jawRatio, edited: rhs.jawRatio) * 30,
            0,
            1
        )
        guard slim >= 0.02 || jaw >= 0.02 else { return nil }
        return (slim, jaw, min(lhs.confidence, rhs.confidence))
    }
}

// MARK: - Body

struct BodyProfile {
    let heights: [Double]
    let confidence: Double
    let boundingBox: NormalizedRect

    func width(at relativeY: Double) -> Double? {
        guard !heights.isEmpty else { return nil }
        let position = PairEditMath.clamp(relativeY, 0, 0.999)
        let index = Int(position * Double(heights.count))
        let value = heights[min(index, heights.count - 1)]
        return value > 0.01 ? value : nil
    }
}

enum BodyEditMetrics {
    private static let grid = 64

    static func profile(of analysis: PortraitAnalysis) -> BodyProfile? {
        guard let mask = analysis.personMask else { return nil }

        var occupancy = [Bool](repeating: false, count: grid * grid)
        var minX = grid
        var maxX = -1
        var minY = grid
        var maxY = -1

        for gy in 0..<grid {
            for gx in 0..<grid {
                let nx = (Double(gx) + 0.5) / Double(grid)
                let ny = (Double(gy) + 0.5) / Double(grid)
                let x = Int(nx * Double(mask.width - 1))
                let y = Int(ny * Double(mask.height - 1))
                let value = mask.normalizedValue(x: x, y: y) ?? 0
                guard value >= 0.35 else { continue }
                occupancy[gy * grid + gx] = true
                minX = min(minX, gx)
                maxX = max(maxX, gx)
                minY = min(minY, gy)
                maxY = max(maxY, gy)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        let bodyHeight = Double(maxY - minY + 1)
        guard bodyHeight >= 8 else { return nil }

        var widths = [Double](repeating: 0, count: maxY - minY + 1)
        for gy in minY...maxY {
            var count = 0
            for gx in minX...maxX where occupancy[gy * grid + gx] {
                count += 1
            }
            widths[gy - minY] = Double(count) / bodyHeight
        }

        let confidence = Double(analysis.body?.confidence ?? 0.55)
        let box = NormalizedRect(
            x: Double(minX) / Double(grid),
            y: Double(minY) / Double(grid),
            width: Double(maxX - minX + 1) / Double(grid),
            height: Double(maxY - minY + 1) / Double(grid)
        )
        return BodyProfile(heights: widths, confidence: confidence, boundingBox: box)
    }

    static func compare(
        original: PortraitAnalysis,
        edited: PortraitAnalysis
    ) -> (arm: Double?, waist: Double?, leg: Double?, legLength: Double?, confidence: Double)? {
        guard let lhs = profile(of: original), let rhs = profile(of: edited) else {
            return nil
        }

        func strength(at y: Double, multiplier: Double) -> Double? {
            guard let a = lhs.width(at: y), let b = rhs.width(at: y) else { return nil }
            let value = PairEditMath.clamp(
                PairEditMath.reduction(original: a, edited: b) * multiplier,
                0,
                1
            )
            return value >= 0.02 ? value : nil
        }

        let waist = strength(at: 0.46, multiplier: 10)
        let arm = strength(at: 0.29, multiplier: 10)
        let leg = strength(at: 0.78, multiplier: 10)

        var legLength: Double?
        if let originalLeg = legSpan(of: original, profile: lhs),
           let editedLeg = legSpan(of: edited, profile: rhs) {
            let change = PairEditMath.relativeChange(
                original: originalLeg,
                edited: editedLeg
            )
            if change > 0.01 {
                legLength = PairEditMath.clamp(1 + change * 1.5, 1, 1.08)
            }
        }

        guard waist != nil || arm != nil || leg != nil || legLength != nil else {
            return nil
        }
        return (
            arm,
            waist,
            leg,
            legLength,
            min(lhs.confidence, rhs.confidence)
        )
    }

    private static func legSpan(of analysis: PortraitAnalysis, profile: BodyProfile) -> Double? {
        guard let body = analysis.body,
              let leftHip = body.point(for: .leftHip),
              let rightHip = body.point(for: .rightHip),
              let leftAnkle = body.point(for: .leftAnkle),
              let rightAnkle = body.point(for: .rightAnkle)
        else {
            return nil
        }
        let hipY = (leftHip.y + rightHip.y) / 2
        let ankleY = (leftAnkle.y + rightAnkle.y) / 2
        let span = abs(ankleY - hipY)
        guard span > 0.01, profile.boundingBox.height > 0.01 else { return nil }
        return span / profile.boundingBox.height
    }
}

// MARK: - Skin texture

struct ImageSampler {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(image: ImageAsset, maxEdge: Int = 384) throws {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw StyleToneError.invalidImage
        }
        let scale = min(1, Double(maxEdge) / Double(max(sourceWidth, sourceHeight)))
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return
            }
            context.interpolationQuality = .medium
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(
                image.cgImage,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
        }

        self.width = width
        self.height = height
        self.bytes = pixels
    }

    func luma(x: Int, y: Int) -> Double? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let offset = (y * width + x) * 4
        let red = Double(bytes[offset])
        let green = Double(bytes[offset + 1])
        let blue = Double(bytes[offset + 2])
        return (0.299 * red + 0.587 * green + 0.114 * blue) / 255
    }
}

struct SkinTexture {
    let fineEnergy: Double
    let regionalVariation: Double
    let fineP99: Double
    let sampleCount: Int
    let confidence: Double
}

enum SkinEditMetrics {
    static func texture(
        of analysis: PortraitAnalysis,
        sampler: ImageSampler
    ) -> SkinTexture? {
        guard let face = analysis.primaryFace,
              let mask = analysis.skinMask
        else {
            return nil
        }
        let box = face.boundingBox
        let x0 = max(0, Int((box.minX + 0.03) * Double(sampler.width - 1)))
        let x1 = min(sampler.width - 1, Int((box.maxX - 0.03) * Double(sampler.width - 1)))
        let y0 = max(0, Int((box.minY + 0.03) * Double(sampler.height - 1)))
        let y1 = min(sampler.height - 1, Int((box.maxY - 0.03) * Double(sampler.height - 1)))
        guard x1 > x0 + 4, y1 > y0 + 4 else { return nil }

        var residuals = [Double]()
        var cellSums = [Double](repeating: 0, count: 9)
        var cellCounts = [Int](repeating: 0, count: 9)
        let sampleStride = max(1, min(x1 - x0, y1 - y0) / 128)

        for y in stride(from: y0, through: y1, by: sampleStride) {
            for x in stride(from: x0, through: x1, by: sampleStride) {
                let nx = Double(x) / Double(sampler.width - 1)
                let ny = Double(y) / Double(sampler.height - 1)
                let maskX = Int(nx * Double(mask.width - 1))
                let maskY = Int(ny * Double(mask.height - 1))
                guard (mask.normalizedValue(x: maskX, y: maskY) ?? 0) >= 0.45,
                      let center = sampler.luma(x: x, y: y)
                else {
                    continue
                }

                var sum = 0.0
                var count = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        if let value = sampler.luma(x: x + dx, y: y + dy) {
                            sum += value
                            count += 1
                        }
                    }
                }
                guard count > 0 else { continue }
                residuals.append(abs(center - sum / Double(count)))

                let column = min(2, max(0, (nx - box.minX) / max(box.width, 0.01) * 3))
                let row = min(2, max(0, (ny - box.minY) / max(box.height, 0.01) * 3))
                let cell = Int(row) * 3 + Int(column)
                cellSums[cell] += center
                cellCounts[cell] += 1
            }
        }

        guard residuals.count >= 150 else { return nil }
        let fine = residuals.reduce(0, +) / Double(residuals.count)
        let sorted = residuals.sorted()
        let p99 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]

        let regionMeans = (0..<9).compactMap { index -> Double? in
            guard cellCounts[index] > 0 else { return nil }
            return cellSums[index] / Double(cellCounts[index])
        }
        guard regionMeans.count >= 3 else { return nil }
        let mean = regionMeans.reduce(0, +) / Double(regionMeans.count)
        let variance = regionMeans.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(regionMeans.count)

        return SkinTexture(
            fineEnergy: fine,
            regionalVariation: variance.squareRoot(),
            fineP99: p99,
            sampleCount: residuals.count,
            confidence: Double(face.confidence) * min(1, Double(residuals.count) / 500)
        )
    }

    static func compare(
        original: PortraitAnalysis,
        edited: PortraitAnalysis,
        originalImage: ImageAsset,
        editedImage: ImageAsset
    ) throws -> (smoothing: Double?, evenness: Double?, blemish: Double?, confidence: Double)? {
        let originalSampler = try ImageSampler(image: originalImage)
        let editedSampler = try ImageSampler(image: editedImage)
        guard let lhs = texture(of: original, sampler: originalSampler),
              let rhs = texture(of: edited, sampler: editedSampler)
        else {
            return nil
        }

        let smoothing = PairEditMath.clamp(
            PairEditMath.reduction(original: lhs.fineEnergy, edited: rhs.fineEnergy) * 12,
            0,
            1
        )
        let evenness = PairEditMath.clamp(
            PairEditMath.reduction(
                original: lhs.regionalVariation,
                edited: rhs.regionalVariation
            ) * 10,
            0,
            1
        )
        let blemish = PairEditMath.clamp(
            PairEditMath.reduction(original: lhs.fineP99, edited: rhs.fineP99) * 10,
            0,
            1
        )

        let result = (
            smoothing: smoothing >= 0.03 ? smoothing : nil,
            evenness: evenness >= 0.03 ? evenness : nil,
            blemish: blemish >= 0.03 ? blemish : nil,
            confidence: min(lhs.confidence, rhs.confidence)
        )
        guard result.smoothing != nil || result.evenness != nil || result.blemish != nil else {
            return nil
        }
        return result
    }
}
