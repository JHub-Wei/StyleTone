import Foundation

/// A localization key plus the English development fallback.
///
/// Until the `zh-Hans` string catalog lands (WP-26), `text` resolves through
/// `L10n` and falls back to the development string. Feature code never
/// hardcodes Chinese and never constructs user-facing copy inline.
public struct PairingText: Sendable, Hashable {
    public let key: LocalizationKey
    public let fallback: String

    public init(_ key: String, fallback: String) {
        self.key = LocalizationKey(key)
        self.fallback = fallback
    }

    /// The string to display.
    public var text: String {
        L10n.resolve(key, fallback: fallback)
    }
}

// MARK: - Quality reason keys

/// Localization keys the pair-quality analyzer emits.
///
/// WP-05 owns the analyzer and emits `pair.reason.*` keys
/// (`Contracts` §3.5 stores localization keys, not prose). The frozen UI
/// prefix list has no `pair` prefix, so the pairing UI maps every known analyzer
/// key onto its own `pairing.reason.*` key and falls back to a humanized label
/// for unknown ones. See `Packages/StyleToneUI/Pairing/README.md`.
public enum PairingQualityReasonKeys {
    public static let resolutionReduced = "pair.reason.resolutionReduced"
    public static let resolutionTooLow = "pair.reason.resolutionTooLow"
    public static let aspectRatioChanged = "pair.reason.aspectRatioChanged"
    public static let aspectRatioMismatch = "pair.reason.aspectRatioMismatch"
    public static let misaligned = "pair.reason.misaligned"
    public static let notRegistered = "pair.reason.notRegistered"
    public static let semanticDrift = "pair.reason.semanticDrift"
    public static let semanticMismatch = "pair.reason.semanticMismatch"
    public static let structureChanged = "pair.reason.structureChanged"
    public static let structureMismatch = "pair.reason.structureMismatch"
    public static let analysisUnavailable = "pair.reason.analysisUnavailable"

    /// Reason the pairing UI adds itself when both slots are the same photo.
    public static let samePhoto = "pairing.reason.samePhoto"

    /// Analyzer keys this build knows how to phrase.
    public static let analyzerKeys: [String] = [
        resolutionReduced,
        resolutionTooLow,
        aspectRatioChanged,
        aspectRatioMismatch,
        misaligned,
        notRegistered,
        semanticDrift,
        semanticMismatch,
        structureChanged,
        structureMismatch,
        analysisUnavailable,
    ]
}

// MARK: - Copy catalog

/// All copy owned by the pairing screen.
public enum PairingCopy {
    // MARK: Screen

    public static let title = PairingText("pairing.title", fallback: "Pairing")
    public static let subtitle = PairingText(
        "pairing.subtitle",
        fallback: "Show a before and after of edits you already love. StyleTone learns on this device."
    )
    public static let note = PairingText(
        "pairing.note",
        fallback: "No account, no upload. Pairs only teach the app on this iPhone."
    )
    public static let addPairButton = PairingText("pairing.addPairButton", fallback: "Add pair")
    public static let continueButton = PairingText("pairing.continueButton", fallback: "Continue")
    public static let skipButton = PairingText("pairing.skipButton", fallback: "Skip for now")
    public static let importHint = PairingText(
        "pairing.import.hint",
        fallback: "In the picker, choose the original first and the edited photo second."
    )
    public static let loading = PairingText(
        "pairing.loading",
        fallback: "Restoring your pairs…"
    )

    // MARK: Progress

