import Foundation
import StyleToneCore

/// Safety envelope applied to every learned `StyleProfile`.
///
/// `StyleToneCore` clamps parameters to their full contract ranges (for example
/// `skin.smoothing` to `0...1`). Learning uses a narrower envelope on purpose:
/// a personalised profile must be safe to apply without the user inspecting
/// every slider first, and the product explicitly forbids automatically
/// applying high-strength geometry.
///
/// The ranges are symmetric around the neutral value for signed parameters,
/// `0...max` for strengths and `1...legLengthMax` for leg length. They are part
/// of the public surface so the calibration UI can explain the limits and tests
/// can assert them without duplicating literals.
public struct StyleSafetyRanges: Sendable, Equatable {
    /// Maximum absolute learned exposure.
    public var exposure: Double
    /// Maximum absolute learned contrast.
    public var contrast: Double
    /// Maximum absolute learned highlight adjustment.
    public var highlights: Double
    /// Maximum absolute learned shadow adjustment.
    public var shadows: Double
    /// Maximum absolute learned temperature adjustment.
    public var temperature: Double
    /// Maximum absolute learned tint adjustment.
    public var tint: Double
    /// Maximum absolute learned saturation adjustment.
    public var saturation: Double

    /// Maximum learned skin smoothing.
    public var smoothing: Double
    /// Maximum learned skin evenness.
    public var evenness: Double
    /// Maximum learned blemish strength.
    public var blemish: Double

    /// Maximum learned face slim strength.
    public var faceSlim: Double
    /// Maximum learned jaw strength.
    public var jaw: Double

    /// Maximum learned arm slim strength.
    public var arm: Double
    /// Maximum learned waist slim strength.
    public var waist: Double
    /// Maximum learned leg slim strength.
    public var leg: Double
    /// Maximum learned leg length multiplier. The minimum is always `1.0`.
    public var legLengthMax: Double

    /// Maximum learned film grain.
    public var grain: Double
    /// Most negative learned vignette. The maximum is always `0`.
    public var vignetteMin: Double

    /// Production defaults: a gentle, natural-looking envelope.
    public static let standard = StyleSafetyRanges()

    /// Creates a safety envelope. Out-of-range and non-finite values fall back
    /// to the production defaults component by component.
    public init(
        exposure: Double = 0.35,
        contrast: Double = 0.45,
        highlights: Double = 0.50,
        shadows: Double = 0.50,
        temperature: Double = 0.40,
        tint: Double = 0.35,
        saturation: Double = 0.45,
        smoothing: Double = 0.55,
        evenness: Double = 0.50,
        blemish: Double = 0.45,
        faceSlim: Double = 0.35,
        jaw: Double = 0.30,
        arm: Double = 0.30,
        waist: Double = 0.30,
        leg: Double = 0.30,
        legLengthMax: Double = 1.08,
        grain: Double = 0.15,
        vignetteMin: Double = -0.18
    ) {
        self.exposure = Self.unit(exposure, fallback: 0.35)
        self.contrast = Self.unit(contrast, fallback: 0.45)
        self.highlights = Self.unit(highlights, fallback: 0.50)
        self.shadows = Self.unit(shadows, fallback: 0.50)
        self.temperature = Self.unit(temperature, fallback: 0.40)
        self.tint = Self.unit(tint, fallback: 0.35)
        self.saturation = Self.unit(saturation, fallback: 0.45)
        self.smoothing = Self.unit(smoothing, fallback: 0.55)
        self.evenness = Self.unit(evenness, fallback: 0.50)
        self.blemish = Self.unit(blemish, fallback: 0.45)
        self.faceSlim = Self.unit(faceSlim, fallback: 0.35)
        self.jaw = Self.unit(jaw, fallback: 0.30)
        self.arm = Self.unit(arm, fallback: 0.30)
        self.waist = Self.unit(waist, fallback: 0.30)
        self.leg = Self.unit(leg, fallback: 0.30)
        self.legLengthMax = Self.legLength(legLengthMax, fallback: 1.08)
        self.grain = Self.unit(grain, fallback: 0.15)
        self.vignetteMin = Self.vignette(vignetteMin, fallback: -0.18)
    }

