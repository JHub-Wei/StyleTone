import Foundation

/// Texture measurements over skin-masked pixels.
struct TextureStatistics: Sendable, Equatable {
    /// Mean squared Laplacian of encoded luma on skin pixels.
    let fineEnergy: Double
    /// 99th percentile absolute Laplacian on skin pixels.
    let fineP99: Double
    /// Standard deviation of 8×8 block means on skin pixels.
    let regionalVariation: Double
    /// Number of interior skin pixels that contributed to `fineEnergy`.
    let sampleCount: Int

    static let empty = TextureStatistics(
        fineEnergy: 0,
        fineP99: 0,
        regionalVariation: 0,
        sampleCount: 0
    )
}

/// Per-image statistics used by the pair fitter.
///
/// Statistics are computed once per pair (not per estimate) and carry the
/// downsampled image so saturation can be measured after white-balance
/// normalisation without a second decode.
struct ImageStatistics: Sendable {
    /// Probabilities for the stored quantile arrays, in ascending order.
    static let probabilities: [Double] = [0.02, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.98]

    let image: NumericImage
    let lumaQuantiles: [Double]
    let linearLumaQuantiles: [Double]
    let skinLumaQuantiles: [Double]
    let medianRelativeChroma: Double
    let neutralChannelLogs: SIMD3<Double>?
    let allChannelLogs: SIMD3<Double>
    let neutralFraction: Double
    let skinFraction: Double
    let skinChromaMean: Double
    let skinHueMean: Double
    let texture: TextureStatistics

    func encodedQuantile(_ probability: Double) -> Double {
        Self.value(in: lumaQuantiles, probability: probability)
    }

    func linearQuantile(_ probability: Double) -> Double {
        Self.value(in: linearLumaQuantiles, probability: probability)
    }

    static func analyze(_ image: NumericImage) -> ImageStatistics {
        let count = image.pixelCount
        guard count > 0 else {
            return ImageStatistics(
                image: image,
                lumaQuantiles: [Double](repeating: 0, count: probabilities.count),
                linearLumaQuantiles: [Double](repeating: 0, count: probabilities.count),
                skinLumaQuantiles: [Double](repeating: 0, count: probabilities.count),
                medianRelativeChroma: 0,
                neutralChannelLogs: nil,
                allChannelLogs: .zero,
                neutralFraction: 0,
                skinFraction: 0,
                skinChromaMean: 0,
                skinHueMean: 0,
                texture: .empty
            )
        }

        var luma = [Double]()
        var linearLuma = [Double]()
        luma.reserveCapacity(count)
        linearLuma.reserveCapacity(count)

        var skinLuma = [Double]()
        var skinChroma = [Double]()
        var skinHue = [Double]()
        var skinWeights = [Double]()
        var skinPixelCount = 0

        var relativeChroma = [Double]()
        var neutralRed = [Double]()
        var neutralGreen = [Double]()
        var neutralBlue = [Double]()
        var allRed = [Double]()
        var allGreen = [Double]()
        var allBlue = [Double]()
        neutralRed.reserveCapacity(count / 8)
        neutralGreen.reserveCapacity(count / 8)
        neutralBlue.reserveCapacity(count / 8)
        allRed.reserveCapacity(count)
        allGreen.reserveCapacity(count)
        allBlue.reserveCapacity(count)

        for index in 0..<count {
            let linear = image.linear[index]
            let skinWeight = Double(image.skin[index])
            let encoded = image.encodedLuma[index]
            luma.append(Double(encoded))
            linearLuma.append(Double(linear.luminance))

            let red = Double(linear.red)
            let green = Double(linear.green)
            let blue = Double(linear.blue)
            allRed.append(red)
            allGreen.append(green)
            allBlue.append(blue)

            if skinWeight > 0.5 {
                skinPixelCount += 1
                skinLuma.append(Double(encoded))
                skinWeights.append(skinWeight)
                let lab = LearningColor.lab(linear: linear)
                skinChroma.append(lab.chroma)
                skinHue.append(lab.hueDegrees)
            } else if encoded > 0.05, encoded < 0.96 {
                let decoded = LearningColor.linearToSRGB(Double(linear.red))
                let decodedGreen = LearningColor.linearToSRGB(Double(linear.green))
                let decodedBlue = LearningColor.linearToSRGB(Double(linear.blue))
                let maximum = max(decoded, decodedGreen, decodedBlue)
                let minimum = min(decoded, decodedGreen, decodedBlue)
                relativeChroma.append((maximum - minimum) / (Double(encoded) + 0.05))
            }

            let encodedRed = LearningColor.linearToSRGB(red)
            let encodedGreen = LearningColor.linearToSRGB(green)
            let encodedBlue = LearningColor.linearToSRGB(blue)
            let encodedMaximum = max(encodedRed, encodedGreen, encodedBlue)
            let encodedMinimum = min(encodedRed, encodedGreen, encodedBlue)
            let encodedChroma = encodedMaximum - encodedMinimum
            if skinWeight < 0.3,
               encoded > 0.10,
               encoded < 0.94,
               encodedChroma < 0.06 {
                neutralRed.append(red)
                neutralGreen.append(green)
                neutralBlue.append(blue)
            }
        }

        let neutralMinimum = max(32, count / 200)
        let useNeutral = neutralRed.count >= neutralMinimum
        let neutralLogs: SIMD3<Double>? = useNeutral
            ? SIMD3(
                log(max(LearningMath.quantile(of: neutralRed, probability: 0.5), 1e-6)),
                log(max(LearningMath.quantile(of: neutralGreen, probability: 0.5), 1e-6)),
                log(max(LearningMath.quantile(of: neutralBlue, probability: 0.5), 1e-6))
            )
            : nil

        let allLogs = SIMD3(
            log(max(LearningMath.quantile(of: allRed, probability: 0.5), 1e-6)),
            log(max(LearningMath.quantile(of: allGreen, probability: 0.5), 1e-6)),
            log(max(LearningMath.quantile(of: allBlue, probability: 0.5), 1e-6))
        )

        let skinWeightTotal = skinWeights.reduce(0, +)
        let skinChromaMean: Double
        if skinWeightTotal > 0 {
            skinChromaMean = zip(skinChroma, skinWeights)
                .reduce(0) { partial, entry in
                    partial + entry.0 * entry.1
                } / skinWeightTotal
        } else {
            skinChromaMean = 0
        }

        return ImageStatistics(
            image: image,
            lumaQuantiles: quantiles(of: luma),
            linearLumaQuantiles: quantiles(of: linearLuma),
            skinLumaQuantiles: quantiles(of: skinLuma),
            medianRelativeChroma: LearningMath.median(relativeChroma),
            neutralChannelLogs: neutralLogs,
            allChannelLogs: allLogs,
            neutralFraction: Double(neutralRed.count) / Double(count),
            skinFraction: Double(skinPixelCount) / Double(count),
            skinChromaMean: skinChromaMean,
            skinHueMean: LearningColor.circularMeanHue(skinHue, weights: skinWeights),
            texture: TextureAnalyzer.analyze(image)
        )
    }