    public static let progressCaption = PairingText(
        "pairing.progress.caption",
        fallback: "Usable pairs"
    )
    public static let progressAccessibilityLabel = PairingText(
        "pairing.progress.accessibilityLabel",
        fallback: "Pairing progress"
    )
    public static let targetLabel = PairingText("pairing.target.label", fallback: "Target")
    public static let targetThree = PairingText("pairing.target.three", fallback: "3 pairs")
    public static let targetFive = PairingText("pairing.target.five", fallback: "5 pairs")
    public static let targetEight = PairingText("pairing.target.eight", fallback: "8 pairs")
    public static let countGood = PairingText("pairing.count.good", fallback: "Good")
    public static let countWarning = PairingText("pairing.count.warning", fallback: "Caution")
    public static let countRejected = PairingText("pairing.count.rejected", fallback: "Not usable")
    public static let countGoodAccessibility = PairingText(
        "pairing.count.good.accessibility",
        fallback: "Good pairs"
    )
    public static let countWarningAccessibility = PairingText(
        "pairing.count.warning.accessibility",
        fallback: "Pairs with a caution"
    )
    public static let countRejectedAccessibility = PairingText(
        "pairing.count.rejected.accessibility",
        fallback: "Pairs not usable for learning"
    )

    // MARK: Empty state

    public static let emptyTitle = PairingText("pairing.empty.title", fallback: "No pairs yet")
    public static let emptyMessage = PairingText(
        "pairing.empty.message",
        fallback: "Pick a photo you edited and the original it started from. Three usable pairs are enough to begin."
    )
    public static let emptyAction = PairingText(
        "pairing.empty.action",
        fallback: "Add your first pair"
    )
    public static let emptyHint = PairingText(
        "pairing.empty.hint",
        fallback: "Original first, edited second."
    )

    // MARK: Slots

    public static let originalTitle = PairingText("pairing.slot.original", fallback: "Original")
    public static let editedTitle = PairingText("pairing.slot.edited", fallback: "Edited")
    public static let chooseSlot = PairingText("pairing.slot.choose", fallback: "Choose")
    public static let chooseOriginal = PairingText(
        "pairing.slot.chooseOriginal",
        fallback: "Choose original"
    )
    public static let chooseEdited = PairingText(
        "pairing.slot.chooseEdited",
        fallback: "Choose edited"
    )
    public static let replaceSlot = PairingText("pairing.slot.replace", fallback: "Replace")
    public static let replaceOriginal = PairingText(
        "pairing.slot.replaceOriginal",
        fallback: "Replace original"
    )
    public static let replaceEdited = PairingText(
        "pairing.slot.replaceEdited",
        fallback: "Replace edited"
    )
    public static let removeSlot = PairingText("pairing.slot.remove", fallback: "Remove")
    public static let removeOriginal = PairingText(
        "pairing.slot.removeOriginal",
        fallback: "Remove original"
    )
    public static let removeEdited = PairingText(
        "pairing.slot.removeEdited",
        fallback: "Remove edited"
    )
    public static let slotEmptyHint = PairingText(
        "pairing.slot.emptyHint",
        fallback: "No photo yet"
    )
    public static let slotStaleTitle = PairingText(
        "pairing.slot.staleTitle",
        fallback: "Choose again"
    )
    public static let slotStaleMessage = PairingText(
        "pairing.slot.staleMessage",
        fallback: "The photo was released when the app closed. Pick it again to keep this pair."
    )
    public static let slotImporting = PairingText(
        "pairing.slot.importing",
        fallback: "Loading photo…"
    )

    // MARK: Pairs

    public static let pairLabel = PairingText("pairing.pair.label", fallback: "Pair")
    public static let deletePair = PairingText("pairing.pair.delete", fallback: "Delete pair")

    // MARK: Quality

