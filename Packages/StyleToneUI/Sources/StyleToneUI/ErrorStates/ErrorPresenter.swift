import Foundation
import Observation
import StyleToneCore

// MARK: - Record

/// One entry in the presenter's bounded diagnostic history.
///
/// It stores enums and codes only: never copy, image data, file names or other
/// user content. Diagnostics can therefore be exported without a privacy review
/// of the error surface itself.
public struct ErrorRecord: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let diagnosticCode: DiagnosticCode
    public let sourceCode: String?
    public let kind: ErrorKind
    public let context: ErrorContext
    public let severity: ErrorSeverity
    public let occurredAt: Date

    init(
        id: UUID = UUID(),
        diagnosticCode: DiagnosticCode,
        sourceCode: String? = nil,
        kind: ErrorKind,
        context: ErrorContext,
        severity: ErrorSeverity,
        occurredAt: Date
    ) {
        self.id = id
        self.diagnosticCode = diagnosticCode
        self.sourceCode = sourceCode
        self.kind = kind
        self.context = context
        self.severity = severity
        self.occurredAt = occurredAt
    }
}

// MARK: - Presenter

/// Owns the app's current error card, transient toast and recovery dispatch.
///
/// One presenter is shared by the shell and injected into screens. Pages keep
/// their own task state; the presenter only decides what the user sees and
/// forwards the chosen action. Presentation is synchronous and never awaits
/// page work, so a slow recovery cannot block or freeze the UI.
@MainActor
@Observable
public final class ErrorPresenter {
    // MARK: Observable state

    /// The blocking/recoverable error card currently shown.
    public private(set) var current: ErrorState?
    /// A transient advisory, if the page chose the toast presentation.
    public private(set) var toast: ToastMessage?
    /// Bounded history of presented errors, newest last.
    public private(set) var history: [ErrorRecord] = []

    /// Page hook. The owning screen translates canonical actions into commands.
    public var onRecovery: (@MainActor (RecoveryAction, ErrorState) -> Void)?

    // MARK: Dependencies

    @ObservationIgnored private let logger: any AppLogging
    @ObservationIgnored private let dateProvider: any DateProviding
    @ObservationIgnored private let maximumHistory: Int
    @ObservationIgnored private var suppressedKeys: Set<String> = []

    public init(
        logger: any AppLogging = NoopLogger(),
        dateProvider: any DateProviding = SystemDateProvider(),
        maximumHistory: Int = 20
    ) {
        self.logger = logger
        self.dateProvider = dateProvider
        self.maximumHistory = max(1, maximumHistory)
    }

    // MARK: Present

    /// Maps and presents any error. Cancellation is recorded in the log but
    /// never shown.
    public func present(_ error: Error, context: ErrorContext = .general) {
        present(ErrorMapper.state(for: error, context: context))
    }

    /// Presents the full card with copy, actions and support code.
    public func present(_ state: ErrorState) {
        guard !state.isSilent else {
            log(state, level: .info, event: "ui.error.suppressed")
            return
        }

        current = state
        toast = nil
        record(state)
        log(
            state,
            level: state.severity == .notice ? .warning : .error,
            event: "ui.error.presented"
        )
    }

    /// Presents a transient advisory.
    ///
    /// Only use this for states without a meaningful action; recoverable errors
    /// should use ``present(_:)`` so their buttons and support code stay
    /// visible.
    public func presentAsToast(_ state: ErrorState, duration: TimeInterval = 4) {
        guard !state.isSilent else {
            log(state, level: .info, event: "ui.error.suppressed")
            return
        }

        toast = Self.toastMessage(for: state, duration: duration)
        record(state)
        log(
            state,
            level: state.severity == .notice ? .warning : .error,
            event: "ui.error.toast"
        )
    }

    /// Presents a state at most once per key (by default its support code).
    ///
    /// Low-battery, thermal and low-storage advisories use this so a page update
    /// cannot stack identical cards.
    public func presentOnce(_ state: ErrorState, key: String? = nil) {
        let suppressionKey = key ?? state.diagnosticCode.rawValue
        guard suppressedKeys.insert(suppressionKey).inserted else { return }
        present(state)
    }

    // MARK: Dismiss

    public func dismiss() {
        current = nil
    }

    /// Dismisses the toast; with an id, only that toast.
    public func dismissToast(id: UUID? = nil) {
        guard let id else {
            toast = nil
            return
        }
        if toast?.id == id {
            toast = nil
        }
    }

    /// Allows the same `presentOnce` key to be shown again, for example after a
    /// new editing session starts.
    public func resetSuppression() {
        suppressedKeys.removeAll()
    }

    // MARK: Recovery

    public func canPerform(_ action: RecoveryAction) -> Bool {
        current?.supports(action) == true
    }

    /// Forwards a recovery choice to the page hook.
    ///
    /// Dismiss is handled locally even when no handler is wired, so closing the
    /// card can never fail. Returns `false` for an action the current state does
    /// not offer, or for a non-dismiss action with no handler.
    @discardableResult
    public func perform(_ action: RecoveryAction) -> Bool {
        guard let state = current, state.supports(action) else { return false }

        if action == .dismiss {
            logRecovery(action, state)
            dismiss()
            return true
        }

        guard let onRecovery else { return false }
        logRecovery(action, state)
        onRecovery(action, state)
        return true
    }

    // MARK: Toast helper

    public static func toastMessage(
        for state: ErrorState,
        duration: TimeInterval = 4
    ) -> ToastMessage {
        state.toastMessage(duration: duration)
    }

    // MARK: Private

    private func record(_ state: ErrorState) {
        history.append(
            ErrorRecord(
                diagnosticCode: state.diagnosticCode,
                sourceCode: state.sourceCode,
                kind: state.kind,
                context: state.context,
                severity: state.severity,
                occurredAt: dateProvider.now
            )
        )
        if history.count > maximumHistory {
            history.removeFirst(history.count - maximumHistory)
        }
    }

    private func log(_ state: ErrorState, level: LogLevel, event: String) {
        logger.log(
            level,
            event,
            metadata: [
                "code": state.diagnosticCode.rawValue,
                "source": state.sourceCode ?? "none",
                "domain": state.domain.rawValue,
                "context": state.context.rawValue,
                "severity": state.severity.rawValue,
            ]
        )
    }

    private func logRecovery(_ action: RecoveryAction, _ state: ErrorState) {
        logger.log(
            .info,
            "ui.error.recovery",
            metadata: [
                "code": state.diagnosticCode.rawValue,
                "action": action.rawValue,
                "context": state.context.rawValue,
            ]
        )
    }
}
