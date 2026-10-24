import Foundation
import StyleToneCore

/// One pair's strength estimate before aggregation.
struct StrengthPairFit: Sendable {
    let skin: SkinParameters
    let face: FaceParameters
    let body: BodyParameters
    let finish: FinishParameters
    let weight: Double
    let issues: Set<StyleLearningIssue>
}

/// Estimates retouch and geometry strengths without doing face/body detection.
///
/// Smoothing, evenness and blemish strength are inferred from skin-masked
/// high-frequency texture loss. Face, body and leg strengths cannot be inferred
/// from colour statistics, so they come from ``PairStrengthSignals`` supplied by
/// the caller (or remain neutral). This is deliberate: the learning module must
/// not guess body shape from a photo, and the product forbids automatically
/// applying strong geometry.
enum StrengthFitter {
    static func fit(
        original: ImageStatistics,
        edited: ImageStatistics,
        signals: PairStrengthSignals?,
        qualityWeight: Double,
        configuration: StyleLearningConfiguration
    ) -> StrengthPairFit {
        var issues = Set<StyleLearningIssue>()
        let textureAvailable = original.texture.sampleCount >= 200
            && edited.texture.sampleCount >= 200

        var smoothing = imageEstimate(
            original: original.texture.fineEnergy,
            edited: edited.texture.fineEnergy
        )
        var evenness = imageEstimate(
            original: original.texture.regionalVariation,
            edited: edited.texture.regionalVariation
        )
        var blemish = imageEstimate(
            original: original.texture.fineP99,
            edited: edited.texture.fineP99
        )

        if !textureAvailable {
            smoothing = 0
            evenness = 0
            blemish = 0
            issues.insert(.insufficientSkin)
        }
        if original.skinFraction < 0.01 {
            issues.insert(.insufficientSkin)
        }
        if original.image.pixelCount < 1024 {
            issues.insert(.lowResolutionPair)
        }

        if let signal = sanitized(signals?.smoothing) {
            smoothing = LearningMath.unit(signal)
        }
        if let signal = sanitized(signals?.evenness) {
            evenness = LearningMath.unit(signal)
        }
        if let signal = sanitized(signals?.blemish) {
            blemish = LearningMath.unit(signal)
        }

        let faceSlim = LearningMath.unit(sanitized(signals?.faceSlim) ?? 0)
        let jaw = LearningMath.unit(sanitized(signals?.jaw) ?? 0)
        let arm = LearningMath.unit(sanitized(signals?.arm) ?? 0)
        let waist = LearningMath.unit(sanitized(signals?.waist) ?? 0)
        let leg = LearningMath.unit(sanitized(signals?.leg) ?? 0)
        let legLength = LearningMath.clamp(
            sanitized(signals?.legLength) ?? 1,
            1,
            1.15
        )
        let grain = LearningMath.unit(sanitized(signals?.grain) ?? 0)
        let vignette = LearningMath.clamp(
            sanitized(signals?.vignette) ?? 0,
            -1,
            0
        )

        let safety = configuration.safety
        let skin = safety.clamped(
            skin: SkinParameters(
                smoothing: smoothing,
                evenness: evenness,
                blemish: blemish
            )
        )
        let face = safety.clamped(
            face: FaceParameters(slim: faceSlim, jaw: jaw)
        )
        let body = safety.clamped(
            body: BodyParameters(
                arm: arm,
                waist: waist,
                leg: leg,
                legLength: legLength
            )
        )
        let finish = safety.clamped(
            finish: FinishParameters(grain: grain, vignette: vignette)
        )

        let reliability: Double
        if signals != nil {
            reliability = 1
        } else if textureAvailable {
            reliability = 0.85
        } else {
            reliability = 0.35
        }
        let weight = LearningMath.unit(qualityWeight * reliability)

        return StrengthPairFit(
            skin: skin,
            face: face,
            body: body,
            finish: finish,
            weight: weight,
            issues: issues
        )
    }

    private static func imageEstimate(original: Double, edited: Double) -> Double {
        guard original.isFinite, edited.isFinite, original > 1e-6 else { return 0 }
        let ratio = LearningMath.safeRatio(edited, original)
        return LearningMath.unit(1 - ratio.squareRoot())
    }

    private static func sanitized(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }
}