    public static let qualityWaiting = PairingText(
        "pairing.quality.waiting",
        fallback: "Choose both photos"
    )
    public static let qualityChecking = PairingText(
        "pairing.quality.checking",
        fallback: "Checking this pair…"
    )
    public static let qualityGood = PairingText("pairing.quality.good", fallback: "Good pair")
    public static let qualityWarning = PairingText(
        "pairing.quality.warning",
        fallback: "Usable with a caution"
    )
    public static let qualityRejected = PairingText(
        "pairing.quality.rejected",
        fallback: "Not usable"
    )
    public static let qualityGoodHint = PairingText(
        "pairing.quality.goodHint",
        fallback: "The original and the edit line up well."
    )
    public static let qualityWarningHint = PairingText(
        "pairing.quality.warningHint",
        fallback: "The app can learn from this pair, but the photos differ more than usual."
    )
    public static let qualityRejectedHint = PairingText(
        "pairing.quality.rejectedHint",
        fallback: "This pair will not be used for learning."
    )
    public static let qualityFailed = PairingText(
        "pairing.quality.failed",
        fallback: "Quality check failed"
    )
    public static let qualityRetry = PairingText("pairing.quality.retry", fallback: "Check again")
    public static let qualityFailureAnalyzerUnavailable = PairingText(
        "pairing.quality.failure.analyzerUnavailable",
        fallback: "Quality checks are not available in this build."
    )
    public static let qualityFailureAnalysisFailed = PairingText(
        "pairing.quality.failure.analysisFailed",
        fallback: "The check could not finish."
    )
    public static let qualityFailureCancelled = PairingText(
        "pairing.quality.failure.cancelled",
        fallback: "The check was interrupted."
    )
    public static let qualityFailureUnknown = PairingText(
        "pairing.quality.failure.unknown",
        fallback: "Something went wrong during the check."
    )
    public static let qualityShortWaiting = PairingText(
        "pairing.quality.short.waiting",
        fallback: "Incomplete"
    )
    public static let qualityShortChecking = PairingText(
        "pairing.quality.short.checking",
        fallback: "Checking"
    )
    public static let qualityShortGood = PairingText(
        "pairing.quality.short.good",
        fallback: "Good"
    )
    public static let qualityShortWarning = PairingText(
        "pairing.quality.short.warning",
        fallback: "Caution"
    )
    public static let qualityShortRejected = PairingText(
        "pairing.quality.short.rejected",
        fallback: "Not usable"
    )
    public static let qualityShortFailed = PairingText(
        "pairing.quality.short.failed",
        fallback: "Failed"
    )

    // MARK: Reasons

    public static let reasonSamePhoto = PairingText(
        "pairing.reason.samePhoto",
        fallback: "Both slots use the same photo."
    )
    public static let reasonResolutionReduced = PairingText(
        "pairing.reason.resolutionReduced",
        fallback: "The edited photo is lower resolution than the original."
    )
    public static let reasonResolutionTooLow = PairingText(
        "pairing.reason.resolutionTooLow",
        fallback: "The edited photo is much smaller than the original."
    )
    public static let reasonAspectRatioChanged = PairingText(
        "pairing.reason.aspectRatioChanged",
        fallback: "The edited photo was cropped to a different shape."
    )
    public static let reasonAspectRatioMismatch = PairingText(
        "pairing.reason.aspectRatioMismatch",
        fallback: "The two photos have very different aspect ratios."
    )
    public static let reasonMisaligned = PairingText(
        "pairing.reason.misaligned",
        fallback: "The edited photo is slightly shifted or reframed."
    )
    public static let reasonNotRegistered = PairingText(
        "pairing.reason.notRegistered",
        fallback: "The edited photo is shifted too far to compare."
    )
    public static let reasonSemanticDrift = PairingText(
        "pairing.reason.semanticDrift",
        fallback: "The photos may show slightly different scenes."
    )
    public static let reasonSemanticMismatch = PairingText(
        "pairing.reason.semanticMismatch",
        fallback: "The photos do not look like the same scene."
    )
    public static let reasonStructureChanged = PairingText(
        "pairing.reason.structureChanged",
        fallback: "The edit changed more than tone and skin."
    )
    public static let reasonStructureMismatch = PairingText(
        "pairing.reason.structureMismatch",
        fallback: "The edit changed the scene too much to learn from."
    )
    public static let reasonAnalysisUnavailable = PairingText(
        "pairing.reason.analysisUnavailable",
        fallback: "The app could not compare the photos in detail."
    )
    public static let reasonUnknown = PairingText(
        "pairing.reason.unknown",
        fallback: "This pair needs a closer look."
    )

