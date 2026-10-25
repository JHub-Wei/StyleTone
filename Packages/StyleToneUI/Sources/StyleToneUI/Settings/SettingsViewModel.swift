import Foundation
import Observation
import StyleToneCore

/// A short, already-localized status message shown above the settings content.
public struct SettingsNotice: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable, Equatable {
        case info
        case success
        case warning
        case error
    }

    public let id: UUID
    public let text: String
    public let kind: Kind

    public init(id: UUID = UUID(), text: String, kind: Kind = .info) {
        self.id = id
        self.text = text
        self.kind = kind
    }
}

/// Screen lifecycle.
public enum SettingsPhase: String, Sendable, Equatable {
    case loading
    case ready
}

/// The two-step deletion state machine.
///
/// `.firstConfirmation` and `.finalConfirmation` are separate states so the
/// second confirmation cannot be skipped by a single tap and so the UI test can
/// assert every transition.
public enum SettingsDeleteStage: String, Sendable, Equatable {
    case idle
    case firstConfirmation
    case finalConfirmation
    case deleting
    case deleted
    case failed
}

/// State and actions behind the settings screen.
///
/// The model owns no SwiftUI types. Deletion, diagnostics and version data are
/// injected protocols, which keeps the feature testable on macOS and keeps the
/// UI free of Persistence/StoreKit/Filesystem imports.
@MainActor
@Observable
public final class SettingsViewModel {
    // MARK: Observable state

    public private(set) var phase: SettingsPhase = .loading
    public private(set) var version: SettingsVersionInfo
    public private(set) var support: SettingsSupportInfo
    public private(set) var licenses: SettingsLicenseCatalog
    public private(set) var diagnosticsSnapshot: SettingsDiagnosticsSnapshot
    public private(set) var isDiagnosticsEnabled: Bool
    public private(set) var deleteStage: SettingsDeleteStage = .idle
    public private(set) var deletionReport: SettingsLocalDataDeletionReport?
    public private(set) var notice: SettingsNotice?
    public private(set) var isBusy = false

    @ObservationIgnored private let dependencies: SettingsDependencies

    // MARK: Init

    public init(dependencies: SettingsDependencies) {
        self.dependencies = dependencies
        let currentVersion = dependencies.versionProvider.currentVersion()
        version = currentVersion
        support = dependencies.support
        licenses = dependencies.licenseProvider.catalog()
        diagnosticsSnapshot = .disabled(version: currentVersion, at: dependencies.dateProvider.now)
        isDiagnosticsEnabled = false
    }

    // MARK: Derived state

    public var diagnosticCode: String {
        diagnosticsSnapshot.code
    }

    public var diagnosticEntryCount: Int {
        diagnosticsSnapshot.entries.count
    }

    public var diagnosticsStatusText: String {
        isDiagnosticsEnabled
            ? SettingsCopy.diagnosticsStatusOn.text
            : SettingsCopy.diagnosticsStatusOff.text
    }

    public var diagnosticsNoteText: String {
        isDiagnosticsEnabled
            ? SettingsCopy.diagnosticsOnNote.text
            : SettingsCopy.diagnosticsOffNote.text
    }

    public var canDeleteData: Bool {
        phase == .ready && !isBusy && deleteStage == .idle
    }

    /// True after a complete deletion; the host can immediately navigate to
    /// onboarding. A relaunch also lands there because preferences and profile
    /// data are empty.
    public var requiresOnboarding: Bool {
        deleteStage == .deleted && deletionReport?.isComplete == true
    }

    public var isDeletionInProgress: Bool {
        deleteStage == .deleting
    }

    public var isFirstConfirmation: Bool {
        deleteStage == .firstConfirmation
    }

    public var isFinalConfirmation: Bool {
        deleteStage == .finalConfirmation
    }

    public var deleteFailureText: String? {
        guard deleteStage == .failed else { return nil }
        return SettingsCopy.deleteFailedBody.text
    }

    // MARK: Lifecycle

    /// Loads the diagnostics opt-in and records that Settings was opened when
    /// the user has opted in.
    public func load() async {
        guard phase == .loading else { return }
        isBusy = true

        diagnosticsSnapshot = await dependencies.diagnostics.snapshot()
        isDiagnosticsEnabled = diagnosticsSnapshot.isEnabled
        if isDiagnosticsEnabled {
            await dependencies.diagnostics.record(
                SettingsDiagnosticEvent(kind: .settingsOpened)
            )
            diagnosticsSnapshot = await dependencies.diagnostics.snapshot()
        }

        isBusy = false
        phase = .ready
    }

    // MARK: Diagnostics

