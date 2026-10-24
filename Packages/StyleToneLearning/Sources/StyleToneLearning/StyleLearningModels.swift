import Foundation
import StyleToneCore

/// Identifies the learner and the profile schema it emits.
public enum StyleLearningAlgorithm {
    /// Version written into `StyleProfile.algorithmVersion`.
    public static let version = StyleProfile.currentAlgorithmVersion
    /// Schema written into `StyleProfile.schemaVersion`.
    public static let schemaVersion = StyleProfile.currentSchemaVersion
}

/// Optional non-visual strength measurements supplied by the caller.
///
/// The learning module deliberately does not detect faces or bodies. When the
/// integration layer already has landmark or contour displacements (for example
/// from WP-05 analysis or a preview renderer), it can pass the normalised
/// strengths here. The learner aggregates them with the same robust estimator
/// and safety clamps as its own texture measurements.
///
/// Values are normalised strengths, not pixel distances:
/// - unit strengths are in `0...1` (`smoothing`, `faceSlim`, …);
/// - `legLength` is a multiplier where `1.0` means unchanged.
///
/// Out-of-range values are clamped, not rejected.
public struct PairStrengthSignals: Sendable, Equatable {
    /// Learned skin smoothing.
    public var smoothing: Double?
    /// Learned skin evenness.
    public var evenness: Double?
    /// Learned blemish strength.
    public var blemish: Double?
    /// Learned face slim strength.
    public var faceSlim: Double?
    /// Learned jaw strength.
    public var jaw: Double?
    /// Learned arm slim strength.
    public var arm: Double?
    /// Learned waist slim strength.
    public var waist: Double?
    /// Learned leg slim strength.
    public var leg: Double?
    /// Learned leg-length multiplier (normally `1.0...1.15`).
    public var legLength: Double?
    /// Learned grain strength.
    public var grain: Double?
    /// Learned vignette strength (negative darkens corners).
    public var vignette: Double?

    public init(
        smoothing: Double? = nil,
        evenness: Double? = nil,
        blemish: Double? = nil,
        faceSlim: Double? = nil,
        jaw: Double? = nil,
        arm: Double? = nil,
        waist: Double? = nil,
        leg: Double? = nil,
        legLength: Double? = nil,
        grain: Double? = nil,
        vignette: Double? = nil
    ) {
        self.smoothing = smoothing
        self.evenness = evenness
        self.blemish = blemish
        self.faceSlim = faceSlim
        self.jaw = jaw
        self.arm = arm
        self.waist = waist
        self.leg = leg
        self.legLength = legLength
        self.grain = grain
        self.vignette = vignette
    }
}

/// A learning request with optional per-pair strength signals.
///
/// `StyleLearning.learn(samples:answers:)` is the frozen protocol entry point;
/// this richer request lets an integration pass measurements without changing
/// the protocol.
public struct StyleLearningRequest: Sendable {
    /// Original/edited pairs in user-selected order.
    public var samples: [PairSample]
    /// AB answers. `strengthDelta` is the signed preference for *more* (+)
    /// or *less* (−) strength; `choseA` is preserved for analytics but is not
    /// used to infer direction because the UI is free to place either option on
    /// the left.
    public var answers: [CalibrationAnswer]
    /// Optional strength measurements keyed by `PairSample.id`.
    public var strengthSignals: [UUID: PairStrengthSignals]

    public init(
        samples: [PairSample],
        answers: [CalibrationAnswer] = [],
        strengthSignals: [UUID: PairStrengthSignals] = [:]
    ) {
        self.samples = samples
        self.answers = answers
        self.strengthSignals = strengthSignals
    }
}

/// Non-fatal conditions observed while learning.
public enum StyleLearningIssue: String, Sendable, Codable, Hashable, CaseIterable {
    /// No pair survived quality filtering or image decoding.
    case noValidPairs
    /// The pair was marked `rejected` by quality analysis.
    case rejectedPair
    /// The image could not be decoded into the analysis proxy.
    case unreadablePair
    /// The pair was graded `warning`; it was used with a lower weight.
    case lowQualityPair
    /// The proxy had too few pixels for a stable texture estimate.
    case lowResolutionPair
    /// Original and edited aspect ratios differ noticeably.
    case mismatchedPair
    /// Too few skin pixels for a reliable skin/texture measurement.
    case insufficientSkin
    /// Too few near-neutral pixels for a reliable white-balance measurement.
    case insufficientNeutral
    /// Fewer than three pairs were available, so leave-one-out validation was
    /// not meaningful.
    case holdoutUnavailable
    /// Leave-one-out error exceeded the standard-confidence threshold.
    case highHoldoutError
    /// At least one pair was down-weighted as an outlier.
    case outlierPair
    /// The request only contained AB answers.
    case abOnly
    /// The skin guard scaled back at least one learned parameter.
    case skinToneGuarded
    /// The safety envelope changed at least one aggregated parameter.
    case safetyClamped
}

/// Explainability data for a learned profile. Never persisted.
public struct StyleLearningDiagnostics: Sendable, Equatable {
    /// Pairs that contributed to the fit (good or warning).
    public let acceptedPairCount: Int
    /// Pairs rejected by quality analysis.
    public let rejectedPairCount: Int
    /// Pairs that could not be decoded or produced no usable estimate.
    public let skippedPairCount: Int
    /// Number of AB answers supplied.
    public let answeredCount: Int
    /// Leave-one-out consistency error, `0...1`.
    public let holdoutError: Double
    /// Mean quality weight of accepted pairs, `0...1`.
    public let meanQuality: Double
    /// Aggregation shrink factor toward neutral, `0...1`.
    public let shrinkage: Double
    /// Mean skin fraction of accepted pairs.
    public let skinFraction: Double
    /// True when the skin guard limited at least one parameter.
    public let skinProtectionApplied: Bool
    /// Sorted, de-duplicated issues.
    public let issues: [StyleLearningIssue]

    public init(
        acceptedPairCount: Int,
        rejectedPairCount: Int,
        skippedPairCount: Int,
        answeredCount: Int,
        holdoutError: Double,
        meanQuality: Double,
        shrinkage: Double,
        skinFraction: Double,
        skinProtectionApplied: Bool,
        issues: [StyleLearningIssue]
    ) {
        self.acceptedPairCount = max(0, acceptedPairCount)
        self.rejectedPairCount = max(0, rejectedPairCount)
        self.skippedPairCount = max(0, skippedPairCount)
        self.answeredCount = max(0, answeredCount)
        self.holdoutError = LearningMath.unit(holdoutError)
        self.meanQuality = LearningMath.unit(meanQuality)
        self.shrinkage = LearningMath.unit(shrinkage)
        self.skinFraction = LearningMath.unit(skinFraction)
        self.skinProtectionApplied = skinProtectionApplied
        self.issues = Array(Set(issues)).sorted { $0.rawValue < $1.rawValue }
    }
}

/// The learned profile plus diagnostics that the calibration UI may surface in
/// debug builds.
public struct StyleLearningResult: Sendable {
    /// Profile ready for preview and persistence.
    public let profile: StyleProfile
    /// Fit diagnostics; not persisted and safe to discard.
    public let diagnostics: StyleLearningDiagnostics

    public init(profile: StyleProfile, diagnostics: StyleLearningDiagnostics) {
        self.profile = profile
        self.diagnostics = diagnostics
    }
}
