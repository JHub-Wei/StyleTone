import Foundation
import StyleToneCore

/// Calibration-owned localized copy and accessibility identifiers.
///
/// User-visible text is never hardcoded in a view. Every string has an English
/// development fallback until WP-26 ships the string catalog. Keys use the
/// frozen `calibration.` prefix.
public enum CalibrationCopy {
    // MARK: Pair stage

    public static let pairsTitle = LocalizationKey("calibration.pairs.title")
    public static let pairsSubtitle = LocalizationKey("calibration.pairs.subtitle")
    public static let pairsNote = LocalizationKey("calibration.pairs.note")
    public static let pairsCount = LocalizationKey("calibration.pairs.count")
    public static let pairsQuality = LocalizationKey("calibration.pairs.quality")
    public static let pairsTarget = LocalizationKey("calibration.pairs.target")
    public static let pairsInsufficient = LocalizationKey("calibration.pairs.insufficient")
    public static let pairsStart = LocalizationKey("calibration.pairs.start")
    public static let pairsAdd = LocalizationKey("calibration.pairs.add")
    public static let pairsSaveLater = LocalizationKey("calibration.pairs.saveLater")
    public static let pairsLocalOnly = LocalizationKey("calibration.pairs.localOnly")
    public static let pairsEmptyTitle = LocalizationKey("calibration.pairs.emptyTitle")
    public static let pairsEmptyMessage = LocalizationKey("calibration.pairs.emptyMessage")
    public static let pairsTierHint = LocalizationKey("calibration.pairs.tierHint")
    public static let pairsRecommended = LocalizationKey("calibration.pairs.recommended")
    public static let pairTierThree = LocalizationKey("calibration.pairTier.three")
    public static let pairTierFive = LocalizationKey("calibration.pairTier.five")
    public static let pairTierEight = LocalizationKey("calibration.pairTier.eight")
    public static let tierAvailable = LocalizationKey("calibration.tier.available")
    public static let tierLocked = LocalizationKey("calibration.tier.locked")

    // MARK: AB stage

    public static let abTitle = LocalizationKey("calibration.ab.title")
    public static let abSubtitle = LocalizationKey("calibration.ab.subtitle")
    public static let abProgress = LocalizationKey("calibration.ab.progress")
    public static let abReady = LocalizationKey("calibration.ab.ready")
    public static let abOptionA = LocalizationKey("calibration.ab.optionA")
    public static let abOptionB = LocalizationKey("calibration.ab.optionB")
    public static let abOptionHint = LocalizationKey("calibration.ab.optionHint")
    public static let abSkip = LocalizationKey("calibration.ab.skip")
    public static let abSkipHint = LocalizationKey("calibration.ab.skipHint")
    public static let abFinish = LocalizationKey("calibration.ab.finish")
    public static let abFinishHint = LocalizationKey("calibration.ab.finishHint")
    public static let abSkipAll = LocalizationKey("calibration.ab.skipAll")
    public static let abSkipAllHint = LocalizationKey("calibration.ab.skipAllHint")
    public static let abSaveLater = LocalizationKey("calibration.ab.saveLater")
    public static let abProgressLabel = LocalizationKey("calibration.ab.progressLabel")

    public static let dimensionTone = LocalizationKey("calibration.dimension.tone")
    public static let dimensionSkinTone = LocalizationKey("calibration.dimension.skinTone")
    public static let dimensionSmoothing = LocalizationKey("calibration.dimension.smoothing")
    public static let dimensionFaceSlim = LocalizationKey("calibration.dimension.faceSlim")
    public static let dimensionBodySlim = LocalizationKey("calibration.dimension.bodySlim")
    public static let dimensionLegLength = LocalizationKey("calibration.dimension.legLength")
    public static let dimensionNaturalness = LocalizationKey("calibration.dimension.naturalness")

