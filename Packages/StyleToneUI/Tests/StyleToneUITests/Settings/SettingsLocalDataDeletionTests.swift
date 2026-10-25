import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

final class SettingsLocalDataDeletionTests: XCTestCase {
    // MARK: Complete path

    func testCompleteDeletionRemovesAndVerifiesEverything() async throws {
        let temporary = try TemporaryDirectory(prefix: "SettingsDeletion")
        defer { temporary.remove() }
        let layout = try makeLayout(in: temporary.url)

        let profileStore = MockStyleProfileStore()
        let diagnosticsFixture = SettingsTestFactory.diagnostics(
            enabled: true,
            entries: [SettingsTestFactory.entry(.appLaunch)]
        )
        let localPreferences = InMemorySettingsLocalPreferences()
        let coordinator = SettingsDataDeletionCoordinator(
            profileStore: profileStore,
            diagnostics: diagnosticsFixture.service,
            preferences: localPreferences,
            locations: layout.locations,
            fileSystem: LocalSettingsDataFileSystem(),
            dateProvider: FixedDateProvider(SettingsTestFactory.referenceDate)
        )

        let report = await coordinator.deleteAllLocalData()

        XCTAssertTrue(report.isComplete)
        XCTAssertTrue(report.requiresOnboarding)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(report.completedComponents, SettingsLocalDataComponent.allCases)
        XCTAssertEqual(report.finishedAt, SettingsTestFactory.referenceDate)

        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.appSupport.path))
        XCTAssertTrue(try contents(of: layout.caches).isEmpty)
        XCTAssertTrue(try contents(of: layout.temporary).isEmpty)

        let deleteCount = await profileStore.deleteCount
        let loadCount = await profileStore.loadCount
        XCTAssertEqual(deleteCount, 1)
        XCTAssertEqual(loadCount, 1)

        let diagnostics = await diagnosticsFixture.service.snapshot()
        XCTAssertFalse(diagnostics.isEnabled)
        XCTAssertTrue(diagnostics.entries.isEmpty)

        let preferenceClearCount = await localPreferences.clearCount
        XCTAssertEqual(preferenceClearCount, 1)
    }

    func testRelaunchAfterDeletionStartsWithNoProfileOrDiagnostics() async throws {
        let temporary = try TemporaryDirectory(prefix: "SettingsDeletion")
        defer { temporary.remove() }
        let layout = try makeLayout(in: temporary.url)
        let profileStore = MockStyleProfileStore(profile: .neutral())
        let diagnosticsFixture = SettingsTestFactory.diagnostics(
            enabled: true,
            entries: [SettingsTestFactory.entry(.appLaunch)]
        )
        let coordinator = SettingsDataDeletionCoordinator(
            profileStore: profileStore,
            diagnostics: diagnosticsFixture.service,
            preferences: InMemorySettingsLocalPreferences(),
            locations: layout.locations,
            fileSystem: LocalSettingsDataFileSystem(),
            dateProvider: FixedDateProvider(SettingsTestFactory.referenceDate)
        )

        let report = await coordinator.deleteAllLocalData()
        XCTAssertTrue(report.requiresOnboarding)

        let activeProfile = try await profileStore.loadActive()
        XCTAssertNil(activeProfile)

        let restartedDiagnostics = SettingsDiagnosticsService(
            preferences: diagnosticsFixture.preferences,
            store: diagnosticsFixture.logStore,
            versionProvider: StaticSettingsVersionProvider(SettingsTestFactory.version),
            dateProvider: FixedDateProvider(SettingsTestFactory.referenceDate)
        )
        let diagnostics = await restartedDiagnostics.snapshot()
        XCTAssertFalse(diagnostics.isEnabled)
        XCTAssertTrue(diagnostics.entries.isEmpty)
    }

    func testSecondDeletionIsIdempotent() async throws {
        let temporary = try TemporaryDirectory(prefix: "SettingsDeletion")
        defer { temporary.remove() }
        let layout = try makeLayout(in: temporary.url)
        let profileStore = MockStyleProfileStore()
        let diagnosticsFixture = SettingsTestFactory.diagnostics(enabled: true)
        let coordinator = SettingsDataDeletionCoordinator(
            profileStore: profileStore,
            diagnostics: diagnosticsFixture.service,
            preferences: InMemorySettingsLocalPreferences(),
            locations: layout.locations,
            fileSystem: LocalSettingsDataFileSystem(),
            dateProvider: FixedDateProvider(SettingsTestFactory.referenceDate)
        )

        let first = await coordinator.deleteAllLocalData()
        let second = await coordinator.deleteAllLocalData()
        XCTAssertTrue(first.isComplete)
        XCTAssertTrue(second.isComplete)
        XCTAssertEqual(second.completedComponents, SettingsLocalDataComponent.allCases)
    }

    // MARK: Failure paths

    func testProfileDeletionFailureIsReportedWithoutAFalseSuccess() async throws {
        let temporary = try TemporaryDirectory(prefix: "SettingsDeletion")
        defer { temporary.remove() }
        let layout = try makeLayout(in: temporary.url)
        let profileStore = MockStyleProfileStore(deleteError: .persistenceFailed)
        let coordinator = SettingsDataDeletionCoordinator(
            profileStore: profileStore,
            diagnostics: SettingsTestFactory.diagnostics(enabled: true).service,
            preferences: InMemorySettingsLocalPreferences(),
            locations: layout.locations,
            fileSystem: LocalSettingsDataFileSystem(),
            dateProvider: FixedDateProvider(SettingsTestFactory.referenceDate)
        )

        let report = await coordinator.deleteAllLocalData()

        XCTAssertFalse(report.isComplete)
        XCTAssertFalse(report.requiresOnboarding)
        XCTAssertEqual(report.failures[.profilesAndEdits], .profileDeletionFailed)
        XCTAssertEqual(report.failedComponents, [.profilesAndEdits])
        XCTAssertEqual(
            report.completedComponents,
            SettingsLocalDataComponent.allCases.filter { $0 != .profilesAndEdits }
        )
    }

    func testDiagnosticsDeletionFailureIsReported() async throws {
        let temporary = try TemporaryDirectory(prefix: "SettingsDeletion")
        defer { temporary.remove() }
        let layout = try makeLayout(in: temporary.url)
        let coordinator = SettingsDataDeletionCoordinator(
            profileStore: MockStyleProfileStore(),
            diagnostics: SettingsFailingDiagnosticsClearer(),
            preferences: InMemorySettingsLocalPreferences(),
            locations: layout.locations,
            fileSystem: LocalSettingsDataFileSystem(),
            dateProvider: FixedDateProvider(SettingsTestFactory.referenceDate)
        )

        let report = await coordinator.deleteAllLocalData()

        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.failures[.diagnostics], .diagnosticsDeletionFailed)
        XCTAssertEqual(report.failedComponents, [.diagnostics])
    }

    func testPreferencesDeletionFailureIsReported() async throws {
        let temporary = try TemporaryDirectory(prefix: "SettingsDeletion")
        defer { temporary.remove() }
        let layout = try makeLayout(in: temporary.url)
        let coordinator = SettingsDataDeletionCoordinator(
            profileStore: MockStyleProfileStore(),
            diagnostics: SettingsTestFactory.diagnostics().service,
            preferences: InMemorySettingsLocalPreferences(clearError: .preferenceUnavailable),
            locations: layout.locations,
            fileSystem: LocalSettingsDataFileSystem(),
            dateProvider: FixedDateProvider(SettingsTestFactory.referenceDate)
        )

        let report = await coordinator.deleteAllLocalData()

        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.failures[.preferences], .preferencesDeletionFailed)
    }

    func testFileRemovalFailureIsReportedForEveryDirectory() async throws {
        let temporary = try TemporaryDirectory(prefix: "SettingsDeletion")
        defer { temporary.remove() }
        let layout = try makeLayout(in: temporary.url)
        let coordinator = SettingsDataDeletionCoordinator(
            profileStore: MockStyleProfileStore(),
            diagnostics: SettingsTestFactory.diagnostics().service,
            preferences: InMemorySettingsLocalPreferences(),
            locations: layout.locations,
            fileSystem: SettingsStubFileSystem(failRemoval: true),
            dateProvider: FixedDateProvider(SettingsTestFactory.referenceDate)
        )

        let report = await coordinator.deleteAllLocalData()

        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.failures[.appFiles], .fileDeletionFailed)
        XCTAssertEqual(report.failures[.caches], .fileDeletionFailed)
        XCTAssertEqual(report.failures[.temporaryFiles], .fileDeletionFailed)
    }

    func testFileResidueIsReported() async throws {
        let temporary = try TemporaryDirectory(prefix: "SettingsDeletion")
        defer { temporary.remove() }
        let layout = try makeLayout(in: temporary.url)
        let coordinator = SettingsDataDeletionCoordinator(
            profileStore: MockStyleProfileStore(),
            diagnostics: SettingsTestFactory.diagnostics().service,
            preferences: InMemorySettingsLocalPreferences(),
            locations: layout.locations,
            fileSystem: SettingsStubFileSystem(
                appSupportResidue: true,
                directoryResidue: true
            ),
            dateProvider: FixedDateProvider(SettingsTestFactory.referenceDate)
        )

        let report = await coordinator.deleteAllLocalData()

        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.failures[.appFiles], .fileResidue)
        XCTAssertEqual(report.failures[.caches], .fileResidue)
        XCTAssertEqual(report.failures[.temporaryFiles], .fileResidue)
    }

    // MARK: Locations and report

    func testStandardLocationsPointAtStyleToneFolders() throws {
        let locations = try XCTUnwrap(SettingsDataDeletionLocations.standard())
        XCTAssertEqual(locations.appSupportDirectory.lastPathComponent, "StyleTone")
        XCTAssertTrue(locations.cachesDirectory.pathExtension.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.cachesDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.temporaryDirectory.path))
    }

    func testCompleteReportIsTheOnlyStateThatRequiresOnboarding() {
        let complete = SettingsTestFactory.report()
        XCTAssertTrue(complete.isComplete)
        XCTAssertTrue(complete.requiresOnboarding)
        XCTAssertTrue(complete.failedComponents.isEmpty)

        let partial = SettingsTestFactory.report(failures: [.appFiles: .fileResidue])
        XCTAssertFalse(partial.isComplete)
        XCTAssertFalse(partial.requiresOnboarding)
        XCTAssertEqual(partial.failedComponents, [.appFiles])
    }

    // MARK: Helpers

    private struct Layout {
        let locations: SettingsDataDeletionLocations
        let appSupport: URL
        let caches: URL
        let temporary: URL
    }

    private func makeLayout(in root: URL) throws -> Layout {
        let appSupport = root
            .appendingPathComponent("AppSupport", isDirectory: true)
            .appendingPathComponent("StyleTone", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("Temp", isDirectory: true)

        try createDirectory(appSupport.appendingPathComponent("style-profiles", isDirectory: true))
        try createDirectory(appSupport.appendingPathComponent("style-thumbnails", isDirectory: true))
        try createDirectory(appSupport.appendingPathComponent("Calibration", isDirectory: true))
        try createDirectory(appSupport.appendingPathComponent("Diagnostics", isDirectory: true))
        try createDirectory(caches.appendingPathComponent("images", isDirectory: true))
        try createDirectory(temporary.appendingPathComponent("nested", isDirectory: true))

        try Data("profile".utf8).write(
            to: appSupport.appendingPathComponent("style-profiles/profile.json")
        )
        try Data("thumbnail".utf8).write(
            to: appSupport.appendingPathComponent("style-thumbnails/profile.jpg")
        )
        try Data("draft".utf8).write(
            to: appSupport.appendingPathComponent("Calibration/calibration-progress.json")
        )
        try Data("log".utf8).write(
            to: appSupport.appendingPathComponent("Diagnostics/diagnostics.json")
        )
        try Data("cached-image".utf8).write(
            to: caches.appendingPathComponent("images/thumb.jpg")
        )
        try Data("export".utf8).write(to: temporary.appendingPathComponent("export.heic"))
        try Data("cache".utf8).write(
            to: temporary.appendingPathComponent("nested/cache.bin")
        )

        return Layout(
            locations: SettingsDataDeletionLocations(
                appSupportDirectory: appSupport,
                cachesDirectory: caches,
                temporaryDirectory: temporary
            ),
            appSupport: appSupport,
            caches: caches,
            temporary: temporary
        )
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    private func contents(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )
    }
}