    /// Returns a copy of `profile` with every parameter clamped to this range.
    public func clamp(_ profile: StyleProfile) -> StyleProfile {
        var result = profile
        result.tone = clamped(tone: profile.tone)
        result.skin = clamped(skin: profile.skin)
        result.face = clamped(face: profile.face)
        result.body = clamped(body: profile.body)
        result.finish = clamped(finish: profile.finish)
        return result
    }

    /// True when every parameter of `profile` lies inside this range.
    ///
    /// `tolerance` absorbs floating-point noise from aggregation; pass `0` for
    /// an exact check.
    public func contains(_ profile: StyleProfile, tolerance: Double = 1e-9) -> Bool {
        let epsilon = max(tolerance, 0)
        return values(of: profile).allSatisfy { entry in
            let (value, range) = entry
            return value.isFinite
                && value >= range.lowerBound - epsilon
                && value <= range.upperBound + epsilon
        }
    }

    // MARK: - Internal clamps

    func clamped(tone: ToneParameters) -> ToneParameters {
        ToneParameters(
            exposure: clamp(tone.exposure, symmetric: exposure),
            contrast: clamp(tone.contrast, symmetric: contrast),
            highlights: clamp(tone.highlights, symmetric: highlights),
            shadows: clamp(tone.shadows, symmetric: shadows),
            temperature: clamp(tone.temperature, symmetric: temperature),
            tint: clamp(tone.tint, symmetric: tint),
            saturation: clamp(tone.saturation, symmetric: saturation)
        )
    }

    func clamped(skin: SkinParameters) -> SkinParameters {
        SkinParameters(
            smoothing: clamp(skin.smoothing, upper: smoothing),
            evenness: clamp(skin.evenness, upper: evenness),
            blemish: clamp(skin.blemish, upper: blemish)
        )
    }

    func clamped(face: FaceParameters) -> FaceParameters {
        FaceParameters(
            slim: clamp(face.slim, upper: faceSlim),
            jaw: clamp(face.jaw, upper: jaw)
        )
    }

    func clamped(body: BodyParameters) -> BodyParameters {
        BodyParameters(
            arm: clamp(body.arm, upper: arm),
            waist: clamp(body.waist, upper: waist),
            leg: clamp(body.leg, upper: leg),
            legLength: min(max(body.legLength, 1), legLengthMax)
        )
    }

    func clamped(finish: FinishParameters) -> FinishParameters {
        FinishParameters(
            grain: clamp(finish.grain, upper: grain),
            vignette: min(max(finish.vignette, vignetteMin), 0)
        )
    }

    // MARK: - Helpers

    private func values(of profile: StyleProfile) -> [(Double, ClosedRange<Double>)] {
        [
            (profile.tone.exposure, (-exposure)...exposure),
            (profile.tone.contrast, (-contrast)...contrast),
            (profile.tone.highlights, (-highlights)...highlights),
            (profile.tone.shadows, (-shadows)...shadows),
            (profile.tone.temperature, (-temperature)...temperature),
            (profile.tone.tint, (-tint)...tint),
            (profile.tone.saturation, (-saturation)...saturation),
            (profile.skin.smoothing, 0...smoothing),
            (profile.skin.evenness, 0...evenness),
            (profile.skin.blemish, 0...blemish),
            (profile.face.slim, 0...faceSlim),
            (profile.face.jaw, 0...jaw),
            (profile.body.arm, 0...arm),
            (profile.body.waist, 0...waist),
            (profile.body.leg, 0...leg),
            (profile.body.legLength, 1...legLengthMax),
            (profile.finish.grain, 0...grain),
            (profile.finish.vignette, vignetteMin...0)
        ]
    }

    private func clamp(_ value: Double, symmetric limit: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -limit), limit)
    }

    private func clamp(_ value: Double, upper limit: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), limit)
    }

    private static func unit(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite, value >= 0 else { return fallback }
        return min(value, 1)
    }

    private static func legLength(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite, value >= 1 else { return fallback }
        return min(max(value, 1), 1.15)
    }

    private static func vignette(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite, value <= 0 else { return fallback }
        return max(value, -1)
    }
}

