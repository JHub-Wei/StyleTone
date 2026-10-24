import Foundation

/// A recovery action attached to a notice.
public enum PairingNoticeAction: Sendable, Equatable {
    /// Opens the system picker again for the given pair and mode.
    case reopenPicker(PairingPickMode, pairID: UUID)
    /// Re-runs the quality check for one pair.
    case retryAssessment(UUID)
    /// Saves the current session again.
    case retrySave
    /// Retries loading the stored session.
    case retryLoad
    /// Clears the stored session and starts from an empty one.
    case startFreshSession
    /// Re-checks whether the system picker can be presented.
    case refreshPickerAvailability
    /// Re-opens a completed session for editing.
    case resumeEditing
}

/// One inline banner above the pair list.
public struct PairingNotice: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case info
        case success
        case warning
        case error
    }

    public let id: UUID
    public let kind: Kind
    public let title: PairingText
    public let message: PairingText?
    public let action: PairingNoticeAction?
    public let actionTitle: PairingText?
    public let isDismissible: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: PairingText,
        message: PairingText? = nil,
        action: PairingNoticeAction? = nil,
        actionTitle: PairingText? = nil,
        isDismissible: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.action = action
        self.actionTitle = actionTitle
        self.isDismissible = isDismissible
    }

    /// Combined text read by VoiceOver.
    public var accessibilityLabel: String {
        [title.text, message?.text].compactMap { $0 }.joined(separator: ". ")
    }

    // MARK: - Factories

    public static func importFailure(
        _ error: PairingImportError,
        mode: PairingPickMode,
        pairID: UUID
    ) -> PairingNotice {
        PairingNotice(
            kind: .error,
            title: error.title,
            message: error.message,
            action: .reopenPicker(mode, pairID: pairID),
            actionTitle: PairingCopy.retry
        )
    }

    public static func sessionLoadFailure(_ error: PairingSessionStoreError) -> PairingNotice {
        PairingNotice(
            kind: .error,
            title: error.title,
            message: error.message,
            action: .startFreshSession,
            actionTitle: PairingCopy.sessionStartFresh,
            isDismissible: true
        )
    }

    public static func sessionSaveFailure() -> PairingNotice {
        PairingNotice(
            kind: .warning,
            title: PairingCopy.sessionSaveTitle,
            message: PairingCopy.sessionSaveMessage,
            action: .retrySave,
            actionTitle: PairingCopy.saveRetry
        )
    }

    public static func pickerUnavailable(_ reason: PairingPickerUnavailableReason) -> PairingNotice {
        PairingNotice(
            kind: .warning,
            title: PairingCopy.pickerUnavailableTitle,
            message: PairingCopy.pickerUnavailableMessage,
            action: .refreshPickerAvailability,
            actionTitle: PairingCopy.pickerRetry,
            isDismissible: false
        )
    }

    public static func restoredSession(hasStalePhotos: Bool) -> PairingNotice {
        PairingNotice(
            kind: .info,
            title: PairingCopy.restoredNotice,
            message: hasStalePhotos ? PairingCopy.staleNotice : nil
        )
    }

    public static func completedSession() -> PairingNotice {
        PairingNotice(
            kind: .success,
            title: PairingCopy.completedNotice,
            action: .resumeEditing,
            actionTitle: PairingCopy.keepEditing
        )
    }

    public static func limitReached() -> PairingNotice {
        PairingNotice(kind: .info, title: PairingCopy.limitReached)
    }
}
