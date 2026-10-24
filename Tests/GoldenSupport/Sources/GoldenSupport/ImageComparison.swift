import Foundation
import StyleToneCore

/// Thresholds applied by ``ImageComparator``.
///
/// A comparison fails when *any* configured threshold is exceeded. Use the
/// presets for common cases and override individual fields when a module needs
/// a specific budget.
public struct ImageThresholds: Sendable, Equatable, Codable {
    /// Maximum per-channel absolute difference (0...255) tolerated before a
    /// pixel counts as "differing".
    public var channelTolerance: Int
    /// Fraction of differing pixels allowed, in `0...1`.
    public var allowedDifferingPixelRatio: Double
    /// Maximum mean CIEDE2000 over all pixels.
    public var maxMeanDeltaE00: Double
    /// Maximum 95th percentile CIEDE2000.
    public var maxP95DeltaE00: Double
    /// Maximum single-pixel CIEDE2000.
    public var maxDeltaE00: Double
    /// Minimum structural similarity (SSIM).
    public var minSSIM: Double

    public init(
        channelTolerance: Int = 2,
        allowedDifferingPixelRatio: Double = 0.01,
        maxMeanDeltaE00: Double = 2.0,
        maxP95DeltaE00: Double = 5.0,
        maxDeltaE00: Double = 12.0,
        minSSIM: Double = 0.95
    ) {
        self.channelTolerance = max(0, channelTolerance)
        self.allowedDifferingPixelRatio = min(max(allowedDifferingPixelRatio, 0), 1)
        self.maxMeanDeltaE00 = max(0, maxMeanDeltaE00)
        self.maxP95DeltaE00 = max(0, maxP95DeltaE00)
        self.maxDeltaE00 = max(0, maxDeltaE00)
        self.minSSIM = min(max(minSSIM, 0), 1)
    }

    /// Bit-exact expectation (identity pipeline, no-op render).
    public static let identity = ImageThresholds(
        channelTolerance: 0,
        allowedDifferingPixelRatio: 0,
        maxMeanDeltaE00: 0.05,
        maxP95DeltaE00: 0.1,
        maxDeltaE00: 0.25,
        minSSIM: 0.9999
    )

    /// Tight tolerance for deterministic image transforms.
    public static let strict = ImageThresholds(
        channelTolerance: 1,
        allowedDifferingPixelRatio: 0.002,
        maxMeanDeltaE00: 1.0,
        maxP95DeltaE00: 2.0,
        maxDeltaE00: 6.0,
        minSSIM: 0.99
    )

    /// Default tolerance for algorithm changes that may shift a few pixels.
    public static let standard = ImageThresholds()

    /// Loose tolerance for perceptual, structure-preserving transforms.
    public static let structural = ImageThresholds(
        channelTolerance: 8,
        allowedDifferingPixelRatio: 0.1,
        maxMeanDeltaE00: 4.0,
        maxP95DeltaE00: 10.0,
        maxDeltaE00: 30.0,
        minSSIM: 0.85
    )
}

/// The result of comparing two images, including per-pixel distribution
/// statistics and the list of thresholds that failed.
public struct ImageDifferenceReport: Sendable, Equatable, Codable {
    public let expectedSize: PixelSize
    public let actualSize: PixelSize
    public let differingPixelCount: Int
    public let differingPixelRatio: Double
    /// Mean absolute RGB channel difference normalised to `0...1`.
    public let meanChannelDelta: Double
    /// Maximum absolute channel difference in `0...255` (alpha included).
    public let maxChannelDelta: Int
    public let meanDeltaE00: Double
    public let p95DeltaE00: Double
    public let maxDeltaE00: Double
    public let ssim: Double
    /// Bounding box of pixels whose channel delta exceeded the tolerance.
    public let differenceBoundingBox: PixelRect?
    public let thresholds: ImageThresholds
    public let failures: [String]