    public static let detailToneLow = LocalizationKey("calibration.ab.detail.tone.low")
    public static let detailToneHigh = LocalizationKey("calibration.ab.detail.tone.high")
    public static let detailSkinToneLow = LocalizationKey("calibration.ab.detail.skinTone.low")
    public static let detailSkinToneHigh = LocalizationKey("calibration.ab.detail.skinTone.high")
    public static let detailSmoothingLow = LocalizationKey("calibration.ab.detail.smoothing.low")
    public static let detailSmoothingHigh = LocalizationKey("calibration.ab.detail.smoothing.high")
    public static let detailFaceSlimLow = LocalizationKey("calibration.ab.detail.faceSlim.low")
    public static let detailFaceSlimHigh = LocalizationKey("calibration.ab.detail.faceSlim.high")
    public static let detailBodySlimLow = LocalizationKey("calibration.ab.detail.bodySlim.low")
    public static let detailBodySlimHigh = LocalizationKey("calibration.ab.detail.bodySlim.high")
    public static let detailLegLengthLow = LocalizationKey("calibration.ab.detail.legLength.low")
    public static let detailLegLengthHigh = LocalizationKey("calibration.ab.detail.legLength.high")
    public static let detailNaturalnessLow = LocalizationKey("calibration.ab.detail.naturalness.low")
    public static let detailNaturalnessHigh = LocalizationKey("calibration.ab.detail.naturalness.high")

    // MARK: Learning

    public static let learningTitle = LocalizationKey("calibration.learning.title")
    public static let learningMessage = LocalizationKey("calibration.learning.message")
    public static let learningCancel = LocalizationKey("calibration.learning.cancel")

    // MARK: Result

    public static let resultTitle = LocalizationKey("calibration.result.title")
    public static let resultSubtitle = LocalizationKey("calibration.result.subtitle")
    public static let resultNaturalTitle = LocalizationKey("calibration.result.naturalTitle")
    public static let resultNaturalNote = LocalizationKey("calibration.result.naturalNote")
    public static let resultConfidence = LocalizationKey("calibration.result.confidence")
    public static let resultPairs = LocalizationKey("calibration.result.pairs")
    public static let resultChoices = LocalizationKey("calibration.result.choices")
    public static let resultPreviewBadge = LocalizationKey("calibration.result.previewBadge")
    public static let resultPreviewNote = LocalizationKey("calibration.result.previewNote")
    public static let resultUse = LocalizationKey("calibration.result.use")
    public static let resultOpenCard = LocalizationKey("calibration.result.openCard")
    public static let resultRecalibrate = LocalizationKey("calibration.result.recalibrate")
    public static let resultSaved = LocalizationKey("calibration.result.saved")
    public static let resultTagNatural = LocalizationKey("calibration.result.tag.natural")
    public static let resultTagWarm = LocalizationKey("calibration.result.tag.warm")
    public static let resultTagSoft = LocalizationKey("calibration.result.tag.soft")
    public static let resultTagDefined = LocalizationKey("calibration.result.tag.defined")
    public static let resultTagEditorial = LocalizationKey("calibration.result.tag.editorial")
    public static let confidenceTrial = LocalizationKey("calibration.result.confidence.trial")
    public static let confidenceStandard = LocalizationKey("calibration.result.confidence.standard")
    public static let confidenceStable = LocalizationKey("calibration.result.confidence.stable")

    // MARK: Failure / notices

    public static let errorTitle = LocalizationKey("calibration.error.title")
    public static let errorLearning = LocalizationKey("calibration.error.learning")
    public static let errorSaving = LocalizationKey("calibration.error.saving")
    public static let errorRestore = LocalizationKey("calibration.error.restore")
    public static let errorMissingPairs = LocalizationKey("calibration.error.missingPairs")
    public static let errorRetry = LocalizationKey("calibration.error.retry")
    public static let errorBack = LocalizationKey("calibration.error.back")
    public static let errorNatural = LocalizationKey("calibration.error.natural")
    public static let errorPairs = LocalizationKey("calibration.error.pairs")
    public static let errorPairsPreserved = LocalizationKey("calibration.error.pairsPreserved")

    public static let noticeRestored = LocalizationKey("calibration.notice.restored")
    public static let noticeCancelled = LocalizationKey("calibration.notice.cancelled")
    public static let noticeProgressUnavailable = LocalizationKey("calibration.notice.progressUnavailable")
    public static let noticeMissingPairs = LocalizationKey("calibration.notice.missingPairs")
    public static let noticeDismiss = LocalizationKey("calibration.notice.dismiss")

