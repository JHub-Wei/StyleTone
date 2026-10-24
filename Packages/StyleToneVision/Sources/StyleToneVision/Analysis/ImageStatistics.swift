import Foundation
import StyleToneImaging

/// Small pixel statistics helpers shared by masks and pair quality.
///
/// All luma values are encoded (gamma) sRGB, matching the thresholds used by
/// the skin and edge models. Linear-light conversion goes through
/// ``ColorPipeline``; this file never re-implements color management.
enum ImageStatistics {
    /// Encoded sRGB components of one straight-alpha linear pixel.
    static func encodedSRGB(_ pixel: SIMD4<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            clamp01(ColorPipeline.srgbEncodedValue(fromLinear: pixel.x)),
            clamp01(ColorPipeline.srgbEncodedValue(fromLinear: pixel.y)),
            clamp01(ColorPipeline.srgbEncodedValue(fromLinear: pixel.z))
        )
    }

    /// Rec. 709 luma of encoded sRGB components.
    static func luma(_ srgb: SIMD3<Float>) -> Float {
        0.2126 * srgb.x + 0.7152 * srgb.y + 0.0722 * srgb.z
    }

    /// Mean encoded luma, sampled on a coarse grid to stay cheap.
    static func meanEncodedLuma(linearImage: LinearImage, maximumSamples: Int = 4096) -> Double {
        let pixelCount = linearImage.pixelCount
        guard pixelCount > 0 else { return 0 }
        let step = max(1, Int((Double(pixelCount) / Double(max(maximumSamples, 1))).squareRoot()))
        var sum = 0.0
        var count = 0
        var y = 0
        while y < linearImage.height {
            var x = 0
            while x < linearImage.width {
                sum += Double(luma(encodedSRGB(linearImage.pixels[y * linearImage.width + x])))
                count += 1
                x += step
            }
            y += step
        }
        guard count > 0 else { return 0 }
        return min(max(sum / Double(count), 0), 1)
    }

    static func clamp01(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
