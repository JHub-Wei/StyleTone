import Foundation

/// Deterministic bilinear sampling with clamp-to-edge addressing.
///
/// The sampler works on straight linear-light RGBA values produced by
/// `ColorPipeline`. Sampling is done at normalized coordinates; pixel centers
/// are at `(x + 0.5) / width`, so an identity warp samples exact texel centers
/// and preserves colours before the final 8-bit encode.
public enum BilinearSampler {
    /// Samples `pixels` at a normalized coordinate.
    ///
    /// Coordinates outside `0...1` clamp to the nearest edge texel. This is the
    /// CPU equivalent of a Metal sampler with `addressMode = clampToEdge`.
    ///
    /// - Parameters:
    ///   - pixels: Row-major RGBA pixels, `width * height` long.
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - point: Normalized sample position (top-left origin, y down).
    public static func sample(
        _ pixels: [SIMD4<Float>],
        width: Int,
        height: Int,
        at point: SIMD2<Float>
    ) -> SIMD4<Float> {
        guard width > 0, height > 0, pixels.count == width * height else {
            return .zero
        }
        if width == 1 && height == 1 {
            return pixels[0]
        }

        let pixelX = min(max(point.x * Float(width) - 0.5, 0), Float(width - 1))
        let pixelY = min(max(point.y * Float(height) - 0.5, 0), Float(height - 1))

        let x0 = min(Int(pixelX), width - 1)
        let y0 = min(Int(pixelY), height - 1)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = pixelX - Float(x0)
        let ty = pixelY - Float(y0)

        let topLeft = pixels[y0 * width + x0]
        let topRight = pixels[y0 * width + x1]
        let bottomLeft = pixels[y1 * width + x0]
        let bottomRight = pixels[y1 * width + x1]

        let top = topLeft * (1 - tx) + topRight * tx
        let bottom = bottomLeft * (1 - tx) + bottomRight * tx
        return top * (1 - ty) + bottom * ty
    }
}