    public init(
        expectedSize: PixelSize,
        actualSize: PixelSize,
        differingPixelCount: Int,
        differingPixelRatio: Double,
        meanChannelDelta: Double,
        maxChannelDelta: Int,
        meanDeltaE00: Double,
        p95DeltaE00: Double,
        maxDeltaE00: Double,
        ssim: Double,
        differenceBoundingBox: PixelRect?,
        thresholds: ImageThresholds,
        failures: [String]
    ) {
        self.expectedSize = expectedSize
        self.actualSize = actualSize
        self.differingPixelCount = differingPixelCount
        self.differingPixelRatio = differingPixelRatio
        self.meanChannelDelta = meanChannelDelta
        self.maxChannelDelta = maxChannelDelta
        self.meanDeltaE00 = meanDeltaE00
        self.p95DeltaE00 = p95DeltaE00
        self.maxDeltaE00 = maxDeltaE00
        self.ssim = ssim
        self.differenceBoundingBox = differenceBoundingBox
        self.thresholds = thresholds
        self.failures = failures
    }

    public var passes: Bool { failures.isEmpty }

    /// One-line human readable summary.
    public var summary: String {
        let result = passes ? "PASS" : "FAIL"
        let size = "\(expectedSize.width)x\(expectedSize.height)"
        return "\(result) \(size) differing=\(differingPixelCount) "
            + "(\(Self.percent(differingPixelRatio))) "
            + "meanDeltaE00=\(Self.decimal(meanDeltaE00, places: 3)) "
            + "p95=\(Self.decimal(p95DeltaE00, places: 3)) "
            + "max=\(Self.decimal(maxDeltaE00, places: 3)) "
            + "SSIM=\(Self.decimal(ssim, places: 4))"
            + (passes ? "" : " failures=[\(failures.joined(separator: "; "))]")
    }

