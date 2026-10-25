import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

@MainActor
final class SettingsViewModelTests: XCTestCase {
    // MARK: Load

    func testInitialStateIsLoadingAndOff() {
        let fixture = SettingsTestFactory.diagnostics()
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)

        XCTAssertEqual(model.phase, .loading)
        XCTAssertFalse(model.isDiagnosticsEnabled)
        XCTAssertFalse(model.canDeleteData)
        XCTAssertEqual(model.deleteStage, .idle)
        XCTAssertEqual(model.version, SettingsTestFactory.version)
        XCTAssertTrue(SettingsDiagnosticCode.isWellFormed(model.diagnosticCode))
    }

    func testLoadMakesTheScreenReady() async {
        let fixture = SettingsTestFactory.diagnostics()
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)

        await model.load()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.isBusy)
        XCTAssertFalse(model.isDiagnosticsEnabled)
        XCTAssertTrue(model.canDeleteData)
        XCTAssertEqual(model.diagnosticsStatusText, SettingsCopy.diagnosticsStatusOff.text)
    }

    func testLoadIsIdempotentAndDoesNotDuplicateTheOpenEvent() async {
        let fixture = SettingsTestFactory.diagnostics(enabled: true)
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)

        await model.load()
        await model.load()

        let snapshot = await fixture.service.snapshot()
        XCTAssertEqual(snapshot.entries.filter { $0.kind == .settingsOpened }.count, 1)
    }

    func testSettingsOpenIsNotRecordedWhenDiagnosticsAreOff() async {
        let fixture = SettingsTestFactory.diagnostics()
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)

        await model.load()

        let entries = await fixture.logStore.currentEntries()
        XCTAssertTrue(entries.isEmpty)
        let saveCount = await fixture.logStore.saveCount
        XCTAssertEqual(saveCount, 0)
    }

    func testSettingsOpenIsRecordedWhenDiagnosticsAreOn() async {
        let fixture = SettingsTestFactory.diagnostics(enabled: true)
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)

        await model.load()

        let snapshot = await fixture.service.snapshot()
        XCTAssertEqual(snapshot.entries.map(\.kind), [.settingsOpened])
    }

    // MARK: Diagnostics

    func testToggleOnOffUpdatesStateAndLog() async {
        let fixture = SettingsTestFactory.diagnostics()
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)
        await model.load()

        await model.setDiagnosticsEnabled(true)
        XCTAssertTrue(model.isDiagnosticsEnabled)
        XCTAssertEqual(model.notice?.kind, .success)

        await fixture.service.record(SettingsDiagnosticEvent(kind: .exportSucceeded))
        var snapshot = await fixture.service.snapshot()
        XCTAssertEqual(snapshot.entries.count, 1)

        await model.setDiagnosticsEnabled(false)
        XCTAssertFalse(model.isDiagnosticsEnabled)
        snapshot = await fixture.service.snapshot()
        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertEqual(model.notice?.kind, .success)
    }

    func testToggleFailureRevertsTheSwitch() async {
        let preferences = InMemorySettingsDiagnosticsPreferences(setError: .preferenceUnavailable)
        let fixture = SettingsTestFactory.diagnostics(preferences: preferences)
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)
        await model.load()

        await model.setDiagnosticsEnabled(true)

        XCTAssertFalse(model.isDiagnosticsEnabled)
        XCTAssertEqual(model.notice?.kind, .error)
        XCTAssertEqual(model.notice?.text, SettingsCopy.diagnosticsEnableFailed.text)
    }

    func testToggleIgnoresARepeatedValue() async {
        let fixture = SettingsTestFactory.diagnostics()
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)
        await model.load()

        await model.setDiagnosticsEnabled(false)
        XCTAssertEqual(model.notice, nil)
    }

    func testCodeChangesWhenDiagnosticsAreEnabled() async {
        let fixture = SettingsTestFactory.diagnostics()
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)
        await model.load()
        let offCode = model.diagnosticCode

        await model.setDiagnosticsEnabled(true)
        XCTAssertNotEqual(model.diagnosticCode, offCode)
        XCTAssertTrue(SettingsDiagnosticCode.isWellFormed(model.diagnosticCode))
    }

    func testClearDiagnosticsKeepsOptIn() async {
        let fixture = SettingsTestFactory.diagnostics(enabled: true)
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)
        await model.load()
        let before = await fixture.service.snapshot()
        XCTAssertFalse(before.entries.isEmpty)

        await model.clearDiagnostics()

        XCTAssertTrue(model.isDiagnosticsEnabled)
        XCTAssertEqual(model.diagnosticEntryCount, 0)
        XCTAssertEqual(model.notice?.text, SettingsCopy.diagnosticsCleared.text)
    }

    func testClearDiagnosticsFailureShowsAnError() async {
        let logStore = InMemorySettingsDiagnosticsLogStore(clearError: .logUnavailable)
        let fixture = SettingsTestFactory.diagnostics(enabled: true, logStore: logStore)
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)
        await model.load()

        await model.clearDiagnostics()

        XCTAssertEqual(model.notice?.kind, .error)
        XCTAssertEqual(model.notice?.text, SettingsCopy.diagnosticsClearFailed.text)
        XCTAssertTrue(model.isDiagnosticsEnabled)
    }

    // MARK: Copy

    func testCopyDiagnosticCodeUsesTheInjectedPasteboard() async {
        let fixture = SettingsTestFactory.diagnostics()
        let pasteboard = SettingsRecordingPasteboard()
        let model = SettingsTestFactory.viewModel(
            diagnostics: fixture.service,
            pasteboard: pasteboard
        )
        await model.load()

        model.copyDiagnosticCode()

        XCTAssertEqual(pasteboard.copied, [model.diagnosticCode])
        XCTAssertEqual(model.notice?.text, SettingsCopy.diagnosticsCopied.text)
    }

    func testCopyFailureShowsAnError() async {
        let fixture = SettingsTestFactory.diagnostics()
        let pasteboard = SettingsRecordingPasteboard()
        pasteboard.succeeds = false
        let model = SettingsTestFactory.viewModel(
            diagnostics: fixture.service,
            pasteboard: pasteboard
        )
        await model.load()

        model.copyDiagnosticCode()

        XCTAssertEqual(model.notice?.kind, .error)
        XCTAssertEqual(model.notice?.text, SettingsCopy.diagnosticsCopyFailed.text)
    }

    func testCopySupportEmail() async {
        let fixture = SettingsTestFactory.diagnostics()
        let pasteboard = SettingsRecordingPasteboard()
        let support = SettingsSupportInfo(email: "help@styletone.app")
        let model = SettingsTestFactory.viewModel(
            diagnostics: fixture.service,
            pasteboard: pasteboard,
            support: support
        )
        await model.load()

        model.copySupportEmail()

        XCTAssertEqual(pasteboard.copied, ["help@styletone.app"])
        XCTAssertEqual(model.notice?.text, SettingsCopy.supportEmailCopied.text)
    }

    func testCopySupportEmailRejectsAnInvalidAddress() async {
        let fixture = SettingsTestFactory.diagnostics()
        let pasteboard = SettingsRecordingPasteboard()
        let support = SettingsSupportInfo(email: "not-an-email")
        let model = SettingsTestFactory.viewModel(
            diagnostics: fixture.service,
            pasteboard: pasteboard,
            support: support
        )

        model.copySupportEmail()

        XCTAssertTrue(pasteboard.copied.isEmpty)
        XCTAssertEqual(model.notice?.kind, .error)
    }

    func testNoticeCanBeDismissed() async {
        let fixture = SettingsTestFactory.diagnostics()
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service)
        await model.load()
        model.copyDiagnosticCode()
        XCTAssertNotNil(model.notice)

        model.dismissNotice()
        XCTAssertNil(model.notice)
    }

    // MARK: Deletion state machine

    func testTwoStepConfirmationCanBeCancelledAndReversed() async {
        let fixture = SettingsTestFactory.diagnostics()
        let deleter = SettingsSequenceDeleter(reports: [SettingsTestFactory.report()])
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service, deleter: deleter)
        await model.load()

        XCTAssertTrue(model.canDeleteData)
        model.requestDelete()
        XCTAssertEqual(model.deleteStage, .firstConfirmation)
        XCTAssertFalse(model.canDeleteData)

        model.continueDelete()
        XCTAssertEqual(model.deleteStage, .finalConfirmation)

        model.backToDeleteOverview()
        XCTAssertEqual(model.deleteStage, .firstConfirmation)

        model.continueDelete()
        model.cancelDelete()
        XCTAssertEqual(model.deleteStage, .idle)

        let callCount = await deleter.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testDeletionCannotStartWithoutTheFinalConfirmation() async {
        let fixture = SettingsTestFactory.diagnostics()
        let deleter = SettingsSequenceDeleter(reports: [SettingsTestFactory.report()])
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service, deleter: deleter)
        await model.load()

        model.beginDeletion()
        XCTAssertEqual(model.deleteStage, .idle)

        model.requestDelete()
        model.beginDeletion()
        XCTAssertEqual(model.deleteStage, .firstConfirmation)

        await model.performDeletion()
        XCTAssertEqual(model.deleteStage, .firstConfirmation)

        let callCount = await deleter.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testDeletionBeforeLoadAndTwiceAfterSuccessIsIgnored() async {
        let fixture = SettingsTestFactory.diagnostics()
        let deleter = SettingsSequenceDeleter(reports: [SettingsTestFactory.report()])
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service, deleter: deleter)

        model.requestDelete()
        XCTAssertEqual(model.deleteStage, .idle)

        await model.load()
        model.requestDelete()
        model.continueDelete()
        await model.confirmDeletion()
        XCTAssertEqual(model.deleteStage, .deleted)

        model.requestDelete()
        XCTAssertEqual(model.deleteStage, .deleted)
    }

    func testCompleteDeletionVerifiesEmptyStoresAndRequestsOnboarding() async throws {
        let temporary = try TemporaryDirectory(prefix: "SettingsModel")
        defer { temporary.remove() }
        let appSupport = temporary.url.appendingPathComponent("StyleTone", isDirectory: true)
        let caches = temporary.url.appendingPathComponent("Caches", isDirectory: true)
        let tempExport = temporary.url.appendingPathComponent("Temp", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appSupport.appendingPathComponent("style-profiles", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: caches.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: tempExport, withIntermediateDirectories: true)
        try Data("profile".utf8).write(
            to: appSupport.appendingPathComponent("style-profiles/profile.json")
        )
        try Data("cached".utf8).write(to: caches.appendingPathComponent("images/thumb.jpg"))
        try Data("export".utf8).write(to: tempExport.appendingPathComponent("export.heic"))

        let fixture = SettingsTestFactory.diagnostics(
            enabled: true,
            entries: [SettingsTestFactory.entry(.appLaunch)]
        )
        let localPreferences = InMemorySettingsLocalPreferences()
        let coordinator = SettingsDataDeletionCoordinator(
            profileStore: MockStyleProfileStore(),
            diagnostics: fixture.service,
            preferences: localPreferences,
            locations: SettingsDataDeletionLocations(
                appSupportDirectory: appSupport,
                cachesDirectory: caches,
                temporaryDirectory: tempExport
            ),
            fileSystem: LocalSettingsDataFileSystem(),
            dateProvider: FixedDateProvider(SettingsTestFactory.referenceDate)
        )
        let model = SettingsTestFactory.viewModel(
            diagnostics: fixture.service,
            deleter: coordinator
        )
        await model.load()
        XCTAssertTrue(model.isDiagnosticsEnabled)

        model.requestDelete()
        model.continueDelete()
        await model.confirmDeletion()

        XCTAssertEqual(model.deleteStage, .deleted)
        XCTAssertTrue(model.requiresOnboarding)
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.deletionReport?.isComplete == true)
        XCTAssertEqual(model.notice?.text, SettingsCopy.deleteNoticeDeleted.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appSupport.path))
        let cached = try FileManager.default.contentsOfDirectory(
            at: caches,
            includingPropertiesForKeys: nil,
            options: []
        )
        XCTAssertTrue(cached.isEmpty)
        let remaining = try FileManager.default.contentsOfDirectory(
            at: tempExport,
            includingPropertiesForKeys: nil,
            options: []
        )
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertFalse(model.isDiagnosticsEnabled)
        XCTAssertEqual(model.diagnosticEntryCount, 0)
        XCTAssertFalse(model.canDeleteData)
    }

    func testPartialDeletionCanBeRetried() async {
        let failure = SettingsTestFactory.report(
            failures: [.profilesAndEdits: .profileDeletionFailed]
        )
        let success = SettingsTestFactory.report()
        let deleter = SettingsSequenceDeleter(reports: [failure, success])
        let fixture = SettingsTestFactory.diagnostics()
        let model = SettingsTestFactory.viewModel(diagnostics: fixture.service, deleter: deleter)
        await model.load()

        model.requestDelete()
        model.continueDelete()
        await model.confirmDeletion()

        XCTAssertEqual(model.deleteStage, .failed)
        XCTAssertFalse(model.requiresOnboarding)
        XCTAssertEqual(model.deletionReport?.failures[.profilesAndEdits], .profileDeletionFailed)
        XCTAssertNotNil(model.deleteFailureText)
        XCTAssertEqual(model.notice?.kind, .error)

        await model.retryDeletion()

        XCTAssertEqual(model.deleteStage, .deleted)
        XCTAssertTrue(model.requiresOnboarding)
        XCTAssertEqual(model.notice?.kind, .success)
        let callCount = await deleter.callCount
        XCTAssertEqual(callCount, 2)
    }
}
