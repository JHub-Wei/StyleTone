import Foundation
import StyleToneCore

/// Stand-in `StyleLearning` for WP-10 until WP-11 lands.
///
/// It is deterministic, local, and produces a safe profile with a confidence
/// level derived from the selected pair count. AB answers nudge the relevant
/// parameters, so replacing this with the real learner is a one-line injection
/// change in the view model.
public struct CalibrationMockStyleLearning: StyleLearning {
    private let fixedDate: Date?

    /// - Parameter now: fixed timestamp for deterministic tests; production
    ///   previews use the current time.
    public init(now: Date? = nil) {
        self.fixedDate = now
    }

    public func learn(
        samples: [PairSample],
        answers: [CalibrationAnswer]
    ) async throws -> StyleProfile {
        guard !samples.isEmpty else {
            throw StyleToneError.invalidState
        }

        let pairCount = samples.count
        let confidence: ConfidenceLevel
        if pairCount >= CalibrationLimits.maximumPairCount {
            confidence = .stable
        } else if pairCount >= CalibrationLimits.mediumPairCount {
            confidence = .standard
        } else {
            confidence = .trial
        }

        // Three pairs intentionally shrink hard; eight are allowed close to the
        // observed AB direction. Every parameter initializer clamps to the
        // safe contract ranges a second time.
        let shrink: Double
        if pairCount < CalibrationLimits.mediumPairCount {
            shrink = 0.55
        } else if pairCount < CalibrationLimits.maximumPairCount {
            shrink = 0.78
        } else {
            shrink = 1.0
        }

        var tone = ToneParameters(
            exposure: 0.04,
            contrast: 0.05,
            highlights: -0.05,
            shadows: 0.06,
            temperature: 0.02,
            tint: 0,
            saturation: 0.04
        )
        var skin = SkinParameters(smoothing: 0.22, evenness: 0.15, blemish: 0.10)
        var face = FaceParameters(slim: 0.12, jaw: 0.08)
        var body = BodyParameters(arm: 0.08, waist: 0.08, leg: 0.05, legLength: 1.01)
        var finish = FinishParameters(grain: 0.03, vignette: -0.03)

        var wantsEditorial = false
        var wantsSoft = false
        var wantsDefined = false
        var wantsWarm = false

        for answer in answers {
            let delta = answer.strengthDelta
            switch answer.dimension {
            case .tone:
                tone.contrast += delta * 0.16
                tone.saturation += delta * 0.10
            case .skinTone:
                tone.temperature += delta * 0.16
                tone.tint += delta * 0.04
                wantsWarm = wantsWarm || delta > 0
            case .smoothing:
                skin.smoothing += delta * 0.14
                skin.evenness += delta * 0.08
                wantsSoft = wantsSoft || delta > 0
            case .faceSlim:
                face.slim += delta * 0.14
                face.jaw += delta * 0.08
                wantsDefined = wantsDefined || delta > 0
            case .bodySlim:
                body.waist += delta * 0.10
                body.arm += delta * 0.06
                wantsDefined = wantsDefined || delta > 0
            case .legLength:
                body.legLength += delta * 0.025
                wantsDefined = wantsDefined || delta > 0
            case .naturalness:
                tone.saturation += delta * 0.08
                skin.smoothing += delta * 0.04
                face.slim += delta * 0.04
                finish.grain += delta * 0.03
                wantsEditorial = wantsEditorial || delta > 0
            }
        }

        tone = ToneParameters(
            exposure: tone.exposure * shrink,
            contrast: tone.contrast * shrink,
            highlights: tone.highlights * shrink,
            shadows: tone.shadows * shrink,
            temperature: tone.temperature * shrink,
            tint: tone.tint * shrink,
            saturation: tone.saturation * shrink
        )
        skin = SkinParameters(
            smoothing: skin.smoothing * shrink,
            evenness: skin.evenness * shrink,
            blemish: skin.blemish * shrink
        )
        face = FaceParameters(slim: face.slim * shrink, jaw: face.jaw * shrink)
        body = BodyParameters(
            arm: body.arm * shrink,
            waist: body.waist * shrink,
            leg: body.leg * shrink,
            legLength: 1 + ((body.legLength - 1) * shrink)
        )
        finish = FinishParameters(grain: finish.grain * shrink, vignette: finish.vignette * shrink)

        var tags = ["style.tag.natural"]
        if wantsWarm {
            tags.append("style.tag.warm")
        }
        if wantsSoft {
            tags.append("style.tag.soft")
        }
        if wantsDefined {
            tags.append("style.tag.defined")
        }
        if wantsEditorial {
            tags.append("style.tag.editorial")
        }

        return StyleProfile(
            algorithmVersion: "st-3.0.0-mock",
            pairCount: pairCount,
            confidence: confidence,
            tone: tone,
            skin: skin,
            face: face,
            body: body,
            finish: finish,
            tags: tags,
            updatedAt: fixedDate ?? Date()
        )
    }
}

/// Small in-memory profile store for SwiftUI previews and the standalone demo.
/// Production injects the WP-08 `StyleProfileStore` instead.
public actor CalibrationPreviewStyleProfileStore: StyleProfileStore {
    private var profile: StyleProfile?

    public init(profile: StyleProfile? = nil) {
        self.profile = profile
    }

    public func loadActive() async throws -> StyleProfile? {
        profile
    }

    public func save(_ profile: StyleProfile) async throws {
        self.profile = profile
    }

    public func deleteAll() async throws {
        profile = nil
    }
}