    // MARK: Picker and privacy

    public static let pickerNote = PairingText(
        "pairing.permission.note",
        fallback: "The picker runs in a separate system process. StyleTone never gets access to your whole library."
    )
    public static let pickerUnavailableTitle = PairingText(
        "pairing.permission.unavailable.title",
        fallback: "Photo picker unavailable"
    )
    public static let pickerUnavailableMessage = PairingText(
        "pairing.permission.unavailable.message",
        fallback: "The system photo picker cannot open right now. Check device restrictions and try again."
    )
    public static let pickerRetry = PairingText(
        "pairing.permission.unavailable.retry",
        fallback: "Try again"
    )

    // MARK: Saving

    public static let saveIdle = PairingText(
        "pairing.save.idle",
        fallback: "Pairs are kept on this device."
    )
    public static let saveSaving = PairingText("pairing.save.saving", fallback: "Saving…")
    public static let saveSaved = PairingText("pairing.save.saved", fallback: "Saved")
    public static let saveFailed = PairingText(
        "pairing.save.failed",
        fallback: "Couldn't save pairs"
    )
    public static let saveRetry = PairingText("pairing.save.retry", fallback: "Try saving again")

    // MARK: Undo

    public static let undoPair = PairingText("pairing.undo.pair", fallback: "Pair deleted")
    public static let undoPhoto = PairingText("pairing.undo.photo", fallback: "Photo removed")
    public static let undoAction = PairingText("pairing.undo.action", fallback: "Undo")

    // MARK: Notices and limits

    public static let restoredNotice = PairingText(
        "pairing.notice.restored",
        fallback: "Your last pairing session was restored."
    )
    public static let staleNotice = PairingText(
        "pairing.notice.stale",
        fallback: "Photos are released when the app closes. Choose them again to reuse their pairs."
    )
    public static let completedNotice = PairingText(
        "pairing.notice.completed",
        fallback: "These pairs are saved."
    )
    public static let keepEditing = PairingText(
        "pairing.notice.keepEditing",
        fallback: "Keep editing"
    )
    public static let limitReached = PairingText(
        "pairing.notice.limitReached",
        fallback: "A session holds up to 12 pairs."
    )
    public static let continueHint = PairingText(
        "pairing.continue.hint",
        fallback: "Add at least 3 usable pairs to continue."
    )
    public static let continueReady = PairingText(
        "pairing.continue.ready",
        fallback: "Usable pairs are ready for calibration."
    )
    public static let dismissNotice = PairingText(
        "pairing.notice.dismiss",
        fallback: "Dismiss"
    )

    // MARK: Import errors

    public static let importFailedTitle = PairingText(
        "error.pairing.import.title",
        fallback: "Couldn't open that photo"
    )
    public static let importFailedMessage = PairingText(
        "error.pairing.import.message",
        fallback: "Choose a different HEIC, JPEG or PNG photo."
    )
    public static let importTooSmallTitle = PairingText(
        "error.pairing.tooSmall.title",
        fallback: "Photo is too small"
    )
    public static let importTooSmallMessage = PairingText(
        "error.pairing.tooSmall.message",
        fallback: "Use a photo that is at least 512 pixels on the long edge."
    )
    public static let importUnsupportedTitle = PairingText(
        "error.pairing.unsupported.title",
        fallback: "Unsupported photo format"
    )
    public static let importUnsupportedMessage = PairingText(
        "error.pairing.unsupported.message",
        fallback: "Choose a HEIC, JPEG or PNG photo."
    )
    public static let importNoDataTitle = PairingText(
        "error.pairing.noData.title",
        fallback: "No photo data"
    )
    public static let importNoDataMessage = PairingText(
        "error.pairing.noData.message",
        fallback: "The picker returned an empty photo. Try again."
    )

    // MARK: Session errors