    // MARK: Shared actions

    public static let cancel = LocalizationKey("calibration.cancel")
    public static let naturalDefault = LocalizationKey("calibration.naturalDefault")
    public static let naturalDefaultNote = LocalizationKey("calibration.naturalDefaultNote")
    public static let progressLabel = LocalizationKey("calibration.progress")

    /// Maps a comparison dimension to its section heading.
    public static func dimensionKey(for dimension: CalibrationDimension) -> LocalizationKey {
        switch dimension {
        case .skinTone: return dimensionSkinTone
        case .smoothing: return dimensionSmoothing
        case .faceSlim: return dimensionFaceSlim
        case .bodySlim: return dimensionBodySlim
        case .legLength: return dimensionLegLength
        case .tone: return dimensionTone
        case .naturalness: return dimensionNaturalness
        }
    }

    /// Maps an AB option to a short, user-facing description.
    public static func detailKey(
        for dimension: CalibrationDimension,
        variant: CalibrationComparisonOption.Variant
    ) -> LocalizationKey {
        switch (dimension, variant) {
        case (.skinTone, .low): return detailSkinToneLow
        case (.skinTone, .high): return detailSkinToneHigh
        case (.smoothing, .low): return detailSmoothingLow
        case (.smoothing, .high): return detailSmoothingHigh
        case (.faceSlim, .low): return detailFaceSlimLow
        case (.faceSlim, .high): return detailFaceSlimHigh
        case (.bodySlim, .low): return detailBodySlimLow
        case (.bodySlim, .high): return detailBodySlimHigh
        case (.legLength, .low): return detailLegLengthLow
        case (.legLength, .high): return detailLegLengthHigh
        case (.tone, .low): return detailToneLow
        case (.tone, .high): return detailToneHigh
        case (.naturalness, .low): return detailNaturalnessLow
        case (.naturalness, .high): return detailNaturalnessHigh
        }
    }

    /// Accessibility label for one tier selector.
    public static func tierDescription(
        _ tier: CalibrationPairTier,
        availablePairs: Int
    ) -> String {
        let name = format(pairTierKey(for: tier), tier.pairCount)
        if availablePairs >= tier.pairCount {
            return format(tierAvailable, name)
        }
        return format(tierLocked, name, tier.pairCount)
    }

    public static func pairTierKey(for tier: CalibrationPairTier) -> LocalizationKey {
        switch tier {
        case .three: return pairTierThree
        case .five: return pairTierFive
        case .eight: return pairTierEight
        }
    }

    public static func confidenceKey(for confidence: ConfidenceLevel) -> LocalizationKey {
        switch confidence {
        case .trial: return confidenceTrial
        case .standard: return confidenceStandard
        case .stable: return confidenceStable
        }
    }

    /// Resolves a key to its fallback while the string catalog is absent.
    public static func text(_ key: LocalizationKey) -> String {
        let fallback = fallbacks[key] ?? key.rawValue
        return L10n.resolve(key, fallback: fallback)
    }

