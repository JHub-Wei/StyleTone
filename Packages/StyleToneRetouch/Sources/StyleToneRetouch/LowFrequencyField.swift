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
        regionalRadius: Int
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
        // Core Graphics bitmap contexts use a bottom-left origin, while
        // `LowFrequencyField.sample(x:y:)` indexes rows top-to-bottom like the
        // source image. Flip the CTM before drawing so the reduced field keeps
        // the source orientation; otherwise evenness pulls color from the
        // vertically mirrored region.
        context.translateBy(x: 0, y: CGFloat(smallHeight))
        context.scaleBy(x: 1, y: -1)
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

        var samples = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: count)
        for index in 0 ..< count {
            samples[index] = SIMD3<Float>(
                blurredLuma[index],
                blurredCb[index],
                blurredCr[index]
            )
        }
        return LowFrequencyField(
            width: smallWidth,
            height: smallHeight,
            scale: scale,
            samples: samples
        )
    }
}