    public static let sessionCorruptedTitle = PairingText(
        "error.pairing.session.corrupted.title",
        fallback: "Saved pairs couldn't be read"
    )
    public static let sessionCorruptedMessage = PairingText(
        "error.pairing.session.corrupted.message",
        fallback: "The saved session is damaged. Start a new session; the old file is left untouched."
    )
    public static let sessionSchemaTitle = PairingText(
        "error.pairing.session.schema.title",
        fallback: "Saved pairs need a newer version"
    )
    public static let sessionSchemaMessage = PairingText(
        "error.pairing.session.schema.message",
        fallback: "This build cannot read the saved session. Start a new session to continue."
    )
    public static let sessionLoadTitle = PairingText(
        "error.pairing.session.load.title",
        fallback: "Couldn't restore pairs"
    )
    public static let sessionLoadMessage = PairingText(
        "error.pairing.session.load.message",
        fallback: "Try loading the saved session again."
    )
    public static let sessionSaveTitle = PairingText(
        "error.pairing.session.save.title",
        fallback: "Couldn't save pairs"
    )
    public static let sessionSaveMessage = PairingText(
        "error.pairing.session.save.message",
        fallback: "The pairs are still here. Try saving again."
    )
    public static let sessionStartFresh = PairingText(
        "error.pairing.session.startFresh",
        fallback: "Start new session"
    )
    public static let retry = PairingText("pairing.action.retry", fallback: "Try again")
    public static let cancel = PairingText("pairing.action.cancel", fallback: "Cancel")
    /// Key used when the analyzer emits a reason this build does not know.
    public static let dynamicReason = PairingText(
        "pairing.reason.dynamic",
        fallback: "This pair needs a closer look."
    )

    // MARK: - Helpers

    /// Title for one slot.
    public static func slotTitle(_ slot: PairingSlot) -> PairingText {
        switch slot {
        case .original: return originalTitle
        case .edited: return editedTitle
        }
    }

    /// "Choose original" / "Choose edited".
    public static func chooseTitle(_ slot: PairingSlot) -> PairingText {
        switch slot {
        case .original: return chooseOriginal
        case .edited: return chooseEdited
        }
    }

    /// "Replace original" / "Replace edited".
    public static func replaceTitle(_ slot: PairingSlot) -> PairingText {
        switch slot {
        case .original: return replaceOriginal
        case .edited: return replaceEdited
        }
    }

    /// "Remove original" / "Remove edited".
    public static func removeTitle(_ slot: PairingSlot) -> PairingText {
        switch slot {
        case .original: return removeOriginal
        case .edited: return removeEdited
        }
    }

    /// "3 pairs" / "5 pairs" / "8 pairs".
    public static func targetTitle(_ target: PairingTarget) -> PairingText {
        switch target {
        case .three: return targetThree
        case .five: return targetFive
        case .eight: return targetEight
        }
    }

    /// Resolves one analyzer reason key into readable copy.
    ///
    /// Known WP-05 keys are mapped onto `pairing.reason.*`; an unknown key is
    /// humanized from its last segment so a new analyzer reason still reads as
    /// a sentence instead of a raw key.
    public static func reasonText(for rawValue: String) -> PairingText {
        reasonTable[rawValue] ?? PairingText(
            dynamicReason.key.rawValue,
            fallback: humanizeReason(rawValue)
        )
    }

    /// Resolved reason sentences, de-duplicated in the order the analyzer sent
    /// them.
    public static func reasonTexts(for reasons: [String]) -> [String] {
        var seen = Set<String>()
        var texts: [String] = []
        for reason in reasons {
            let text = reasonText(for: reason).text
            guard seen.insert(text).inserted else { continue }
            texts.append(text)
        }
        return texts
    }