    /// Resolves and formats a key. Only integer and string positional
    /// arguments are used by calibration copy.
    public static func format(_ key: LocalizationKey, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    /// The fallback for a key; exposed so tests can audit every string.
    public static func fallback(for key: LocalizationKey) -> String? {
        fallbacks[key]
    }

    /// Every calibration key, sorted for deterministic tests.
    public static var allKeys: [LocalizationKey] {
        fallbacks.keys.sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: Fallbacks

    private static let fallbacks: [LocalizationKey: String] = [
        pairsTitle: "Start with your pairs",
        pairsSubtitle: "Three pairs are enough to begin. Add two for 5, or three more for 8. Three pairs usually take about 4 minutes.",
        pairsNote: "Only good and warning pairs tune your style. Rejected pairs and originals stay on this device.",
        pairsCount: "%d pairs ready",
        pairsQuality: "%d good, %d warning, %d rejected",
        pairsTarget: "Next milestone: %d pairs",
        pairsInsufficient: "Add at least 3 good or warning pairs to start.",
        pairsStart: "Start with %d pairs",
        pairsAdd: "Add more pairs",
        pairsSaveLater: "Save and finish later",
        pairsLocalOnly: "No account needed. Pairs and calibration stay on this device.",
        pairsEmptyTitle: "No pairs yet",
        pairsEmptyMessage: "Choose an original and the edited version you love. Three pairs is enough.",
        pairsTierHint: "Choose how many pairs to use. More pairs give a steadier style.",
        pairsRecommended: "Recommended",
        pairTierThree: "%d pairs",
        pairTierFive: "%d pairs",
        pairTierEight: "%d pairs",
        tierAvailable: "%@, available",
        tierLocked: "%@, needs %d pairs",

        abTitle: "Which look feels more like you?",
        abSubtitle: "Tap A or B. Every choice tunes the result. Six cards are enough, and you can skip any card.",
        abProgress: "%d of %d",
        abReady: "Six cards done. Finish now, or keep going for a steadier style.",
        abOptionA: "Option A",
        abOptionB: "Option B",
        abOptionHint: "Choose this look",
        abSkip: "Not sure, skip this one",
        abSkipHint: "No answer is recorded. Your progress stays saved.",
        abFinish: "Finish and build my style",
        abFinishHint: "Continue through %d more cards to finish",
        abSkipAll: "Skip AB and use natural default",
        abSkipAllHint: "Uses a clean natural style without AB choices.",
        abSaveLater: "Save and finish later",
        abProgressLabel: "AB progress",

        dimensionTone: "Light and tone",
        dimensionSkinTone: "Skin tone",
        dimensionSmoothing: "Skin texture",
        dimensionFaceSlim: "Face shape",
        dimensionBodySlim: "Body shape",
        dimensionLegLength: "Leg length",
        dimensionNaturalness: "Natural feel",

        detailToneLow: "Softer light",
        detailToneHigh: "Deeper contrast",
        detailSkinToneLow: "Neutral warmth",
        detailSkinToneHigh: "Warm glow",
        detailSmoothingLow: "Keep texture",
        detailSmoothingHigh: "Smoother skin",
        detailFaceSlimLow: "Natural jawline",
        detailFaceSlimHigh: "Sculpted jawline",
        detailBodySlimLow: "Natural silhouette",
        detailBodySlimHigh: "Defined silhouette",
        detailLegLengthLow: "Natural proportions",
        detailLegLengthHigh: "Longer lines",
        detailNaturalnessLow: "True to life",
        detailNaturalnessHigh: "Editorial finish",

        learningTitle: "Building your style",
        learningMessage: "Comparing your pairs and choices. Everything stays on this device.",
        learningCancel: "Cancel and keep my progress",

        resultTitle: "Your style is ready",
        resultSubtitle: "A personal look learned from %d pairs and %d choices.",
        resultNaturalTitle: "Natural default",
        resultNaturalNote: "AB was skipped. You can recalibrate any time.",
        resultConfidence: "Confidence",
        resultPairs: "%d pairs",
        resultChoices: "%d choices",
        resultPreviewBadge: "Preview placeholder",
        resultPreviewNote: "The style preview is a placeholder until rendering is wired.",
        resultUse: "Use this style",
        resultOpenCard: "Open style card",
        resultRecalibrate: "Recalibrate",
        resultSaved: "Saved on this device.",
        resultTagNatural: "Natural",
        resultTagWarm: "Warm",
        resultTagSoft: "Soft",
        resultTagDefined: "Defined",
        resultTagEditorial: "Editorial",
        confidenceTrial: "Trial",
        confidenceStandard: "Standard",
        confidenceStable: "Stable",

        errorTitle: "Something interrupted calibration",
        errorLearning: "Your pairs and choices are safe. Try again, go back, or use the natural default.",
        errorSaving: "Your style was built but could not be saved. Try again, or use the natural default.",
        errorRestore: "Saved progress could not be read. Your pairs are still here.",
        errorMissingPairs: "Some photos from the saved session are not available. Add them again or start over.",
        errorRetry: "Try again",
        errorBack: "Back to comparisons",
        errorNatural: "Use natural default",
        errorPairs: "Back to pairs",
        errorPairsPreserved: "Your selected pairs are still here.",

        noticeRestored: "Picked up where you left off.",
        noticeCancelled: "Learning cancelled. Your answers are saved.",
        noticeProgressUnavailable: "Progress could not be saved. You can still continue.",
        noticeMissingPairs: "Some pairs from your saved session are missing.",
        noticeDismiss: "Dismiss",

        cancel: "Save and finish later",
        naturalDefault: "Use natural default",
        naturalDefaultNote: "Start with a clean, natural look and calibrate later.",
        progressLabel: "Progress",
    ]
}

public extension AccessibilityID {
    static let calibrationRoot = AccessibilityID(.calibration, "root")
    static let calibrationProgress = AccessibilityID(.calibration, "progress")
    static let calibrationPairCount = AccessibilityID(.calibration, "pairCount")
    static let calibrationQualitySummary = AccessibilityID(.calibration, "qualitySummary")
    static let calibrationTierThree = AccessibilityID(.calibration, "tier.three")
    static let calibrationTierFive = AccessibilityID(.calibration, "tier.five")
    static let calibrationTierEight = AccessibilityID(.calibration, "tier.eight")
    static let calibrationPairEmpty = AccessibilityID(.calibration, "pairEmpty")
    static let calibrationABProgress = AccessibilityID(.calibration, "abProgress")
    static let calibrationABPrompt = AccessibilityID(.calibration, "abPrompt")
    static let calibrationABOptionAButton = AccessibilityID(.calibration, "ab.optionAButton")
    static let calibrationABOptionBButton = AccessibilityID(.calibration, "ab.optionBButton")
    static let calibrationABSkipButton = AccessibilityID(.calibration, "ab.skipButton")
    static let calibrationABFinishButton = AccessibilityID(.calibration, "ab.finishButton")
    static let calibrationABNaturalButton = AccessibilityID(.calibration, "ab.naturalButton")
    static let calibrationABSaveLaterButton = AccessibilityID(.calibration, "ab.saveLaterButton")
    static let calibrationNaturalButton = AccessibilityID(.calibration, "naturalButton")
    static let calibrationPauseButton = AccessibilityID(.calibration, "pauseButton")
    static let calibrationCancelWorkButton = AccessibilityID(.calibration, "cancelWorkButton")
    static let calibrationLoading = AccessibilityID(.calibration, "loading")
    static let calibrationErrorRetryButton = AccessibilityID(.calibration, "error.retryButton")
    static let calibrationErrorBackButton = AccessibilityID(.calibration, "error.backButton")
    static let calibrationErrorNaturalButton = AccessibilityID(.calibration, "error.naturalButton")
    static let calibrationErrorPairsButton = AccessibilityID(.calibration, "error.pairsButton")
    static let calibrationNotice = AccessibilityID(.calibration, "notice")
    static let calibrationNoAccountNote = AccessibilityID(.calibration, "noAccountNote")
    static let calibrationUseStyleButton = AccessibilityID(.calibration, "useStyleButton")
    static let calibrationResultSummary = AccessibilityID(.calibration, "resultSummary")
    static let calibrationResultConfidence = AccessibilityID(.calibration, "resultConfidence")

    /// Calibration identifiers introduced by WP-10, including the four frozen
    /// identifiers from the design system.
    static let calibrationAll: [AccessibilityID] = [
        calibrationRoot,
        calibrationStartButton,
        calibrationAddPairsButton,
        calibrationStyleCardButton,
        calibrationRecalibrateButton,
        calibrationProgress,
        calibrationPairCount,
        calibrationQualitySummary,
        calibrationTierThree,
        calibrationTierFive,
        calibrationTierEight,
        calibrationPairEmpty,
        calibrationABProgress,
        calibrationABPrompt,
        calibrationABOptionAButton,
        calibrationABOptionBButton,
        calibrationABSkipButton,
        calibrationABFinishButton,
        calibrationABNaturalButton,
        calibrationABSaveLaterButton,
        calibrationNaturalButton,
        calibrationPauseButton,
        calibrationCancelWorkButton,
        calibrationLoading,
        calibrationErrorRetryButton,
        calibrationErrorBackButton,
        calibrationErrorNaturalButton,
        calibrationErrorPairsButton,
        calibrationNotice,
        calibrationNoAccountNote,
        calibrationUseStyleButton,
        calibrationResultSummary,
        calibrationResultConfidence,
    ]
}
