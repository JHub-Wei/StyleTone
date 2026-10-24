import CoreGraphics
import Foundation
import StyleToneCore

/// A small, colour-managed proxy of an `ImageAsset`.
///
/// Pixels are sRGB-decoded to linear light for colour math and keep an encoded
/// luma plane for texture measurements. The proxy is private to the learner and
/// is never written back; it exists so the fitter can work on at most
/// `maximumAnalysisEdge²` pixels instead of a full-resolution photo.
struct NumericImage: Sendable {
    let width: Int
    let height: Int
    /// Row-major linear-light sRGB.
    let linear: [LinearRGB]
    /// Colour-based skin likelihood, `0...1`, row-major.
    let skin: [Float]
    /// Encoded Rec. 709 luma, row-major, used for high-frequency texture.
    let encodedLuma: [Float]

    var pixelCount: Int { width * height }

    func index(x: Int, y: Int) -> Int {
        y * width + x
    }
}

/// Decodes an `ImageAsset` into ``NumericImage``.
enum NumericImageLoader {
    /// Longest edge is capped, aspect ratio is preserved and the image is drawn
    /// through an sRGB bitmap context so P3 or indexed inputs become stable
    /// sRGB values.
    static func load(_ asset: ImageAsset, maximumEdge: Int) throws -> NumericImage {
        let source = asset.cgImage
        let sourceWidth = source.width
        let sourceHeight = source.height
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw StyleToneError.invalidImage
        }

        let limit = min(max(maximumEdge, 16), 512)
        let longestEdge = max(sourceWidth, sourceHeight)
        let scale = min(1.0, Double(limit) / Double(longestEdge))
        let targetWidth = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let targetHeight = max(1, Int((Double(sourceHeight) * scale).rounded()))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: targetWidth,
                  height: targetHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: targetWidth * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw StyleToneError.imageDecodingFailed
        }

        context.interpolationQuality = .medium
        context.setBlendMode(.copy)
        context.draw(
            source,
            in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        )

        guard let data = context.data else {
            throw StyleToneError.imageDecodingFailed
        }

        let count = targetWidth * targetHeight
        var linear = [LinearRGB](repeating: LinearRGB(red: 0, green: 0, blue: 0), count: count)
        var skin = [Float](repeating: 0, count: count)
        var encodedLuma = [Float](repeating: 0, count: count)
        let rowBytes = context.bytesPerRow
        let bytes = data.assumingMemoryBound(to: UInt8.self)

        for y in 0..<targetHeight {
            let row = bytes + y * rowBytes
            let destinationRow = y * targetWidth
            for x in 0..<targetWidth {
                let offset = x * 4
                let alpha = row[offset + 3]
                let index = destinationRow + x
                guard alpha > 0 else {
                    continue
                }

                let red = unpremultiply(row[offset], alpha: alpha)
                let green = unpremultiply(row[offset + 1], alpha: alpha)
                let blue = unpremultiply(row[offset + 2], alpha: alpha)

                linear[index] = LinearRGB(
                    red: Float(LearningColor.srgbToLinear(red)),
                    green: Float(LearningColor.srgbToLinear(green)),
                    blue: Float(LearningColor.srgbToLinear(blue))
                )
                skin[index] = SkinToneModel.weight(
                    encodedRed: red,
                    green: green,
                    blue: blue
                )
                encodedLuma[index] = Float(
                    0.2126 * red + 0.7152 * green + 0.0722 * blue
                )
            }
        }

        return NumericImage(
            width: targetWidth,
            height: targetHeight,
            linear: linear,
            skin: skin,
            encodedLuma: encodedLuma
        )
    }

    private static func unpremultiply(_ component: UInt8, alpha: UInt8) -> Double {
        guard alpha < 255 else { return Double(component) / 255 }
        let value = Double(component) * 255 / Double(alpha)
        return min(max(value / 255, 0), 1)
    }
}

/// Lightweight colour-based skin likelihood used by tone fitting and texture
/// masking.
///
/// This is deliberately *not* face or identity detection: it only answers "does
/// this pixel look like skin colour?" so the fitter can exclude skin from white
/// balance and verify that the learned tone does not push the skin region.
/// Ambiguous pixels receive a soft weight; no skin type is classified and no
/// result is persisted.
enum SkinToneModel {
    static func weight(
        encodedRed red: Double,
        green: Double,
        blue: Double
    ) -> Float {
        let luma = 0.299 * red + 0.587 * green + 0.114 * blue
        let cb = 0.564 * (blue - luma) + 0.5
        let cr = 0.713 * (red - luma) + 0.5

        let lumaWeight = LearningMath.smoothstep(0.08, 0.17, luma)
            * (1 - LearningMath.smoothstep(0.93, 0.99, luma))
        let cbWeight = 1 - LearningMath.smoothstep(0.09, 0.15, abs(cb - 0.43))
        let crWeight = 1 - LearningMath.smoothstep(0.09, 0.15, abs(cr - 0.615))

        let lab = LearningColor.lab(encodedRed: red, green: green, blue: blue)
        let chromaWeight = LearningMath.smoothstep(2.5, 8, lab.chroma)
            * (1 - LearningMath.smoothstep(52, 68, lab.chroma))
        let hueWeight = 1 - LearningMath.smoothstep(
            20,
            42,
            LearningMath.hueDistance(lab.hueDegrees, 38)
        )
        let redBlueWeight = LearningMath.smoothstep(-0.01, 0.04, red - blue)

        let score = lumaWeight * cbWeight * crWeight * chromaWeight * hueWeight * redBlueWeight
        return Float(LearningMath.unit(score))
    }
}
