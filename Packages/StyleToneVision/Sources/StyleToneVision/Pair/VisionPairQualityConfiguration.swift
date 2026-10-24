import Foundation
import StyleToneCore

/// Localization keys for pair-quality reasons.
///
/// UI code resolves these with `String(localized:)`; the analyzer never emits
/// user-facing prose. A `good` pair has no reasons.
public enum PairQualityReason: String, Sendable, Codable, CaseIterable, Hashable {
    case resolutionReduced = "pair.reason.resolutionReduced"
    case resolutionTooLow = "pair.reason.resolutionTooLow"
    case aspectRatioChanged = "pair.reason.aspectRatioChanged"
    case aspectRatioMismatch = "pair.reason.aspectRatioMismatch"
    case misaligned = "pair.reason.misaligned"
    case notRegistered = "pair.reason.notRegistered"
    case semanticDrift = "pair.reason.semanticDrift"
    case semanticMismatch = "pair.reason.semanticMismatch"
    case structureChanged = "pair.reason.structureChanged"
    case structureMismatch = "pair.reason.structureMismatch"
    case analysisUnavailable = "pair.reason.analysisUnavailable"
}

/// Tuning knobs for ``VisionPairQualityAnalyzer``.
public struct VisionPairQualityConfiguration: Sendable, Equatable {
    /// Longest edge used for feature-print and structural comparison.
    public var maximumAnalysisDimension: Int

    /// Square resolution used by the translation-registration search.
    public var registrationDimension: Int

    /// Square resolution used by the structural comparison.
    public var structureDimension: Int

    /// Resolution ratio below which a pair is rejected.
    public var rejectedResolutionRatio: Double

    /// Resolution ratio below which a pair gets a warning.
    public var warningResolutionRatio: Double

    /// Aspect-ratio delta above which a pair is rejected.
    public var rejectedAspectRatioDelta: Double

    /// Aspect-ratio delta above which a pair gets a warning.
    public var warningAspectRatioDelta: Double

    /// Semantic similarity below which a pair is rejected.
    public var rejectedSimilarity: Float

    /// Semantic similarity below which a pair gets a warning.
    public var warningSimilarity: Float

    /// Normalized registration offset above which a pair is rejected.
    public var rejectedMisalignment: Double

    /// Normalized registration offset above which a pair gets a warning.
    public var warningMisalignment: Double

    /// Structural delta above which a pair is rejected.
    public var rejectedStructureDelta: Double

    /// Structural delta above which a pair gets a warning.
    public var warningStructureDelta: Double

    public init(
        maximumAnalysisDimension: Int = 512,
        registrationDimension: Int = 128,
        structureDimension: Int = 192,
        rejectedResolutionRatio: Double = 0.50,
        warningResolutionRatio: Double = 0.85,
        rejectedAspectRatioDelta: Double = 0.08,
        warningAspectRatioDelta: Double = 0.02,
        rejectedSimilarity: Float = 0.45,
        warningSimilarity: Float = 0.70,
        rejectedMisalignment: Double = 0.08,
        warningMisalignment: Double = 0.02,
        rejectedStructureDelta: Double = 0.45,
        warningStructureDelta: Double = 0.22
    ) {
        self.maximumAnalysisDimension = max(128, maximumAnalysisDimension)
        self.registrationDimension = max(64, registrationDimension)
        self.structureDimension = max(64, structureDimension)
        self.rejectedResolutionRatio = min(max(rejectedResolutionRatio, 0), 1)
        self.warningResolutionRatio = min(max(warningResolutionRatio, 0), 1)
        self.rejectedAspectRatioDelta = max(0, rejectedAspectRatioDelta)
        self.warningAspectRatioDelta = max(0, warningAspectRatioDelta)
        self.rejectedSimilarity = min(max(rejectedSimilarity, 0), 1)
        self.warningSimilarity = min(max(warningSimilarity, 0), 1)
        self.rejectedMisalignment = min(max(rejectedMisalignment, 0), 1)
        self.warningMisalignment = min(max(warningMisalignment, 0), 1)
        self.rejectedStructureDelta = min(max(rejectedStructureDelta, 0), 1)
        self.warningStructureDelta = min(max(warningStructureDelta, 0), 1)
    }
}

/// Numeric evidence behind one ``PairQuality`` decision.
///
/// Values are image-level measurements only; no landmarks, hashes of faces or
/// pixel payloads are retained.
public struct VisionPairQualityMetrics: Sendable, Equatable {
    public let originalSize: PixelSize
    public let editedSize: PixelSize
    public let resolutionRatio: Double
    public let aspectRatioDelta: Double
    public let semanticSimilarity: Float?
    public let registrationOffset: Double?
    public let registrationConfidence: Float?
    public let structureDelta: Double?
    public let usedFeaturePrint: Bool
    public let duration: TimeInterval

    public init(
        originalSize: PixelSize,
        editedSize: PixelSize,
        resolutionRatio: Double,
        aspectRatioDelta: Double,
        semanticSimilarity: Float?,
        registrationOffset: Double?,
        registrationConfidence: Float?,
        structureDelta: Double?,
        usedFeaturePrint: Bool,
        duration: TimeInterval
    ) {
        self.originalSize = originalSize
        self.editedSize = editedSize
        self.resolutionRatio = resolutionRatio
        self.aspectRatioDelta = aspectRatioDelta
        self.semanticSimilarity = semanticSimilarity
        self.registrationOffset = registrationOffset
        self.registrationConfidence = registrationConfidence
        self.structureDelta = structureDelta
        self.usedFeaturePrint = usedFeaturePrint
        self.duration = duration
    }
}

/// ``PairQuality`` plus the metrics used to produce it.
public struct VisionPairQualityResult: Sendable {
    public let quality: PairQuality
    public let metrics: VisionPairQualityMetrics

    public init(quality: PairQuality, metrics: VisionPairQualityMetrics) {
        self.quality = quality
        self.metrics = metrics
    }
}
