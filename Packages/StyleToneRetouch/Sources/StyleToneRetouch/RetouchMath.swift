import Foundation

/// Small colour and numeric helpers shared by the skin and blemish pipelines.
enum RetouchMath {
    @inline(__always)
    static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        guard value.isFinite else { return lower }
        return min(max(value, lower), upper)
    }

    @inline(__always)
    static func unit(_ value: Double) -> Double {
        clamp(value, 0, 1)
    }

    @inline(__always)
    static func luma(_ pixel: SIMD4<Float>) -> Float {
        0.2126 * pixel.x + 0.7152 * pixel.y + 0.0722 * pixel.z
    }

    @inline(__always)
    static func luma(red: Float, green: Float, blue: Float) -> Float {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    @inline(__always)
    static func chroma(red: Float, green: Float, blue: Float, luma: Float) -> SIMD2<Float> {
        SIMD2<Float>((blue - luma) / 1.8556, (red - luma) / 1.5748)
    }

    @inline(__always)
    static func reconstruct(luma: Float, chroma: SIMD2<Float>) -> SIMD3<Float> {
        let red = luma + 1.5748 * chroma.y
        let blue = luma + 1.8556 * chroma.x
        let green = (luma - 0.2126 * red - 0.0722 * blue) / 0.7152
        return SIMD3<Float>(red, green, blue)
    }

    /// Keeps reconstructed skin away from the 8-bit clipping rails.
    ///
    /// `evenness` can raise a channel while normalising a local tone; without
    /// headroom the encode would quantise it to 250+ and the golden corpus
    /// counts that as a skin-clipping incident. The limits leave one code value
    /// of margin for rounding in the linear-to-sRGB encode.
    @inline(__always)
    static func clampHeadroom(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            min(max(rgb.x, 0.02), 0.94),
            min(max(rgb.y, 0.02), 0.94),
            min(max(rgb.z, 0.02), 0.94)
        )
    }

    /// Fades between 0 and 1 with a smooth first derivative.
    @inline(__always)
    static func smoothstep(_ value: Float) -> Float {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// 1 on flat texture, approaching 0 on strong edges.
    @inline(__always)
    static func edgeWeight(detail: Float, threshold: Float) -> Float {
        let safeThreshold = max(threshold, 1e-5)
        let ratio = abs(detail) / safeThreshold
        return 1 / (1 + ratio * ratio)
    }
}

/// Separable, O(pixel count) box blur with clamp-to-edge addressing.
///
/// This is the only primitive the guided filter and the regional field need.
/// Both passes are written row-major so the vertical pass remains cache
/// friendly: a full row of column sums is updated for each output row.
enum BoxBlur {
    static func apply(
        _ source: [Float],
        width: Int,
        height: Int,
        radius requestedRadius: Int
    ) -> [Float] {
        guard width > 0, height > 0, source.count == width * height else {
            return source
        }
        let radius = min(max(requestedRadius, 0), max(width, height))
        guard radius > 0 else { return source }

        let count = width * height
        let window = Float(2 * radius + 1)
        let inverseWindow = 1 / window
        var horizontal = [Float](repeating: 0, count: count)

        source.withUnsafeBufferPointer { input in
            horizontal.withUnsafeMutableBufferPointer { output in
                for y in 0 ..< height {
                    let row = y * width
                    var sum: Float = 0
                    for offset in -radius ... radius {
                        sum += input[row + min(max(offset, 0), width - 1)]
                    }
                    for x in 0 ..< width {
                        output[row + x] = sum * inverseWindow
                        let addX = min(x + radius + 1, width - 1)
                        let removeX = max(x - radius, 0)
                        sum += input[row + addX] - input[row + removeX]
                    }
                }
            }
        }

        var vertical = [Float](repeating: 0, count: count)
        var columnSums = [Float](repeating: 0, count: width)
        horizontal.withUnsafeBufferPointer { input in
            vertical.withUnsafeMutableBufferPointer { output in
                columnSums.withUnsafeMutableBufferPointer { sums in
                    for x in 0 ..< width {
                        sums[x] = 0
                    }
                    for offset in -radius ... radius {
                        let row = min(max(offset, 0), height - 1) * width
                        for x in 0 ..< width {
                            sums[x] += input[row + x]
                        }
                    }
                    for y in 0 ..< height {
                        let row = y * width
                        for x in 0 ..< width {
                            output[row + x] = sums[x] * inverseWindow
                        }
                        let addRow = min(y + radius + 1, height - 1) * width
                        let removeRow = max(y - radius, 0) * width
                        for x in 0 ..< width {
                            sums[x] += input[addRow + x] - input[removeRow + x]
                        }
                    }
                }
            }
        }
        return vertical
    }
}

/// Self-guided filter used for the fine frequency band.
///
/// The filter is the standard O(N) guided filter with `guide == input`:
///
/// `q = mean(a) * I + mean(b)`, `a = var / (var + epsilon)`.
///
/// Where local variance is much larger than `epsilon` (edges, lashes) `a`
/// approaches 1 and the filter returns the input; flat skin is averaged.
enum GuidedFilter {
    static func selfGuided(
        _ source: [Float],
        width: Int,
        height: Int,
        radius: Int,
        epsilon requestedEpsilon: Float
    ) -> [Float] {
        guard width > 0, height > 0, source.count == width * height else {
            return source
        }
        let epsilon = max(requestedEpsilon, 1e-6)
        let count = width * height
        let mean = BoxBlur.apply(source, width: width, height: height, radius: radius)

        var squared = [Float](repeating: 0, count: count)
        source.withUnsafeBufferPointer { input in
            squared.withUnsafeMutableBufferPointer { output in
                for index in 0 ..< count {
                    let value = input[index]
                    output[index] = value * value
                }
            }
        }
        let correlation = BoxBlur.apply(squared, width: width, height: height, radius: radius)

        var a = [Float](repeating: 0, count: count)
        var b = [Float](repeating: 0, count: count)
        for index in 0 ..< count {
            let localMean = mean[index]
            var variance = correlation[index] - localMean * localMean
            if variance < 0 {
                variance = 0
            }
            let coefficient = variance / (variance + epsilon)
            a[index] = coefficient
            b[index] = localMean * (1 - coefficient)
        }

        let meanA = BoxBlur.apply(a, width: width, height: height, radius: radius)
        let meanB = BoxBlur.apply(b, width: width, height: height, radius: radius)

        var output = [Float](repeating: 0, count: count)
        for index in 0 ..< count {
            output[index] = meanA[index] * source[index] + meanB[index]
        }
        return output
    }
}
