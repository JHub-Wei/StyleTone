import Foundation
import StyleToneUI
import TestShared
import XCTest

final class SettingsDiagnosticsTests: XCTestCase {
    // MARK: Opt-in gate

    func testDiagnosticsAreOffByDefault() async {
        let fixture = SettingsTestFactory.diagnostics()
        let snapshot = await fixture.service.snapshot()

        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertTrue(SettingsDiagnosticCode.isWellFormed(snapshot.code))
        let saveCount = await fixture.logStore.saveCount
        XCTAssertEqual(saveCount, 0)
    }

    func testRecordWhileOffCollectsNothing() async {
        let fixture = SettingsTestFactory.diagnostics()
        await fixture.service.record(SettingsDiagnosticEvent(kind: .appLaunch))
        await fixture.service.record(SettingsDiagnosticEvent(kind: .exportSucceeded))

        let snapshot = await fixture.service.snapshot()
        XCTAssertTrue(snapshot.entries.isEmpty)
        let saveCount = await fixture.logStore.saveCount
        XCTAssertEqual(saveCount, 0)
    }

    func testEnablingPersistsAndRecordsWhitelistedEvents() async throws {
        let fixture = SettingsTestFactory.diagnostics()
        let enabled = try await fixture.service.setEnabled(true)
        XCTAssertTrue(enabled.isEnabled)

        await fixture.service.record(
            SettingsDiagnosticEvent(kind: .exportFailed, code: "E_EXPORT")
        )
        let snapshot = await fixture.service.snapshot()
        XCTAssertTrue(snapshot.isEnabled)
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.entries.first?.kind, .exportFailed)
        XCTAssertEqual(snapshot.entries.first?.code, "E_EXPORT")