    /// Every text this screen defines, for catalog and key tests.
    public static let all: [PairingText] = [
        title, subtitle, note, addPairButton, continueButton, skipButton, importHint, loading,
        progressCaption, progressAccessibilityLabel, targetLabel, targetThree, targetFive,
        targetEight, countGood, countWarning, countRejected, countGoodAccessibility,
        countWarningAccessibility, countRejectedAccessibility,
        emptyTitle, emptyMessage, emptyAction, emptyHint,
        originalTitle, editedTitle, chooseSlot, chooseOriginal, chooseEdited, replaceSlot,
        replaceOriginal, replaceEdited, removeSlot, removeOriginal, removeEdited,
        slotEmptyHint, slotStaleTitle, slotStaleMessage, slotImporting,
        pairLabel, deletePair,
        qualityWaiting, qualityChecking, qualityGood, qualityWarning, qualityRejected,
        qualityGoodHint, qualityWarningHint, qualityRejectedHint, qualityFailed, qualityRetry,
        qualityFailureAnalyzerUnavailable, qualityFailureAnalysisFailed,
        qualityFailureCancelled, qualityFailureUnknown,
        qualityShortWaiting, qualityShortChecking, qualityShortGood, qualityShortWarning,
        qualityShortRejected, qualityShortFailed,
        reasonSamePhoto, reasonResolutionReduced, reasonResolutionTooLow, reasonAspectRatioChanged,
        reasonAspectRatioMismatch, reasonMisaligned, reasonNotRegistered, reasonSemanticDrift,
        reasonSemanticMismatch, reasonStructureChanged, reasonStructureMismatch,
        reasonAnalysisUnavailable, reasonUnknown, dynamicReason,
        pickerNote, pickerUnavailableTitle, pickerUnavailableMessage, pickerRetry,
        saveIdle, saveSaving, saveSaved, saveFailed, saveRetry,
        undoPair, undoPhoto, undoAction,
        restoredNotice, staleNotice, completedNotice, keepEditing, limitReached,
        continueHint, continueReady, dismissNotice,
        importFailedTitle, importFailedMessage, importTooSmallTitle, importTooSmallMessage,
        importUnsupportedTitle, importUnsupportedMessage, importNoDataTitle, importNoDataMessage,
        sessionCorruptedTitle, sessionCorruptedMessage, sessionSchemaTitle, sessionSchemaMessage,
        sessionLoadTitle, sessionLoadMessage, sessionSaveTitle, sessionSaveMessage,
        sessionStartFresh, retry, cancel,
    ]

    // MARK: - Private

    private static let reasonTable: [String: PairingText] = [
        PairingQualityReasonKeys.resolutionReduced: reasonResolutionReduced,
        PairingQualityReasonKeys.resolutionTooLow: reasonResolutionTooLow,
        PairingQualityReasonKeys.aspectRatioChanged: reasonAspectRatioChanged,
        PairingQualityReasonKeys.aspectRatioMismatch: reasonAspectRatioMismatch,
        PairingQualityReasonKeys.misaligned: reasonMisaligned,
        PairingQualityReasonKeys.notRegistered: reasonNotRegistered,
        PairingQualityReasonKeys.semanticDrift: reasonSemanticDrift,
        PairingQualityReasonKeys.semanticMismatch: reasonSemanticMismatch,
        PairingQualityReasonKeys.structureChanged: reasonStructureChanged,
        PairingQualityReasonKeys.structureMismatch: reasonStructureMismatch,
        PairingQualityReasonKeys.analysisUnavailable: reasonAnalysisUnavailable,
        PairingQualityReasonKeys.samePhoto: reasonSamePhoto,
    ]

    private static func humanizeReason(_ rawValue: String) -> String {
        let suffix = rawValue.split(separator: ".").last.map(String.init) ?? rawValue
        var spaced = ""
        for (index, character) in suffix.enumerated() {
            if character.isUppercase, index > 0 {
                spaced.append(" ")
            }
            spaced.append(character)
        }
        let lowercased = spaced.lowercased()
        guard let first = lowercased.first else {
            return reasonUnknown.text
        }
        let remainder = String(lowercased.dropFirst())
        return String(first).uppercased() + remainder + "."
    }
}
