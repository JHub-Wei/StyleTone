import Foundation
import StyleToneCore

/// One pair's tone estimate before aggregation.
struct TonePairFit: Sendable {
    let tone: ToneParameters
    let weight: Double
    let skinProtectionApplied: Bool
    let skinChromaGain: Double
    let skinHueShift: Double
    let issues: Set<StyleLearningIssue>
}

/// Fits exposure, contrast, highlight/shadow response, white balance and
/// saturation from an original/edited pair.
///
/// The estimator compares robust distribution statistics instead of aligned
/// pixels, because a user's edited export may have a slightly different crop or
/// compression. Skin-like pixels are excluded from white balance and saturation
/// fitting, then checked again against the skin guard.
enum ToneFitter {
    static func fit(
        original: ImageStatistics,
        edited: ImageStatistics,
        qualityWeight: Double,
        configuration: StyleLearningConfiguration
    ) -> TonePairFit? {
        guard original.image.pixelCount >= 16,
              edited.image.pixelCount >= 16
        else {
            return nil
        }

        let safety = configuration.safety
        var issues = Set<StyleLearningIssue>()

        // Quantile transfer: regressing edited luma on original luma gives a
        // robust tone curve slope/intercept without requiring pixel alignment.
        let probabilities = [0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95]
        let originalLuma = probabilities.map { original.encodedQuantile($0) }
        let editedLuma = probabilities.map { edited.encodedQuantile($0) }
        let meanOriginal = originalLuma.reduce(0, +) / Double(originalLuma.count)
        let meanEdited = editedLuma.reduce(0, +) / Double(editedLuma.count)

        var covariance = 0.0
        var variance = 0.0
        for index in originalLuma.indices {
            let deltaOriginal = originalLuma[index] - meanOriginal
            covariance += deltaOriginal * (editedLuma[index] - meanEdited)
            variance += deltaOriginal * deltaOriginal
        }

        let slope = variance > 1e-7
            ? LearningMath.clamp(covariance / variance, 0.2, 3.0)
            : 1.0
        let intercept = meanEdited - slope * meanOriginal

        let originalLinearMedian = max(original.linearQuantile(0.50), 1e-5)
        let editedLinearMedian = max(edited.linearQuantile(0.50), 1e-5)
        let exposure = LearningMath.clamp(
            0.45 * LearningMath.safeLog2(editedLinearMedian / originalLinearMedian),
            to: -safety.exposure...safety.exposure
        )

        let contrast = LearningMath.clamp(
            (slope - 1) * 0.8,
            to: -safety.contrast...safety.contrast
        )

        let originalHigh = original.encodedQuantile(0.95)
        let editedHigh = edited.encodedQuantile(0.95)
        let highResidual = editedHigh - (intercept + slope * originalHigh)
        let highlights = LearningMath.clamp(
            highResidual * 2.5,
            to: -safety.highlights...safety.highlights
        )

        let originalLow = original.encodedQuantile(0.05)
        let editedLow = edited.encodedQuantile(0.05)
        let lowResidual = editedLow - (intercept + slope * originalLow)
        let shadows = LearningMath.clamp(
            lowResidual * 2.5,
            to: -safety.shadows...safety.shadows
        )

        // White balance is measured on near-neutral, non-skin pixels. Median
        // channel ratios are much less sensitive to content than a grey-world
        // mean and survive a warm/cool edit without amplifying local colour.
        let useNeutral = original.neutralChannelLogs != nil && edited.neutralChannelLogs != nil
        if !useNeutral {
            issues.insert(.insufficientNeutral)
        }
        let originalLogs = original.neutralChannelLogs ?? original.allChannelLogs
        let editedLogs = edited.neutralChannelLogs ?? edited.allChannelLogs
        let channelDifference = editedLogs - originalLogs
        let meanChannelDifference = (channelDifference.x + channelDifference.y + channelDifference.z) / 3
        let redDifference = channelDifference.x - meanChannelDifference
        let blueDifference = channelDifference.z - meanChannelDifference

        var temperature = LearningMath.clamp(
            (redDifference - blueDifference) * 0.8,
            to: -safety.temperature...safety.temperature
        )
        var tint = LearningMath.clamp(
            (redDifference + blueDifference) * 0.8,
            to: -safety.tint...safety.tint
        )

        let gains = SIMD3(
            LearningMath.clamp(exp(channelDifference.x), 0.2, 5),
            LearningMath.clamp(exp(channelDifference.y), 0.2, 5),
            LearningMath.clamp(exp(channelDifference.z), 0.2, 5)
        )

        // Saturation is measured on relative chroma so exposure does not leak
        // into the estimate. Edited pixels are first divided by the fitted white
        // balance gains, otherwise a warm edit would masquerade as saturation.
        let originalChroma: Double
        let editedChroma: Double
        if original.image.width == edited.image.width,
           original.image.height == edited.image.height {
            originalChroma = relativeChromaMean(
                image: original.image,
                channelGains: SIMD3(repeating: 1)
            )
            editedChroma = relativeChromaMean(
                image: edited.image,
                channelGains: gains
            )
        } else {
            originalChroma = original.medianRelativeChroma
            editedChroma = edited.medianRelativeChroma
            issues.insert(.mismatchedPair)
        }

        var saturation = LearningMath.clamp(
            (LearningMath.safeRatio(editedChroma, originalChroma) - 1) * 1.4,
            to: -safety.saturation...safety.saturation
        )

        var skinProtectionApplied = false
        var skinChromaGain = 1.0
        var skinHueShift = 0.0
        let skinConfiguration = configuration.skinProtection
        if skinConfiguration.isEnabled,
           original.skinFraction >= skinConfiguration.minimumSkinFraction,
           edited.skinFraction >= skinConfiguration.minimumSkinFraction {
            let originalSkinChroma = max(original.skinChromaMean, 0.01)
            let editedSkinChroma = max(edited.skinChromaMean, 0.01)
            skinChromaGain = editedSkinChroma / originalSkinChroma
            skinHueShift = LearningMath.hueDistance(
                original.skinHueMean,
                edited.skinHueMean
            )

            if skinChromaGain > skinConfiguration.maximumChromaGain, saturation > 0 {
                let factor = LearningMath.clamp(
                    skinConfiguration.maximumChromaGain / skinChromaGain,
                    0.15,
                    1
                )
                saturation *= factor
                skinProtectionApplied = true
            }

            if skinHueShift > skinConfiguration.maximumHueShiftDegrees {
                let factor = LearningMath.clamp(
                    skinConfiguration.maximumHueShiftDegrees / skinHueShift,
                    0.15,
                    1
                )
                temperature *= factor
                tint *= factor
                if saturation > 0 {
                    saturation *= factor
                }
                skinProtectionApplied = true
            }
        } else {
            issues.insert(.insufficientSkin)
        }

        if skinProtectionApplied {
            issues.insert(.skinToneGuarded)
        }

        let tone = safety.clamped(
            tone: ToneParameters(
                exposure: exposure,
                contrast: contrast,
                highlights: highlights,
                shadows: shadows,
                temperature: temperature,
                tint: tint,
                saturation: saturation
            )
        )

        let neutralReliability = 0.55
            + 0.45 * LearningMath.unit(original.neutralFraction / 0.08)
        let sizeReliability = 0.70
            + 0.30 * LearningMath.unit(Double(original.image.pixelCount) / 4096)
        let weight = LearningMath.unit(
            qualityWeight * neutralReliability * sizeReliability
        )

        return TonePairFit(
            tone: tone,
            weight: weight,
            skinProtectionApplied: skinProtectionApplied,
            skinChromaGain: skinChromaGain,
            skinHueShift: skinHueShift,
            issues: issues
        )
    }

    /// Mean relative chroma (chroma divided by luma) of non-skin pixels after
    /// dividing the image by `channelGains`.
    private static func relativeChromaMean(
        image: NumericImage,
        channelGains: SIMD3<Double>
    ) -> Double {
        guard image.pixelCount > 0 else { return 0 }
        let redGain = max(channelGains.x, 1e-4)
        let greenGain = max(channelGains.y, 1e-4)
        let blueGain = max(channelGains.z, 1e-4)

        var sum = 0.0
        var count = 0
        for index in 0..<image.pixelCount where image.skin[index] <= 0.5 {
            let pixel = image.linear[index]
            let red = Double(pixel.x) / redGain
            let green = Double(pixel.y) / greenGain
            let blue = Double(pixel.z) / blueGain
            let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            guard luma > 0.01 else { continue }
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            sum += (maximum - minimum) / (luma + 0.05)
            count += 1
        }
        return count > 0 ? sum / Double(count) : 0
    }
}
