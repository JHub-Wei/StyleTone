import Foundation

/// Accessibility identifiers owned by the pairing screen.
///
/// The convention is the frozen `screen.element` one from
/// `docs/10-task-decomposition/contracts.md` §8. Per-pair identifiers nest a
/// stable pair segment (`pair1`, `pair2`, …) so UI tests can address the third
/// card's edited slot without depending on label text.
public enum PairingAccessibilityID {
    // MARK: Screen-level

    public static let screen = AccessibilityID(.pairing, "root")
    public static let progress = AccessibilityID(.pairing, "progress")
    public static let progressValue = AccessibilityID(.pairing, "progress.value")
    public static let counts = AccessibilityID(.pairing, "counts")
    public static let countsGood = AccessibilityID(.pairing, "counts.good")
    public static let countsWarning = AccessibilityID(.pairing, "counts.warning")
    public static let countsRejected = AccessibilityID(.pairing, "counts.rejected")
    public static let targetPicker = AccessibilityID(.pairing, "targetPicker")
    public static let pairList = AccessibilityID(.pairing, "pairList")
    public static let emptyState = AccessibilityID(.pairing, "emptyState")
    public static let addPairButton = AccessibilityID.pairingAddPairButton
    public static let continueButton = AccessibilityID.pairingContinueButton
    public static let skipButton = AccessibilityID(.pairing, "skipButton")
    public static let continueHint = AccessibilityID(.pairing, "continueHint")
    public static let saveState = AccessibilityID(.pairing, "saveState")
    public static let pickerNote = AccessibilityID(.pairing, "pickerNote")
    public static let pickerUnavailable = AccessibilityID(.pairing, "pickerUnavailable")
    public static let notice = AccessibilityID(.pairing, "notice")
    public static let noticeAction = AccessibilityID(.pairing, "notice.actionButton")
    public static let noticeDismiss = AccessibilityID(.pairing, "notice.dismissButton")
    public static let pickerUnavailableDismiss = AccessibilityID(
        .pairing,
        "pickerUnavailable.dismissButton"
    )
    public static let loading = AccessibilityID(.pairing, "loading")
    public static let undoBar = AccessibilityID(.pairing, "undoBar")
    public static let undoButton = AccessibilityID(.pairing, "undoButton")

    // MARK: Per-target

    public static func target(_ target: PairingTarget) -> AccessibilityID {
        AccessibilityID(.pairing, "target.\(targetName(target))")
    }

    // MARK: Per-pair

    public static func pair(_ number: Int) -> AccessibilityID {
        AccessibilityID(.pairing, pairSegment(number))
    }

    public static func pairTitle(_ number: Int) -> AccessibilityID {
        AccessibilityID(.pairing, "\(pairSegment(number)).title")
    }

    public static func slot(_ slot: PairingSlot, pair number: Int) -> AccessibilityID {
        AccessibilityID(.pairing, "\(pairSegment(number)).\(slot.rawValue)")
    }

    public static func photo(_ slot: PairingSlot, pair number: Int) -> AccessibilityID {
        AccessibilityID(.pairing, "\(pairSegment(number)).\(slot.rawValue).photo")
    }

    public static func pickButton(_ slot: PairingSlot, pair number: Int) -> AccessibilityID {
        AccessibilityID(.pairing, "\(pairSegment(number)).\(slot.rawValue).pickButton")
    }

    public static func removeButton(_ slot: PairingSlot, pair number: Int) -> AccessibilityID {
        AccessibilityID(.pairing, "\(pairSegment(number)).\(slot.rawValue).removeButton")
    }

    public static func slotNote(_ slot: PairingSlot, pair number: Int) -> AccessibilityID {
        AccessibilityID(.pairing, "\(pairSegment(number)).\(slot.rawValue).note")
    }

    public static func deleteButton(pair number: Int) -> AccessibilityID {
        AccessibilityID(.pairing, "\(pairSegment(number)).deleteButton")
    }

    public static func quality(pair number: Int) -> AccessibilityID {
        AccessibilityID(.pairing, "\(pairSegment(number)).quality")
    }

    public static func retryButton(pair number: Int) -> AccessibilityID {
        AccessibilityID(.pairing, "\(pairSegment(number)).retryButton")
    }

    public static func importingIndicator(pair number: Int) -> AccessibilityID {
        AccessibilityID(.pairing, "\(pairSegment(number)).importing")
    }

    /// Placeholder canvases in the empty state.
    public static func emptyPhoto(_ slot: PairingSlot) -> AccessibilityID {
        AccessibilityID(.pairing, "emptyState.\(slot.rawValue)")
    }

    // MARK: - Catalogs

    /// Screen-level identifiers, for convention tests.
    public static let all: [AccessibilityID] = [
        screen,
        progress,
        progressValue,
        counts,
        countsGood,
        countsWarning,
        countsRejected,
        targetPicker,
        pairList,
        emptyState,
        addPairButton,
        continueButton,
        skipButton,
        continueHint,
        saveState,
        pickerNote,
        pickerUnavailable,
        notice,
        noticeAction,
        noticeDismiss,
        pickerUnavailableDismiss,
        loading,
        undoBar,
        undoButton,
        target(.three),
        target(.five),
        target(.eight),
        emptyPhoto(.original),
        emptyPhoto(.edited),
    ]

    /// Every identifier one pair card exposes, for convention tests.
    public static func identifiers(forPair number: Int) -> [AccessibilityID] {
        var identifiers: [AccessibilityID] = [
            pair(number),
            pairTitle(number),
            deleteButton(pair: number),
            quality(pair: number),
            retryButton(pair: number),
            importingIndicator(pair: number),
        ]
        for slot in PairingSlot.allCases {
            identifiers.append(slot(slot, pair: number))
            identifiers.append(photo(slot, pair: number))
            identifiers.append(pickButton(slot, pair: number))
            identifiers.append(removeButton(slot, pair: number))
            identifiers.append(slotNote(slot, pair: number))
        }
        return identifiers
    }

    private static func pairSegment(_ number: Int) -> String {
        "pair\(max(1, number))"
    }

    private static func targetName(_ target: PairingTarget) -> String {
        switch target {
        case .three: return "three"
        case .five: return "five"
        case .eight: return "eight"
        }
    }
}