    // MARK: - Helpers

    private static func quantiles(of values: [Double]) -> [Double] {
        guard !values.isEmpty else {
            return [Double](repeating: 0, count: probabilities.count)
        }
        let sorted = values.sorted()
        return probabilities.map { LearningMath.quantile(sorted: sorted, probability: $0) }
    }

    private static func value(in quantiles: [Double], probability: Double) -> Double {
        guard !quantiles.isEmpty else { return 0 }
        let target = LearningMath.clamp(probability, 0, 1)
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, candidate) in probabilities.enumerated() where index < quantiles.count {
            let distance = abs(candidate - target)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return quantiles[bestIndex]
    }
}

/// Skin-masked spatial statistics used to estimate retouch strength.
enum TextureAnalyzer {
    static func analyze(_ image: NumericImage) -> TextureStatistics {
        let width = image.width
        let height = image.height
        guard width >= 3, height >= 3 else { return .empty }

        var energy = 0.0
        var sampleCount = 0
        var absoluteLaplacians = [Double]()
        absoluteLaplacians.reserveCapacity(image.pixelCount / 4)

        let luma = image.encodedLuma
        let skin = image.skin

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                guard skin[index] > 0.6,
                      skin[index - 1] > 0.6,
                      skin[index + 1] > 0.6,
                      skin[index - width] > 0.6,
                      skin[index + width] > 0.6
                else {
                    continue
                }

                let center = Double(luma[index])
                let laplacian = 4 * center
                    - Double(luma[index - 1])
                    - Double(luma[index + 1])
                    - Double(luma[index - width])
                    - Double(luma[index + width])
                energy += laplacian * laplacian
                absoluteLaplacians.append(abs(laplacian))
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return .empty
        }

        var blockMeans = [Double]()
        let blockSize = 8
        var blockY = 0
        while blockY < height {
            var blockX = 0
            while blockX < width {
                var sum = 0.0
                var skinPixels = 0
                var pixels = 0
                let maxY = min(blockY + blockSize, height)
                let maxX = min(blockX + blockSize, width)
                for y in blockY..<maxY {
                    for x in blockX..<maxX {
                        let index = y * width + x
                        pixels += 1
                        if skin[index] > 0.5 {
                            sum += Double(luma[index])
                            skinPixels += 1
                        }
                    }
                }
                if pixels > 0, skinPixels * 2 >= pixels {
                    blockMeans.append(sum / Double(skinPixels))
                }
                blockX += blockSize
            }
            blockY += blockSize
        }

        return TextureStatistics(
            fineEnergy: energy / Double(sampleCount),
            fineP99: LearningMath.quantile(of: absoluteLaplacians, probability: 0.99),
            regionalVariation: LearningMath.standardDeviation(blockMeans),
            sampleCount: sampleCount
        )
    }
}
