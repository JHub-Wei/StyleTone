import Foundation

// MARK: - Severity

/// How strongly the surface should present an error.
public enum ErrorSeverity: String, CaseIterable, Sendable, Codable, Hashable {
    /// Advisory; the current action can continue.
    case notice
    /// The current action failed and needs a recovery choice.
    case recoverable

    var toastKind: ToastMessage.Kind {
        switch self {
        case .notice: return .warning
        case .recoverable: return .error
        }
    }
}

// MARK: - Context

/// Where the error was caught. Diagnostics only; copy stays context-free.
public enum ErrorContext: String, CaseIterable, Sendable, Codable, Hashable {
    case shell
    case pairing
    case calibration
    case editor
    case export
    case settings
    case paywall
    case diagnostics
    case general
}

// MARK: - Recovery

/// One recovery affordance attached to an error.
///
/// Pages translate these canonical actions into their own commands. The error
/// unit always contains at least `.dismiss` for a non-silent state, so the user
/// is never trapped.
public enum RecoveryAction: String, CaseIterable, Sendable, Codable, Hashable {
    case retry
    case resume
    case continueOffline
    case continueAnyway
    case openSettings
    case freeUpSpace
    case restorePurchase
    case shareInstead
    case saveInstead
    case upgrade
    case chooseAnotherPhoto
    case useNaturalStyle
    case reduceStrength
    case recalibrate
    case dismiss

    public var title: ErrorText {
        ErrorCopy.actionTitle(self)
    }

    /// Whether this action should be rendered with the primary button style.
    public var isPreferred: Bool {
        switch self {
        case .shareInstead, .saveInstead, .dismiss:
            return false
        case .retry, .resume, .continueOffline, .continueAnyway, .openSettings,
             .freeUpSpace, .restorePurchase, .upgrade, .chooseAnotherPhoto,
             .useNaturalStyle, .reduceStrength, .recalibrate:
            return true
        }
    }

    /// SF Symbol name used by the shared error card.
    public var systemImage: String {
        switch self {
        case .retry: return "arrow.clockwise"
        case .resume: return "play.fill"
        case .continueOffline: return "wifi.slash"
        case .continueAnyway: return "arrow.right"
        case .openSettings: return "gearshape"
        case .freeUpSpace: return "externaldrive.badge.minus"
        case .restorePurchase: return "arrow.counterclockwise"
        case .shareInstead: return "square.and.arrow.up"
        case .saveInstead: return "square.and.arrow.down"
        case .upgrade: return "sparkles"
        case .chooseAnotherPhoto: return "photo"
        case .useNaturalStyle: return "wand.and.stars"
        case .reduceStrength: return "slider.horizontal.3"
        case .recalibrate: return "arrow.triangle.2.circlepath"
        case .dismiss: return "xmark"
        }
    }
}

// MARK: - State

/// The single user-facing error value used by every screen.
///
/// `ErrorState` contains no file names, image identifiers, URLs or user text.
/// Construct it through ``ErrorMapper`` (or one of the page adapters) so the
/// same engine error always resolves to the same copy, actions and support
/// code.
public struct ErrorState: Identifiable, Sendable, Equatable, Error {
    public let id: UUID
    public let kind: ErrorKind
    public let context: ErrorContext
    public let recoveryActions: [RecoveryAction]
    public let diagnosticCode: DiagnosticCode
    /// The closest underlying machine code, kept for diagnostics only.
    ///
    /// For example `E_RENDER`, `E_LIBRARY_PERMISSION` or `URLError.-1009`.
    /// Never shown as the primary support code and never localized.
    public let sourceCode: String?

    public init(
        id: UUID = UUID(),
        kind: ErrorKind,
        context: ErrorContext = .general,
        recoveryActions: [RecoveryAction]? = nil,
        diagnosticCode: DiagnosticCode? = nil,
        sourceCode: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.context = context

        var actions: [RecoveryAction]
        if kind.isSilent {
            actions = []
        } else {
            actions = recoveryActions ?? kind.defaultRecoveries
            if actions.isEmpty {
                actions = kind.defaultRecoveries
            }
            if actions.isEmpty {
                actions = [.dismiss]
            }
            if !actions.contains(.dismiss) {
                actions.append(.dismiss)
            }
            var seen: Set<RecoveryAction> = []
            actions = actions.filter { seen.insert($0).inserted }
        }

        self.recoveryActions = actions
        if let diagnosticCode, diagnosticCode.isValid {
            self.diagnosticCode = diagnosticCode
        } else {
            self.diagnosticCode = kind.diagnosticCode
        }
        self.sourceCode = Self.sanitizedSourceCode(sourceCode)
    }

    // MARK: Copy

    public var title: ErrorText {
        ErrorCopy.title(kind)
    }

    public var message: ErrorText {
        ErrorCopy.message(kind)
    }

    public var diagnosticText: String {
        ErrorCopy.diagnosticText(diagnosticCode.rawValue)
    }

    /// VoiceOver label for the whole card. The support code stays a separate,
    /// addressable element so a UI test can query it without reading the title
    /// and message as one blob.
    public var accessibilityLabel: String {
        [title.text, message.text].joined(separator: ". ")
    }

    // MARK: Semantics

    public var domain: ErrorDomain {
        kind.domain
    }

    public var severity: ErrorSeverity {
        kind.severity
    }

    public var isSilent: Bool {
        kind.isSilent
    }

    public var isRetryable: Bool {
        recoveryActions.contains(.retry)
    }

    /// The first preferred action, or the first action when none is preferred.
    public var primaryAction: RecoveryAction? {
        recoveryActions.first(where: { $0.isPreferred }) ?? recoveryActions.first
    }

    public func supports(_ action: RecoveryAction) -> Bool {
        recoveryActions.contains(action)
    }

    /// Adapter for the existing design-system toast.
    ///
    /// Pages that want a transient advisory can call
    /// `ErrorPresenter.presentAsToast`; blocking/recoverable errors should use
    /// the full card so the actions and support code stay visible.
    public func toastMessage(duration: TimeInterval = 4) -> ToastMessage {
        ToastMessage(text: message.text, kind: severity.toastKind, duration: duration)
    }

    // MARK: - Source-code hygiene

    /// Keeps only machine-code characters, so a caller cannot accidentally put a
    /// path, URL, email address or photo identifier into the diagnostic log.
    static func sanitizedSourceCode(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.count <= 64 else { return nil }
        let allowed = raw.unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value) // A-Z
                || (97...122).contains(scalar.value) // a-z
                || (48...57).contains(scalar.value) // 0-9
                || scalar.value == 45 // -
                || scalar.value == 46 // .
                || scalar.value == 95 // _
        }
        return allowed ? raw : nil
    }
}

// MARK: - Accessibility

/// Accessibility identifiers for the shared error surface.
///
/// `designSystem` is the only frozen screen available to a cross-screen
/// component; identifiers stay under `designSystem.error.*` so a UI test can
/// address the same card on every screen.
public enum ErrorStateAccessibility {
    public static let card = AccessibilityID(.designSystem, "error.card")
    public static let diagnostic = AccessibilityID(.designSystem, "error.diagnostic")

    public static func actionButton(_ action: RecoveryAction) -> AccessibilityID {
        AccessibilityID(.designSystem, "error.action.\(action.rawValue)")
    }

    public static let all: [AccessibilityID] =
        [card, diagnostic] + RecoveryAction.allCases.map { actionButton($0) }
}