/// Limits that keep learned tone changes from shifting skin hue or saturation.
///
/// The learner sees image pairs, not a face analysis. It builds a colour-based
/// skin likelihood internally, fits white balance and saturation on non-skin
/// pixels, and then verifies the skin region did not move outside these limits.
/// When it did, the offending parameters are scaled back before the profile is
/// written.
public struct SkinProtectionConfiguration: Sendable, Equatable {
    /// Enables the post-fit skin guard.
    public var isEnabled: Bool
    /// Maximum allowed relative gain of mean skin chroma.
    public var maximumChromaGain: Double
    /// Maximum allowed skin hue rotation, in degrees.
    public var maximumHueShiftDegrees: Double
    /// Below this skin fraction the guard is skipped (no reliable measurement).
    public var minimumSkinFraction: Double

    /// Production defaults.
    public static let standard = SkinProtectionConfiguration()

    public init(
        isEnabled: Bool = true,
        maximumChromaGain: Double = 1.12,
        maximumHueShiftDegrees: Double = 6,
        minimumSkinFraction: Double = 0.01
    ) {
        self.isEnabled = isEnabled
        self.maximumChromaGain = maximumChromaGain.isFinite
            ? max(1, maximumChromaGain)
            : 1.12
        self.maximumHueShiftDegrees = maximumHueShiftDegrees.isFinite
            ? max(0, maximumHueShiftDegrees)
            : 6
        self.minimumSkinFraction = minimumSkinFraction.isFinite
            ? min(max(minimumSkinFraction, 0), 1)
            : 0.01
    }
}

/// Tuning for ``StyleLearningEngine``.
///
/// The defaults are the values used by the acceptance tests. Most callers
/// should use ``standard``; the initializer exists so tests can shrink the
/// analysis proxy or tighten thresholds without changing production code.
public struct StyleLearningConfiguration: Sendable, Equatable {
    /// Longest edge of the private analysis proxy. Pairs are downsampled to at
    /// most this size before statistics are collected. `256` keeps a five-pair
    /// analysis well inside the 90 s budget while retaining enough skin texture
    /// to estimate smoothing.
    public var maximumAnalysisEdge: Int

    /// Per-parameter safety envelope.
    public var safety: StyleSafetyRanges

    /// Skin-tone protection limits.
    public var skinProtection: SkinProtectionConfiguration

    /// Hold-out error at or below which eight or more good pairs may be called
    /// ``ConfidenceLevel/stable``.
    public var stableHoldoutError: Double

    /// Hold-out error at or below which five or more good pairs may be called
    /// ``ConfidenceLevel/standard``.
    public var standardHoldoutError: Double

    /// Minimum accepted pair count for ``ConfidenceLevel/stable``.
    public var stablePairCount: Int

    /// Minimum accepted pair count for ``ConfidenceLevel/standard``.
    public var standardPairCount: Int

    /// Answer count at which AB influence reaches full strength. The product
    /// asks for 6–8 choices; fewer choices are deliberately weaker.
    public var fullInfluenceAnswerCount: Int

    /// Production defaults.
    public static let standard = StyleLearningConfiguration()

    public init(
        maximumAnalysisEdge: Int = 256,
        safety: StyleSafetyRanges = .standard,
        skinProtection: SkinProtectionConfiguration = .standard,
        stableHoldoutError: Double = 0.30,
        standardHoldoutError: Double = 0.50,
        stablePairCount: Int = 8,
        standardPairCount: Int = 5,
        fullInfluenceAnswerCount: Int = 6
    ) {
        self.maximumAnalysisEdge = min(max(maximumAnalysisEdge, 32), 512)
        self.safety = safety
        self.skinProtection = skinProtection

        let stable = Self.threshold(stableHoldoutError, fallback: 0.30)
        let standard = Self.threshold(standardHoldoutError, fallback: 0.50)
        self.stableHoldoutError = stable
        self.standardHoldoutError = max(stable, standard)

        let standardPairs = max(2, standardPairCount)
        self.standardPairCount = standardPairs
        self.stablePairCount = max(standardPairs, stablePairCount)
        self.fullInfluenceAnswerCount = min(max(fullInfluenceAnswerCount, 1), 24)
    }

    private static func threshold(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, 0), 1)
    }
}