        let stored = await fixture.preferences.currentValue()
        XCTAssertTrue(stored)
    }

    func testDisablingStopsCollectionAndClearsTheLog() async throws {
        let fixture = SettingsTestFactory.diagnostics()
        _ = try await fixture.service.setEnabled(true)
        await fixture.service.record(SettingsDiagnosticEvent(kind: .appLaunch))
        let before = await fixture.service.snapshot()
        XCTAssertEqual(before.entries.count, 1)

        let disabled = try await fixture.service.setEnabled(false)
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertTrue(disabled.entries.isEmpty)

        await fixture.service.record(SettingsDiagnosticEvent(kind: .appForeground))
        let after = await fixture.service.snapshot()
        XCTAssertTrue(after.entries.isEmpty)
        XCTAssertFalse(after.isEnabled)

        let clearCount = await fixture.logStore.clearCount
        XCTAssertGreaterThanOrEqual(clearCount, 1)
    }

    func testRestartKeepsOptInAndBoundedEntries() async throws {
        let fixture = SettingsTestFactory.diagnostics()
        _ = try await fixture.service.setEnabled(true)
        await fixture.service.record(SettingsDiagnosticEvent(kind: .settingsOpened))

        let restarted = SettingsDiagnosticsService(
            preferences: fixture.preferences,
            store: fixture.logStore,
            versionProvider: StaticSettingsVersionProvider(SettingsTestFactory.version),
            dateProvider: FixedDateProvider(SettingsTestFactory.referenceDate)
        )
        let snapshot = await restarted.snapshot()
        XCTAssertTrue(snapshot.isEnabled)
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.entries.first?.kind, .settingsOpened)
    }

    func testEnablingFailureLeavesDiagnosticsOff() async {
        let preferences = InMemorySettingsDiagnosticsPreferences(setError: .preferenceUnavailable)
        let fixture = SettingsTestFactory.diagnostics(preferences: preferences)

        do {
            _ = try await fixture.service.setEnabled(true)
            XCTFail("expected preference failure")
        } catch {
            XCTAssertEqual(error as? SettingsDiagnosticsError, .preferenceUnavailable)
        }

        let snapshot = await fixture.service.snapshot()
        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertTrue(snapshot.entries.isEmpty)
    }

    func testDisablingFailureStillStopsCollectionButReportsTheLogProblem() async {
        let logStore = InMemorySettingsDiagnosticsLogStore(clearError: .logUnavailable)
        let preferences = InMemorySettingsDiagnosticsPreferences(enabled: true)
        let fixture = SettingsTestFactory.diagnostics(
            preferences: preferences,
            logStore: logStore
        )

        do {
            _ = try await fixture.service.setEnabled(false)
            XCTFail("expected log failure")
        } catch {
            XCTAssertEqual(error as? SettingsDiagnosticsError, .logUnavailable)
        }

        let snapshot = await fixture.service.snapshot()
        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertTrue(snapshot.entries.isEmpty)
        let stored = await preferences.currentValue()
        XCTAssertFalse(stored)
    }

    func testOrphanedEntriesAreClearedWhenOptInIsOff() async {
        let orphan = SettingsTestFactory.entry(.appLaunch)
        let fixture = SettingsTestFactory.diagnostics(enabled: false, entries: [orphan])

        let snapshot = await fixture.service.snapshot()
        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertTrue(snapshot.entries.isEmpty)

        let clearCount = await fixture.logStore.clearCount
        XCTAssertEqual(clearCount, 1)
    }

    func testRingKeepsNewestEntries() async {
        let fixture = SettingsTestFactory.diagnostics(enabled: true, maximumEntries: 3)
        let kinds: [SettingsDiagnosticEventKind] = [
            .appLaunch,
            .appForeground,
            .settingsOpened,
            .exportSucceeded,
            .exportFailed,
        ]
        for kind in kinds {
            await fixture.service.record(SettingsDiagnosticEvent(kind: kind))
        }

        let snapshot = await fixture.service.snapshot()
        XCTAssertEqual(snapshot.entries.map(\.kind), Array(kinds.suffix(3)))
    }

    func testClearRemovesEntriesButKeepsOptIn() async throws {
        let fixture = SettingsTestFactory.diagnostics()
        _ = try await fixture.service.setEnabled(true)
        await fixture.service.record(SettingsDiagnosticEvent(kind: .appLaunch))

        let snapshot = try await fixture.service.clear()
        XCTAssertTrue(snapshot.isEnabled)
        XCTAssertTrue(snapshot.entries.isEmpty)
    }

    func testDeleteDiagnosticDataClearsPreferencesAndLog() async throws {
        let fixture = SettingsTestFactory.diagnostics()
        _ = try await fixture.service.setEnabled(true)
        await fixture.service.record(SettingsDiagnosticEvent(kind: .appLaunch))

        try await fixture.service.deleteDiagnosticData()

        let snapshot = await fixture.service.snapshot()
        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertTrue(snapshot.entries.isEmpty)

        let preferred = await fixture.preferences.currentValue()
        XCTAssertFalse(preferred)
        let preferenceClearCount = await fixture.preferences.clearCount
        XCTAssertEqual(preferenceClearCount, 1)
        let logClearCount = await fixture.logStore.clearCount
        XCTAssertGreaterThanOrEqual(logClearCount, 1)
    }

    // MARK: Diagnostic code

    func testCodeEmbedsOnlyBuildAndStateInformation() {
        let off = SettingsDiagnosticCode.make(
            version: SettingsTestFactory.version,
            isEnabled: false,
            entryCount: 0
        )
        let on = SettingsDiagnosticCode.make(
            version: SettingsTestFactory.version,
            isEnabled: true,
            entryCount: 7
        )

        XCTAssertTrue(SettingsDiagnosticCode.isWellFormed(off), off)
        XCTAssertTrue(SettingsDiagnosticCode.isWellFormed(on), on)
        XCTAssertTrue(off.contains("ST21-1.2.3-45-iOS17-OFF-0-"))
        XCTAssertTrue(on.contains("ST21-1.2.3-45-iOS17-ON-7-"))
        XCTAssertNotEqual(off, on)
        XCTAssertLessThanOrEqual(on.count, SettingsDiagnosticCode.maximumLength)
    }

    func testCodeIsDeterministicAndSanitized() {
        let first = SettingsDiagnosticCode.make(
            version: SettingsTestFactory.version,
            isEnabled: true,
            entryCount: 2
        )
        let second = SettingsDiagnosticCode.make(
            version: SettingsTestFactory.version,
            isEnabled: true,
            entryCount: 2
        )
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.contains("@"))
        XCTAssertFalse(first.contains("/"))
        XCTAssertFalse(first.contains(" "))

        let hostile = SettingsVersionInfo(
            marketingVersion: "1.2 beta/../..",
            buildNumber: "4 5",
            platform: "iOS",
            osVersion: "17.4"
        )
        let code = SettingsDiagnosticCode.make(
            version: hostile,
            isEnabled: false,
            entryCount: 0
        )
        XCTAssertTrue(SettingsDiagnosticCode.isWellFormed(code), code)
        XCTAssertFalse(code.contains(" "))
        XCTAssertFalse(code.contains("/"))
    }

    func testCodeCountIsClamped() {
        let code = SettingsDiagnosticCode.make(
            version: SettingsTestFactory.version,
            isEnabled: true,
            entryCount: 1_000_000
        )
        XCTAssertTrue(code.contains("99999"))
        XCTAssertTrue(SettingsDiagnosticCode.isWellFormed(code))
    }

    // MARK: Event sanitisation

    func testOnlyBoundedErrorCodesAreAccepted() {
        XCTAssertEqual(
            SettingsDiagnosticEvent(kind: .exportFailed, code: "E_EXPORT").code,
            "E_EXPORT"
        )
        XCTAssertNil(SettingsDiagnosticEvent(kind: .exportFailed, code: "photo.jpg").code)
        XCTAssertNil(SettingsDiagnosticEvent(kind: .exportFailed, code: "/tmp/E_EXPORT").code)
        XCTAssertNil(SettingsDiagnosticEvent(kind: .exportFailed, code: "user@example.com").code)
        XCTAssertNil(SettingsDiagnosticEvent(kind: .exportFailed, code: "e_export").code)
        XCTAssertNil(SettingsDiagnosticEvent(kind: .exportFailed, code: "E EXPORT").code)
        XCTAssertNil(SettingsDiagnosticEvent(kind: .exportFailed, code: "E").code)
        XCTAssertNil(SettingsDiagnosticEvent(kind: .exportFailed, code: String(repeating: "A", count: 33)).code)
        XCTAssertTrue(SettingsDiagnosticEvent.isValidCode("E_STATE"))
        XCTAssertFalse(SettingsDiagnosticEvent.isValidCode("E_STATE\n"))
    }

    // MARK: File store

    func testFileStoreRoundTripsAndStaysFreeOfUserData() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync(prefix: "SettingsLog") { directory in
            let store = FileSettingsDiagnosticsLogStore(directory: directory)
            let entries = [
                SettingsTestFactory.entry(.appLaunch),
                SettingsTestFactory.entry(.exportFailed, code: "E_EXPORT"),
            ]
            try await store.save(entries)

            let loaded = await store.load()
            XCTAssertEqual(loaded, entries)

            let data = try Data(contentsOf: store.logFileURL)
            let text = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertTrue(text.contains("export.failed"))
            XCTAssertTrue(text.contains("E_EXPORT"))
            XCTAssertFalse(text.contains("DCIM"))
            XCTAssertFalse(text.contains("/Users"))
            XCTAssertFalse(text.contains("@"))
        }
    }

    func testFileStoreIgnoresCorruptAndOversizedFiles() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync(prefix: "SettingsLog") { directory in
            let store = FileSettingsDiagnosticsLogStore(directory: directory)
            let url = store.logFileURL

            try Data("not json".utf8).write(to: url)
            let corrupt = await store.load()
            XCTAssertTrue(corrupt.isEmpty)

            try Data(repeating: 0, count: SettingsDiagnosticsLimits.maximumFileSize + 1).write(to: url)
            let oversized = await store.load()
            XCTAssertTrue(oversized.isEmpty)
        }
    }

    func testFileStoreCapsEntriesAndRemovesTheFile() async throws {
        try await TemporaryDirectory.withTemporaryDirectoryAsync(prefix: "SettingsLog") { directory in
            let store = FileSettingsDiagnosticsLogStore(directory: directory, maximumEntries: 2)
            let entries = (0..<5).map { index in
                SettingsTestFactory.entry(
                    index.isMultiple(of: 2) ? .appLaunch : .appForeground
                )
            }
            try await store.save(entries)

            let loaded = await store.load()
            XCTAssertEqual(loaded, Array(entries.suffix(2)))

            try await store.clear()
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.logFileURL.path))
        }
    }

    func testDefaultLogDirectoryIsInsideTheAppSandbox() throws {
        let directory = try XCTUnwrap(FileSettingsDiagnosticsLogStore.defaultDirectory())
        XCTAssertEqual(directory.lastPathComponent, "Diagnostics")
        XCTAssertEqual(directory.deletingLastPathComponent().lastPathComponent, "StyleTone")
    }
}
