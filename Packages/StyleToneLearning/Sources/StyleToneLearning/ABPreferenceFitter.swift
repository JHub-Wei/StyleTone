import Foundation
import StyleToneCore

/// Raw AB deltas. Core parameter initialisers clamp strengths to `0...1`, so
/// negative preferences must be represented as raw deltas and applied after
/// aggregation.
struct ABAdjustment: Sendable, Equatable {
    struct SkinDelta: Sendable, Equatable {
        var smoothing = 0.0
        var evenness = 0.0
        var blemish = 0.0
    }

    struct FaceDelta: Sendable, Equatable {
        var slim = 0.0
        var jaw = 0.0
    }

    struct BodyDelta: Sendable, Equatable {
        var arm = 0.0
        var waist = 0.0
        var leg = 0.0
        var legLength = 0.0
    }

    var tone = ToneParameters()
    var skin = SkinDelta()
    var face = FaceDelta()
    var body = BodyDelta()
    var naturalnessScale = 1.0
    var appliedAnswerCount = 0
    var ambiguousAnswerCount = 0
}

/// Converts 6–8 AB choices into bounded parameter nudges.
///
/// `CalibrationAnswer.strengthDelta` is the signed preference for more (+) or
/// less (−) strength. The UI is free to place either candidate on side A, so
/// `choseA` is intentionally not used for direction. Six answers reach full
/// influence; fewer choices are scaled down. Each choice moves its dimension
/// by a visible but bounded amount, and the safety envelope still applies.
enum ABPreferenceFitter {
    static func adjustment(
        answers: [CalibrationAnswer],
        configuration: StyleLearningConfiguration
    ) -> ABAdjustment {
        var buckets: [String: [Double]] = [:]
        var processed = 0
        var ambiguous = 0

        for answer in answers {
            guard answer.strengthDelta.isFinite else { continue }
            processed += 1
            let delta = LearningMath.signedUnit(answer.strengthDelta)
            if abs(delta) < 1e-6 {
                ambiguous += 1
            }
            buckets[answer.dimension.rawValue, default: []].append(delta)
        }

        guard processed > 0 else {
            return ABAdjustment()
        }

        let reliability = min(
            1,
            Double(processed) / Double(configuration.fullInfluenceAnswerCount)
        )

        let tonePreference = preference(for: .tone, buckets: buckets)
        let skinTonePreference = preference(for: .skinTone, buckets: buckets)
        let smoothingPreference = preference(for: .smoothing, buckets: buckets)
        let facePreference = preference(for: .faceSlim, buckets: buckets)
        let bodyPreference = preference(for: .bodySlim, buckets: buckets)
        let legPreference = preference(for: .legLength, buckets: buckets)
        let naturalnessPreference = preference(for: .naturalness, buckets: buckets)

        var adjustment = ABAdjustment()
        adjustment.appliedAnswerCount = processed
        adjustment.ambiguousAnswerCount = ambiguous

        adjustment.tone = ToneParameters(
            exposure: 0.10 * tonePreference * reliability,
            contrast: 0.25 * tonePreference * reliability
                + 0.08 * naturalnessPreference * reliability,
            highlights: 0,
            shadows: 0,
            temperature: 0.20 * skinTonePreference * reliability,
            tint: 0.10 * skinTonePreference * reliability,
            saturation: 0.22 * tonePreference * reliability
                + 0.08 * naturalnessPreference * reliability
        )

        adjustment.skin = ABAdjustment.SkinDelta(
            smoothing: 0.45 * smoothingPreference * reliability,
            evenness: 0.20 * smoothingPreference * reliability
                + 0.10 * skinTonePreference * reliability,
            blemish: 0.12 * smoothingPreference * reliability
        )

        adjustment.face = ABAdjustment.FaceDelta(
            slim: 0.30 * facePreference * reliability,
            jaw: 0.18 * facePreference * reliability
        )

        adjustment.body = ABAdjustment.BodyDelta(
            arm: 0.30 * bodyPreference * reliability,
            waist: 0.30 * bodyPreference * reliability,
            leg: 0.25 * bodyPreference * reliability,
            legLength: 0.06 * legPreference * reliability
        )

        adjustment.naturalnessScale = LearningMath.clamp(
            1 + 0.12 * naturalnessPreference * reliability,
            0.80,
            1.15
        )

        return adjustment
    }

    private static func preference(
        for dimension: CalibrationDimension,
        buckets: [String: [Double]]
    ) -> Double {
        guard let values = buckets[dimension.rawValue], !values.isEmpty else { return 0 }
        let sum = values.reduce(0, +)
        let denominator = max(1.0, Double(values.count).squareRoot())
        return tanh(sum / denominator)
    }
}
