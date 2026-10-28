import CoreGraphics
import Foundation
import StyleToneCore
import StyleToneImaging

/// Downsampled luma/chroma field used by the evenness pass.
///
/// Evenness only needs low frequencies, so the field is built from a reduced
/// copy of the image: this keeps the 12 MP case cheap and bounds memory to a
/// few megabytes. The reduced copy is drawn with Core Graphics into the same
/// colour space as the input, then linearised through ``ColorPipeline`` so the
/// field sees linear light and never silently changes the working space.
struct LowFrequencyField: Sendable {
    let width: Int
    let height: Int
    let scale: Int
    /// `(luma, Cb, Cr)` at reduced resolution.
    let samples: [SIMD3<Float>]

    func sample(x: Int, y: Int) -> SIMD3<Float> {
        guard width > 0, height > 0 else {
            return SIMD3<Float>(0, 0, 0)
        }
        if width == 1, height == 1 {
            return samples[0]
        }
        let inverseScale = 1 / Float(scale)
        let sourceX = (Float(x) + 0.5) * inverseScale - 0.5
        let sourceY = (Float(y) + 0.5) * inverseScale - 0.5
        let baseX = Int(floor(sourceX))
        let baseY = Int(floor(sourceY))
        let tx = min(max(sourceX - Float(baseX), 0), 1)
        let ty = min(max(sourceY - Float(baseY), 0), 1)
        let x0 = min(max(baseX, 0), width - 1)
        let x1 = min(max(baseX + 1, 0), width - 1)
        let y0 = min(max(baseY, 0), height - 1)
        let y1 = min(max(baseY + 1, 0), height - 1)

        let top = samples[y0 * width + x0] * (1 - tx) + samples[y0 * width + x1] * tx
        let bottom = samples[y1 * width + x0] * (1 - tx) + samples[y1 * width + x1] * tx
        return top * (1 - ty) + bottom * ty
    }

    static func make(
        image: ImageAsset,
        colorSpace: CGColorSpace,
        regionalRadius: Int,
        skinAlpha: [UInt8]? = nil
    ) throws -> LowFrequencyField? {
        guard image.width > 0, image.height > 0 else { return nil }
        let scale = max(
            1,
            min(8, Int((Double(regionalRadius) / 16.0).rounded()))
        )
        let smallWidth = max(1, (image.width + scale - 1) / scale)
        let smallHeight = max(1, (image.height + scale - 1) / scale)

        guard let context = CGContext(
            data: nil,
            width: smallWidth,
            height: smallHeight,
            bitsPerComponent: 8,
            bytesPerRow: smallWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.setBlendMode(.copy)
        context.draw(
            image.cgImage,
            in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight)
        )
        guard let reducedImage = context.makeImage() else { return nil }

        let reducedAsset = ImageAsset(cgImage: reducedImage, colorSpace: colorSpace)
        let linear = try ColorPipeline().linearize(reducedAsset)
        let count = linear.pixelCount
        var luma = [Float](repeating: 0, count: count)
        var cb = [Float](repeating: 0, count: count)
        var cr = [Float](repeating: 0, count: count)
        for index in 0 ..< count {
            let pixel = linear.pixels[index]
            let value = RetouchMath.luma(pixel)
            luma[index] = value
            cb[index] = (pixel.z - value) / 1.8556
            cr[index] = (pixel.x - value) / 1.5748
        }

        let blurRadius = max(1, min(64, regionalRadius / max(scale, 1)))
        var samples = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: count)

        if Self.hasPartialCoverage(skinAlpha, imageSize: image.pixelSize) {
            let weights = Self.skinWeights(
                alpha: skinAlpha,
                imageSize: image.pixelSize,
                width: smallWidth,
                height: smallHeight,
                scale: scale
            )
            let weightedLuma = zip(luma, weights).map { pair in pair.0 * pair.1 }
            let weightedCb = zip(cb, weights).map { pair in pair.0 * pair.1 }
            let weightedCr = zip(cr, weights).map { pair in pair.0 * pair.1 }

            let blurredWeight = BoxBlur.apply(
                weights,
                width: smallWidth,
                height: smallHeight,
                radius: blurRadius
            )
            let blurredLuma = BoxBlur.apply(
                weightedLuma,
                width: smallWidth,
                height: smallHeight,
                radius: blurRadius
            )
            let blurredCb = BoxBlur.apply(
                weightedCb,
                width: smallWidth,
                height: smallHeight,
                radius: blurRadius
            )
            let blurredCr = BoxBlur.apply(
                weightedCr,
                width: smallWidth,
                height: smallHeight,
                radius: blurRadius
            )

            for index in 0 ..< count {
                let denominator = blurredWeight[index]
                guard denominator > 1e-5 else { continue }
                samples[index] = SIMD3<Float>(
                    blurredLuma[index] / denominator,
                    blurredCb[index] / denominator,
                    blurredCr[index] / denominator
                )
            }
        } else {
            let blurredLuma = BoxBlur.apply(
                luma,
                width: smallWidth,
                height: smallHeight,
                radius: blurRadius
            )
            let blurredCb = BoxBlur.apply(
                cb,
                width: smallWidth,
                height: smallHeight,
                radius: blurRadius
            )
            let blurredCr = BoxBlur.apply(
                cr,
                width: smallWidth,
                height: smallHeight,
                radius: blurRadius
            )
            for index in 0 ..< count {
                samples[index] = SIMD3<Float>(
                    blurredLuma[index],
                    blurredCb[index],
                    blurredCr[index]
                )
            }
        }

        return LowFrequencyField(
            width: smallWidth,
            height: smallHeight,
            scale: scale,
            samples: samples
        )
    }

    /// A full-coverage mask has no background to exclude; keeping the original
    /// three-blur path avoids paying for four extra passes on the common case.
    private static func hasPartialCoverage(
        _ alpha: [UInt8]?,
        imageSize: PixelSize
    ) -> Bool {
        guard let alpha,
              alpha.count == imageSize.width * imageSize.height
        else {
            return false
        }
        return alpha.contains { $0 < 250 }
    }

    /// Downsamples the skin coverage into the reduced field. Weighting the
    /// blur by this mask stops evenness from borrowing luma/chroma from hair,
    /// clothing or the background just outside the skin boundary.
    private static func skinWeights(
        alpha: [UInt8]?,
        imageSize: PixelSize,
        width: Int,
        height: Int,
        scale: Int
    ) -> [Float] {
        guard let alpha,
              alpha.count == imageSize.width * imageSize.height
        else {
            return [Float](repeating: 1, count: width * height)
        }

        var weights = [Float](repeating: 0, count: width * height)
        for y in 0 ..< height {
            let sourceY = y * scale
            let sourceYEnd = min(sourceY + scale, imageSize.height)
            for x in 0 ..< width {
                let sourceX = x * scale
                let sourceXEnd = min(sourceX + scale, imageSize.width)
                var sum = 0
                var samples = 0
                for sourceRow in sourceY ..< sourceYEnd {
                    let row = sourceRow * imageSize.width
                    for sourceColumn in sourceX ..< sourceXEnd {
                        sum += Int(alpha[row + sourceColumn])
                        samples += 1
                    }
                }
                if samples > 0 {
                    weights[y * width + x] = Float(sum) / (Float(samples) * 255)
                }
            }
        }
        return weights
    }
}