    /// Runs one toggle transition. Exposed for tests; the view uses
    /// ``requestDiagnosticsToggle(_:)``.
    public func setDiagnosticsEnabled(_ enabled: Bool) async {
        guard phase == .ready, !isBusy, enabled != isDiagnosticsEnabled else { return }

        // Optimistic UI: the switch follows the tap immediately, then snaps
        // back if persistence fails.
        isDiagnosticsEnabled = enabled
        isBusy = true
        defer { isBusy = false }

        do {
            diagnosticsSnapshot = try await dependencies.diagnostics.setEnabled(enabled)
            isDiagnosticsEnabled = diagnosticsSnapshot.isEnabled
            show(
                enabled ? SettingsCopy.diagnosticsEnabledNotice : SettingsCopy.diagnosticsDisabledNotice,
                kind: .success
            )
        } catch {
            diagnosticsSnapshot = await dependencies.diagnostics.snapshot()
            isDiagnosticsEnabled = diagnosticsSnapshot.isEnabled
            show(
                enabled ? SettingsCopy.diagnosticsEnableFailed : SettingsCopy.diagnosticsDisableFailed,
                kind: .error
            )
        }
    }

    /// Entry point for the SwiftUI toggle; ignores taps while a transition runs.
    public func requestDiagnosticsToggle(_ enabled: Bool) {
        guard phase == .ready, !isBusy, enabled != isDiagnosticsEnabled else { return }
        Task { @MainActor in
            await self.setDiagnosticsEnabled(enabled)
        }
    }

    /// Removes log entries but keeps the opt-in unchanged.
    public func clearDiagnostics() async {
        guard phase == .ready, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            diagnosticsSnapshot = try await dependencies.diagnostics.clear()
            isDiagnosticsEnabled = diagnosticsSnapshot.isEnabled
            show(SettingsCopy.diagnosticsCleared, kind: .success)
        } catch {
            diagnosticsSnapshot = await dependencies.diagnostics.snapshot()
            isDiagnosticsEnabled = diagnosticsSnapshot.isEnabled
            show(SettingsCopy.diagnosticsClearFailed, kind: .error)
        }
    }

    public func copyDiagnosticCode() {
        let code = diagnosticsSnapshot.code
        guard !code.isEmpty, dependencies.pasteboard.copy(code) else {
            show(SettingsCopy.diagnosticsCopyFailed, kind: .error)
            return
        }
        show(SettingsCopy.diagnosticsCopied, kind: .success)
    }

    public func copySupportEmail() {
        guard support.hasValidEmail, dependencies.pasteboard.copy(support.email) else {
            show(SettingsCopy.copyFailed, kind: .error)
            return
        }
        show(SettingsCopy.supportEmailCopied, kind: .success)
    }

    // MARK: Deletion

    public func requestDelete() {
        guard canDeleteData else { return }
        deleteStage = .firstConfirmation
    }

    public func continueDelete() {
        guard deleteStage == .firstConfirmation else { return }
        deleteStage = .finalConfirmation
    }

    public func backToDeleteOverview() {
        guard deleteStage == .finalConfirmation else { return }
        deleteStage = .firstConfirmation
    }

    public func cancelDelete() {
        guard deleteStage == .firstConfirmation || deleteStage == .finalConfirmation else { return }
        deleteStage = .idle
    }

    /// Enters the deleting state synchronously, so dismissing the confirmation
    /// sheet cannot cancel the deletion that was just confirmed.
    public func beginDeletion() {
        guard deleteStage == .finalConfirmation else { return }
        deleteStage = .deleting
        isBusy = true
    }

    /// Starts deletion and waits for its report. The view calls this after the
    /// final destructive button.
    public func confirmDeletion() async {
        guard deleteStage == .finalConfirmation else { return }
        beginDeletion()
        await performDeletion()
    }

    /// Runs the deletion for an already-entered `.deleting` state.
    public func performDeletion() async {
        guard deleteStage == .deleting else { return }

        deletionReport = nil
        let report = await dependencies.dataDeleter.deleteAllLocalData()
        deletionReport = report

        // The preference domain is part of the deletion, so diagnostics must
        // come back off. Do not record an event here: it would recreate a log
        // immediately after the user deleted everything.
        diagnosticsSnapshot = await dependencies.diagnostics.snapshot()
        isDiagnosticsEnabled = diagnosticsSnapshot.isEnabled

        if report.isComplete {
            deleteStage = .deleted
            show(SettingsCopy.deleteNoticeDeleted, kind: .success)
        } else {
            deleteStage = .failed
            show(SettingsCopy.deleteNoticeFailed, kind: .error)
        }
        isBusy = false
    }

    /// Retries after a partial deletion without asking for confirmation again;
    /// the destructive intent was already confirmed.
    public func retryDeletion() async {
        guard phase == .ready, deleteStage == .failed else { return }
        deleteStage = .deleting
        isBusy = true
        await performDeletion()
    }

    public func dismissNotice() {
        notice = nil
    }

    // MARK: Private

    private func show(_ text: SettingsText, kind: SettingsNotice.Kind) {
        notice = SettingsNotice(text: text.text, kind: kind)
    }
}