    /// Markdown table suitable for a CI job summary.
    public func markdown() -> String {
        var lines: [String] = []
        lines.append("### Image comparison: \(passes ? "PASS" : "FAIL")")
        lines.append("")
        lines.append("| metric | value | threshold |")
        lines.append("|---|---|---|")
        lines.append("| size | \(expectedSize.width)x\(expectedSize.height) | — |")
        lines.append("| differing pixels | \(differingPixelCount) (\(Self.percent(differingPixelRatio))) | ≤ \(Self.percent(thresholds.allowedDifferingPixelRatio)) |")
        lines.append("| mean channel delta | \(Self.decimal(meanChannelDelta, places: 4)) | — |")
        lines.append("| max channel delta | \(maxChannelDelta) | ≤ \(thresholds.channelTolerance) per pixel |")
        lines.append("| mean ΔE00 | \(Self.decimal(meanDeltaE00, places: 3)) | ≤ \(Self.decimal(thresholds.maxMeanDeltaE00, places: 3)) |")
        lines.append("| p95 ΔE00 | \(Self.decimal(p95DeltaE00, places: 3)) | ≤ \(Self.decimal(thresholds.maxP95DeltaE00, places: 3)) |")
        lines.append("| max ΔE00 | \(Self.decimal(maxDeltaE00, places: 3)) | ≤ \(Self.decimal(thresholds.maxDeltaE00, places: 3)) |")
        lines.append("| SSIM | \(Self.decimal(ssim, places: 4)) | ≥ \(Self.decimal(thresholds.minSSIM, places: 4)) |")
        if let box = differenceBoundingBox {
            lines.append("| difference bounds | x=\(box.x) y=\(box.y) w=\(box.width) h=\(box.height) | — |")
        }
        if !failures.isEmpty {
            lines.append("")
            lines.append("Failures:")
            for failure in failures {
                lines.append("- \(failure)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func decimal(_ value: Double, places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }
}

/// Deterministic image comparison: per-pixel ΔE00, SSIM, channel thresholds and
/// a diff image for CI artifacts.
public enum ImageComparator {
    /// Compares two same-size buffers and evaluates every threshold.
    public static func compare(
        expected: PixelBuffer,
        actual: PixelBuffer,
        thresholds: ImageThresholds = .standard
    ) throws -> ImageDifferenceReport {
        guard expected.width == actual.width, expected.height == actual.height else {
            throw GoldenSupportError.imageSizeMismatch(
                expected: expected.pixelSize,
                actual: actual.pixelSize
            )
        }

        let width = expected.width
        let height = expected.height
        let pixelCount = width * height
        var differingPixelCount = 0
        var channelDeltaTotal = 0
        var maxChannelDelta = 0
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var deltaValues: [Double] = []
        deltaValues.reserveCapacity(pixelCount)

        for y in 0..<height {
            for x in 0..<width {
                let expectedPixel = expected[x, y]
                let actualPixel = actual[x, y]
                let redDelta = abs(Int(expectedPixel.red) - Int(actualPixel.red))
                let greenDelta = abs(Int(expectedPixel.green) - Int(actualPixel.green))
                let blueDelta = abs(Int(expectedPixel.blue) - Int(actualPixel.blue))
                let alphaDelta = abs(Int(expectedPixel.alpha) - Int(actualPixel.alpha))
                let pixelDelta = max(max(redDelta, greenDelta), max(blueDelta, alphaDelta))

                channelDeltaTotal += redDelta + greenDelta + blueDelta
                maxChannelDelta = max(maxChannelDelta, pixelDelta)
                if pixelDelta > thresholds.channelTolerance {
                    differingPixelCount += 1
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
                deltaValues.append(ColorScience.deltaE00(expectedPixel.color, actualPixel.color))
            }
        }

        deltaValues.sort()
        let meanDeltaE = deltaValues.reduce(0, +) / Double(pixelCount)
        let maxDeltaE = deltaValues.last ?? 0
        let p95DeltaE = percentile(deltaValues, fraction: 0.95)
        let ssim = structuralSimilarity(expected, actual)
        let differingPixelRatio = Double(differingPixelCount) / Double(pixelCount)
        let meanChannelDelta = Double(channelDeltaTotal) / (Double(pixelCount) * 3.0 * 255.0)
        let boundingBox = differingPixelCount == 0
            ? nil
            : PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)

        var failures: [String] = []
        if differingPixelRatio > thresholds.allowedDifferingPixelRatio {
            failures.append(
                String(
                    format: "differingPixelRatio %.4f > %.4f",
                    differingPixelRatio,
                    thresholds.allowedDifferingPixelRatio
                )
            )
        }
        if meanDeltaE > thresholds.maxMeanDeltaE00 {
            failures.append(
                String(format: "meanDeltaE00 %.4f > %.4f", meanDeltaE, thresholds.maxMeanDeltaE00)
            )
        }
        if p95DeltaE > thresholds.maxP95DeltaE00 {
            failures.append(
                String(format: "p95DeltaE00 %.4f > %.4f", p95DeltaE, thresholds.maxP95DeltaE00)
            )
        }
        if maxDeltaE > thresholds.maxDeltaE00 {
            failures.append(
                String(format: "maxDeltaE00 %.4f > %.4f", maxDeltaE, thresholds.maxDeltaE00)
            )
        }
        if ssim < thresholds.minSSIM {
            failures.append(
                String(format: "ssim %.4f < %.4f", ssim, thresholds.minSSIM)
            )
        }

        return ImageDifferenceReport(
            expectedSize: expected.pixelSize,
            actualSize: actual.pixelSize,
            differingPixelCount: differingPixelCount,
            differingPixelRatio: differingPixelRatio,
            meanChannelDelta: meanChannelDelta,
            maxChannelDelta: maxChannelDelta,
            meanDeltaE00: meanDeltaE,
            p95DeltaE00: p95DeltaE,
            maxDeltaE00: maxDeltaE,
            ssim: ssim,
            differenceBoundingBox: boundingBox,
            thresholds: thresholds,
            failures: failures
        )
    }

    /// Convenience overload for `ImageAsset` values.
    public static func compare(
        expected: ImageAsset,
        actual: ImageAsset,
        thresholds: ImageThresholds = .standard
    ) throws -> ImageDifferenceReport {
        let expectedBuffer = try PixelBuffer(image: expected)
        let actualBuffer = try PixelBuffer(image: actual)
        return try compare(expected: expectedBuffer, actual: actualBuffer, thresholds: thresholds)
    }

    /// Per-pixel CIEDE2000 map in row-major order, in `0...100` for normal sRGB.
    ///
    /// This is `O(pixels)` with trigonometric work per pixel; use small
    /// fixtures or sparsely sampled images in hot paths.
    public static func deltaEMap(expected: PixelBuffer, actual: PixelBuffer) throws -> [Float] {
        guard expected.width == actual.width, expected.height == actual.height else {
            throw GoldenSupportError.imageSizeMismatch(
                expected: expected.pixelSize,
                actual: actual.pixelSize
            )
        }
        var map = [Float](repeating: 0, count: expected.pixelCount)
        var index = 0
        for y in 0..<expected.height {
            for x in 0..<expected.width {
                map[index] = Float(
                    ColorScience.deltaE00(expected[x, y].color, actual[x, y].color)
                )
                index += 1
            }
        }
        return map
    }

    /// Structural similarity on Rec. 709 luma, averaged over 8x8 blocks.
    ///
    /// Identical images score exactly `1.0`. Partial blocks at the right and
    /// bottom edges are included at their actual size.
    public static func structuralSimilarity(_ first: PixelBuffer, _ second: PixelBuffer) -> Double {
        guard first.width == second.width, first.height == second.height,
              first.width > 0, first.height > 0
        else {
            return 0
        }

        let blockSize = 8
        let c1 = 6.5025
        let c2 = 58.5225
        var total = 0.0
        var blockCount = 0
        var blockY = 0
        while blockY < first.height {
            let endY = min(blockY + blockSize, first.height)
            var blockX = 0
            while blockX < first.width {
                let endX = min(blockX + blockSize, first.width)
                let sampleCount = Double((endX - blockX) * (endY - blockY))

                var firstTotal = 0.0
                var secondTotal = 0.0
                for y in blockY..<endY {
                    for x in blockX..<endX {
                        firstTotal += first[x, y].color.luma
                        secondTotal += second[x, y].color.luma
                    }
                }
                let firstMean = firstTotal / sampleCount
                let secondMean = secondTotal / sampleCount

                var firstVariance = 0.0
                var secondVariance = 0.0
                var covariance = 0.0
                for y in blockY..<endY {
                    for x in blockX..<endX {
                        let firstDelta = first[x, y].color.luma - firstMean
                        let secondDelta = second[x, y].color.luma - secondMean
                        firstVariance += firstDelta * firstDelta
                        secondVariance += secondDelta * secondDelta
                        covariance += firstDelta * secondDelta
                    }
                }
                firstVariance /= sampleCount
                secondVariance /= sampleCount
                covariance /= sampleCount

                let numerator = (2 * firstMean * secondMean + c1) * (2 * covariance + c2)
                let denominator = (firstMean * firstMean + secondMean * secondMean + c1)
                    * (firstVariance + secondVariance + c2)
                total += denominator == 0 ? 1 : numerator / denominator
                blockCount += 1
                blockX = endX
            }
            blockY = endY
        }
        return blockCount == 0 ? 1 : total / Double(blockCount)
    }

    /// Grayscale absolute-difference image (amplified) for CI artifacts.
    public static func differenceImage(
        expected: PixelBuffer,
        actual: PixelBuffer,
        amplification: Int = 8
    ) throws -> PixelBuffer {
        guard expected.width == actual.width, expected.height == actual.height else {
            throw GoldenSupportError.imageSizeMismatch(
                expected: expected.pixelSize,
                actual: actual.pixelSize
            )
        }
        let factor = max(1, amplification)
        var buffer = try PixelBuffer(width: expected.width, height: expected.height, fill: .black)
        for y in 0..<expected.height {
            for x in 0..<expected.width {
                let expectedPixel = expected[x, y]
                let actualPixel = actual[x, y]
                let delta = max(
                    max(
                        abs(Int(expectedPixel.red) - Int(actualPixel.red)),
                        abs(Int(expectedPixel.green) - Int(actualPixel.green))
                    ),
                    abs(Int(expectedPixel.blue) - Int(actualPixel.blue))
                )
                let value = UInt8(min(255, delta * factor))
                buffer[x, y] = RGBA8(red: value, green: value, blue: value)
            }
        }
        return buffer
    }

    private static func percentile(_ sortedValues: [Double], fraction: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let clampedFraction = min(max(fraction, 0), 1)
        let rank = Int((clampedFraction * Double(sortedValues.count)).rounded(.up))
        let index = min(max(rank - 1, 0), sortedValues.count - 1)
        return sortedValues[index]
    }
}
