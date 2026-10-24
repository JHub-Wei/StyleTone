import Foundation
import StyleToneCore

/// Shrink-to-neutral schedule for 3/5/8 pair calibration.
///
/// Three pairs are a weak signal, so every learned parameter is pulled hard
/// toward the natural default. Five pairs are usable but still conservative.
/// Eight consistent pairs are allowed to keep almost all of the fitted value.
/// Quality and hold-out error scale the schedule further down.
enum ShrinkageModel {
    static func factor(
        acceptedPairCount: Int,
        holdoutError: Double,
        meanQuality: Double
    ) -> Double {
        let base: Double
        switch acceptedPairCount {
        case ..<2:
            base = 0.15
        case 2:
            base = 0.22
        case 3:
            base = 0.35
        case 4:
            base = 0.55
        case 5:
            base = 0.72
        case 6:
            base = 0.82
        case 7:
            base = 0.90
        default:
            base = 1.0
        }

        let quality = 0.65 + 0.35 * LearningMath.unit(meanQuality)
        let error = 1 - 0.45 * LearningMath.unit(holdoutError)
        return LearningMath.clamp(base * quality * error, 0.05, 1)
    }

    static func shrink(_ style: AggregatedStyle, by factor: Double) -> AggregatedStyle {
        let scale = LearningMath.unit(factor)
        return AggregatedStyle(
            tone: ToneParameters(
                exposure: style.tone.exposure * scale,
                contrast: style.tone.contrast * scale,
                highlights: style.tone.highlights * scale,
                shadows: style.tone.shadows * scale,
                temperature: style.tone.temperature * scale,
                tint: style.tone.tint * scale,
                saturation: style.tone.saturation * scale
            ),
            skin: SkinParameters(
                smoothing: style.skin.smoothing * scale,
                evenness: style.skin.evenness * scale,
                blemish: style.skin.blemish * scale
            ),
            face: FaceParameters(
                slim: style.face.slim * scale,
                jaw: style.face.jaw * scale
            ),
            body: BodyParameters(
                arm: style.body.arm * scale,
                waist: style.body.waist * scale,
                leg: style.body.leg * scale,
                legLength: 1 + (style.body.legLength - 1) * scale
            ),
            finish: FinishParameters(
                grain: style.finish.grain * scale,
                vignette: style.finish.vignette * scale
            ),
            outlierCount: style.outlierCount
        )
    }
}

/// Maps pair count, quality and hold-out error to the public confidence enum.
enum ConfidenceModel {
    static func level(
        acceptedPairCount: Int,
        holdoutError: Double,
        meanQuality: Double,
        configuration: StyleLearningConfiguration
    ) -> ConfidenceLevel {
        let qualityOK = meanQuality >= 0.75
        if acceptedPairCount >= configuration.stablePairCount,
           holdoutError <= configuration.stableHoldoutError,
           qualityOK {
            return .stable
        }
        if acceptedPairCount >= configuration.standardPairCount,
           holdoutError <= configuration.standardHoldoutError,
           meanQuality >= 0.5 {
            return .standard
        }
        return .trial
    }
}

/// Applies shrink, AB preference and the safety envelope, then builds the
/// final `StyleProfile` with localization-key tags.
enum ProfileAssembler {
    struct Output: Sendable {
        let profile: StyleProfile
        let safetyClamped: Bool
    }

    static func assemble(
        style: AggregatedStyle,
        shrinkFactor: Double,
        adjustment: ABAdjustment,
        pairCount: Int,
        confidence: ConfidenceLevel,
        date: Date,
        safety: StyleSafetyRanges
    ) -> Output {
        let shrunk = ShrinkageModel.shrink(style, by: shrinkFactor)
        let naturalness = LearningMath.clamp(adjustment.naturalnessScale, 0.8, 1.15)

        var tone = ToneParameters(
            exposure: shrunk.tone.exposure + adjustment.tone.exposure,
            contrast: shrunk.tone.contrast + adjustment.tone.contrast,
            highlights: shrunk.tone.highlights + adjustment.tone.highlights,
            shadows: shrunk.tone.shadows + adjustment.tone.shadows,
            temperature: shrunk.tone.temperature + adjustment.tone.temperature,
            tint: shrunk.tone.tint + adjustment.tone.tint,
            saturation: shrunk.tone.saturation + adjustment.tone.saturation
        )
        tone = safety.clamped(tone: tone)

        var skin = SkinParameters(
            smoothing: shrunk.skin.smoothing * naturalness + adjustment.skin.smoothing,
            evenness: shrunk.skin.evenness * naturalness + adjustment.skin.evenness,
            blemish: shrunk.skin.blemish * naturalness + adjustment.skin.blemish
        )
        skin = safety.clamped(skin: skin)

        var face = FaceParameters(
            slim: shrunk.face.slim * naturalness + adjustment.face.slim,
            jaw: shrunk.face.jaw * naturalness + adjustment.face.jaw
        )
        face = safety.clamped(face: face)

        var body = BodyParameters(
            arm: shrunk.body.arm * naturalness + adjustment.body.arm,
            waist: shrunk.body.waist * naturalness + adjustment.body.waist,
            leg: shrunk.body.leg * naturalness + adjustment.body.leg,
            legLength: 1
                + (shrunk.body.legLength - 1) * naturalness
                + adjustment.body.legLength
        )
        body = safety.clamped(body: body)

        var finish = FinishParameters(
            grain: shrunk.finish.grain * naturalness,
            vignette: shrunk.finish.vignette * naturalness
        )
        finish = safety.clamped(finish: finish)

        let candidate = StyleProfile(
            schemaVersion: StyleLearningAlgorithm.schemaVersion,
            algorithmVersion: StyleLearningAlgorithm.version,
            pairCount: pairCount,
            confidence: confidence,
            tone: tone,
            skin: skin,
            face: face,
            body: body,
            finish: finish,
            tags: [],
            updatedAt: date
        )
        let clamped = safety.clamp(candidate)
        let didClamp = clamped.tone != candidate.tone
            || clamped.skin != candidate.skin
            || clamped.face != candidate.face
            || clamped.body != candidate.body
            || clamped.finish != candidate.finish

        var profile = clamped
        profile.tags = tags(for: profile)
        return Output(profile: profile, safetyClamped: didClamp)
    }

    private static func tags(for profile: StyleProfile) -> [String] {
        var tags = ["style.tag.natural"]
        if profile.tone.temperature > 0.04 || profile.tone.tint > 0.04 {
            tags.append("style.tag.warm")
        }
        if profile.skin.smoothing >= 0.10 || profile.skin.evenness >= 0.08 {
            tags.append("style.tag.soft")
        }
        if profile.face.slim >= 0.07 || profile.face.jaw >= 0.05
            || profile.body.waist >= 0.06 || profile.body.arm >= 0.06
            || profile.body.leg >= 0.06 {
            tags.append("style.tag.defined")
        }
        if profile.tone.contrast >= 0.10 || profile.tone.saturation >= 0.12
            || profile.finish.grain >= 0.04 || profile.body.legLength >= 1.02
            || profile.tone.highlights <= -0.08 {
            tags.append("style.tag.editorial")
        }
        return tags
    }
}
