import Foundation
import StyleToneCore

/// A mask sampled onto a regular grid.
///
/// Each bin stores the **maximum** and the **mean** mask coverage of the pixels
/// that mapped to it. The maximum preserves thin lines (a one-pixel-wide line
/// still makes its bin "hot"), while the mean distinguishes a line from a
/// densely textured area.
struct BackgroundMaskGrid: Sendable {
    /// Number of bins per row.
    let width: Int
    /// Number of bin rows.
    let height: Int
    /// Maximum coverage per bin, `0...1`, row-major.
    let maximums: [Float]
    /// Mean coverage per bin, `0...1`, row-major.
    let means: [Float]

    /// `true` when no pixel reached the sampler's threshold.
    var isEmpty: Bool {
        maximums.allSatisfy { $0 <= 0 }
    }

    /// Bilinearly interpolated maximum coverage at a normalized position.
    func maximum(at point: SIMD2<Float>) -> Float {
        interpolate(maximums, at: point)
    }

    /// Bilinearly interpolated mean coverage at a normalized position.
    func mean(at point: SIMD2<Float>) -> Float {
        interpolate(means, at: point)
    }

    private func interpolate(_ values: [Float], at point: SIMD2<Float>) -> Float {
        guard width >= 2, height >= 2, values.count == width * height else {
            return 0
        }
        let clamped = SIMD2<Float>(
            min(max(point.x, 0), 1),
            min(max(point.y, 0), 1)
        )
        let gridX = clamped.x * Float(width - 1)
        let gridY = clamped.y * Float(height - 1)
        let x0 = min(Int(gridX), width - 2)
        let y0 = min(Int(gridY), height - 2)
        let x1 = x0 + 1
        let y1 = y0 + 1
        let tx = gridX - Float(x0)
        let ty = gridY - Float(y0)

        let topLeft = values[y0 * width + x0]
        let topRight = values[y0 * width + x1]
        let bottomLeft = values[y1 * width + x0]
        let bottomRight = values[y1 * width + x1]
        let top = topLeft * (1 - tx) + topRight * tx
        let bottom = bottomLeft * (1 - tx) + bottomRight * tx
        return top * (1 - ty) + bottom * ty
    }
}

/// Deterministic downsampler from a full-resolution ``MaskBuffer`` to a coarse
/// analysis grid.
///
/// The sampler reads the mask with a fixed stride and bins each sampled pixel
/// to the nearest grid vertex. It is intentionally simple and allocation-light:
/// a 12 MP mask at the default budget costs fewer than one million byte reads,
/// independent of the warp grid density. Masks of 2 MP or less are read every
/// pixel, which keeps unit tests exact.
enum BackgroundMaskSampler {
    /// Samples `mask` onto a `width * height` grid.
    ///
    /// - Parameters:
    ///   - mask: Source mask.
    ///   - width: Destination bins per row (clamped to at least 2).
    ///   - height: Destination bin rows (clamped to at least 2).
    ///   - threshold: Values below this 8-bit threshold are treated as zero.
    ///   - desiredStride: Minimum sampling stride on large masks.
    ///   - maximumSamples: Approximate sample budget per call.
    /// - Throws: `CancellationError` when the enclosing task is cancelled.
    static func sample(
        mask: MaskBuffer,
        width: Int,
        height: Int,
        threshold: UInt8,
        desiredStride: Int,
        maximumSamples: Int
    ) throws -> BackgroundMaskGrid {
        let gridWidth = max(2, width)
        let gridHeight = max(2, height)
        let binCount = gridWidth * gridHeight
        var maximums = [Float](repeating: 0, count: binCount)
        var sums = [Float](repeating: 0, count: binCount)
        var counts = [Int](repeating: 0, count: binCount)

        let maskWidth = mask.width
        let maskHeight = mask.height
        let stride = samplingStride(
            maskWidth: maskWidth,
            maskHeight: maskHeight,
            desiredStride: desiredStride,
            maximumSamples: maximumSamples
        )
        let xScale = Float(gridWidth - 1) / Float(maskWidth)
        let yScale = Float(gridHeight - 1) / Float(maskHeight)

        try mask.bytes.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            var y = 0
            while y < maskHeight {
                if y.isMultiple(of: 64) {
                    try Task.checkCancellation()
                }
                let row = y * maskWidth
                let binY = min(
                    gridHeight - 1,
                    max(0, Int((Float(y) + 0.5) * yScale + 0.5))
                )
                let binRow = binY * gridWidth
                var x = 0
                while x < maskWidth {
                    let raw = base[row + x]
                    let value = raw >= threshold ? Float(raw) / 255 : 0
                    let binX = min(
                        gridWidth - 1,
                        max(0, Int((Float(x) + 0.5) * xScale + 0.5))
                    )
                    let index = binRow + binX
                    if value > maximums[index] {
                        maximums[index] = value
                    }
                    sums[index] += value
                    counts[index] += 1
                    x += stride
                }
                y += stride
            }
        }

        var means = [Float](repeating: 0, count: binCount)
        for index in 0 ..< binCount {
            let count = counts[index]
            if count > 0 {
                means[index] = sums[index] / Float(count)
            }
        }
        return BackgroundMaskGrid(
            width: gridWidth,
            height: gridHeight,
            maximums: maximums,
            means: means
        )
    }

    /// Effective sampling stride for one mask.
    ///
    /// Small masks are read every pixel so tests and 1024-px proxies keep exact
    /// geometry. Large masks respect `desiredStride` but are coarsened further
    /// when the sample budget would be exceeded.
    static func samplingStride(
        maskWidth: Int,
        maskHeight: Int,
        desiredStride: Int,
        maximumSamples: Int
    ) -> Int {
        let desired = min(max(desiredStride, 1), 64)
        let total = maskWidth * maskHeight
        guard total > 2_000_000 else { return 1 }
        let budget = max(10_000, maximumSamples)
        let needed = Int((Double(total) / Double(budget)).squareRoot().rounded(.up))
        return min(64, max(desired, needed))
    }
}
