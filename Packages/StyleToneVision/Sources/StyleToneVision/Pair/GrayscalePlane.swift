import Foundation
import StyleToneImaging

/// A square, mean-centred grayscale plane used by registration and structural
/// comparison.
struct GrayscalePlane {
    let dimension: Int
    /// Encoded sRGB luma in `0...1`.
    let raw: [Float]
    /// Zero-mean, unit-variance luma. All zeros for a flat image.
    let normalized: [Float]
    let isFlat: Bool
}

enum GrayscalePlaneBuilder {
    static func build(
        linearImage: LinearImage,
        dimension: Int
    ) throws -> GrayscalePlane? {
        guard dimension >= 8 else { return nil }
        let width = linearImage.width
        let height = linearImage.height
        guard width > 0, height > 0 else { return nil }

        var raw = [Float](repeating: 0, count: dimension * dimension)
        for y in 0 ..< dimension {
            if y.isMultiple(of: 32) {
                try Task.checkCancellation()
            }
            let sourceY = min(height - 1, y * height / dimension)
            let sourceRow = sourceY * width
            let destinationRow = y * dimension
            for x in 0 ..< dimension {
                let sourceX = min(width - 1, x * width / dimension)
                let pixel = linearImage.pixels[sourceRow + sourceX]
                raw[destinationRow + x] = ImageStatistics.luma(ImageStatistics.encodedSRGB(pixel))
            }
        }

        let count = Double(raw.count)
        var sum = 0.0
        for value in raw {
            sum += Double(value)
        }
        let mean = sum / count
        var varianceSum = 0.0
        for value in raw {
            let difference = Double(value) - mean
            varianceSum += difference * difference
        }
        let standardDeviation = (varianceSum / count).squareRoot()
        let isFlat = standardDeviation < 1e-6

        var normalized = [Float](repeating: 0, count: raw.count)
        if !isFlat {
            let scale = Float(1 / standardDeviation)
            let meanFloat = Float(mean)
            for index in raw.indices {
                normalized[index] = (raw[index] - meanFloat) * scale
            }
        }
        return GrayscalePlane(
            dimension: dimension,
            raw: raw,
            normalized: normalized,
            isFlat: isFlat
        )
    }
}
