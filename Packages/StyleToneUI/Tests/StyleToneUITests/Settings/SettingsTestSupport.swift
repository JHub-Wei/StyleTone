import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

// MARK: - Fixtures

enum SettingsTestError: Error, Sendable {
    case fileOperation
}

enum SettingsTestFactory {
    /// 2026-01-01T00:00:00Z, the project reference date.
    static let referenceDate = FixedDateProvider.reference

    static let version = SettingsVersionInfo(
        marketingVersion: "1.2.3",
        buildNumber: "45",
        platform: "iOS",
        osVersion: "17.4"
    )

    static func entry(
        _ kind: SettingsDiagnosticEventKind,
        code: String? = nil,
        at date: Date = referenceDate
    ) -> SettingsDiagnosticEntry {
        SettingsDiagnosticEntry(
            kind: kind,
            code: code,
            recordedAt: date,
            appVersion: version.marketingVersion,
            buildNumber: version.buildNumber,
            platform: version.platform,
            osVersion: version.osVersion
        )
    }

    struct DiagnosticsFixture: Sendable {
        let service: SettingsDiagnosticsService
        let preferences: InMemorySettingsDiagnosticsPreferences
        let logStore: InMemorySettingsDiagnosticsLogStore
    }

    static func diagnostics(
        enabled: Bool = false,
        entries: [SettingsDiagnosticEntry] = [],
        preferences: InMemorySettingsDiagnosticsPreferences? = nil,
        logStore: InMemorySettingsDiagnosticsLogStore? = nil,
        maximumEntries: Int = SettingsDiagnosticsLimits.maximumEntries
    ) -> DiagnosticsFixture {
        let resolvedPreferences = preferences ?? InMemorySettingsDiagnosticsPreferences(enabled: enabled)
        let resolvedLogStore = logStore ?? InMemorySettingsDiagnosticsLogStore(entries: entries)
        let service = SettingsDiagnosticsService(
            preferences: resolvedPreferences,
            store: resolvedLogStore,
            versionProvider: StaticSettingsVersionProvider(version),
            dateProvider: FixedDateProvider(referenceDate),
            maximumEntries: maximumEntries
        )
        return DiagnosticsFixture(
            service: service,
            preferences: resolvedPreferences,
            logStore: resolvedLogStore
        )
    }

    static func report(
        failures: [SettingsLocalDataComponent: SettingsLocalDataDeletionFailure] = [:],
        at date: Date = referenceDate
    ) -> SettingsLocalDataDeletionReport {
        let completed = SettingsLocalDataComponent.allCases.filter { failures[$0] == nil }
        return SettingsLocalDataDeletionReport(
            completedComponents: completed,
            failures: failures,
            finishedAt: date
        )
    }

    @MainActor
    static func dependencies(
        diagnostics: any SettingsDiagnosticsControlling,
        deleter: any SettingsLocalDataDeleting,
        pasteboard: any SettingsPasteboardWriting,
        support: SettingsSupportInfo = .placeholder,
        version: SettingsVersionInfo = SettingsTestFactory.version,
        licenses: SettingsLicenseCatalog = .standard
    ) -> SettingsDependencies {
        SettingsDependencies(
            diagnostics: diagnostics,
            dataDeleter: deleter,
            versionProvider: StaticSettingsVersionProvider(version),
            licenseProvider: StaticSettingsLicenseProvider(licenses),
            support: support,
            pasteboard: pasteboard,
            dateProvider: FixedDateProvider(referenceDate)
        )
    }

    @MainActor
    static func viewModel(
        diagnostics: any SettingsDiagnosticsControlling,
        deleter: any SettingsLocalDataDeleting = InMemorySettingsLocalDataDeleter(
            dateProvider: FixedDateProvider(referenceDate)
        ),
        pasteboard: SettingsRecordingPasteboard = SettingsRecordingPasteboard(),
        support: SettingsSupportInfo = .placeholder,
        version: SettingsVersionInfo = SettingsTestFactory.version,
        licenses: SettingsLicenseCatalog = .standard
    ) -> SettingsViewModel {
        SettingsViewModel(
            dependencies: dependencies(
                diagnostics: diagnostics,
                deleter: deleter,
                pasteboard: pasteboard,
                support: support,
                version: version,
                licenses: licenses
            )
        )
    }
}

// MARK: - Doubles

/// Pasteboard double; never touches the simulator pasteboard.
@MainActor
final class SettingsRecordingPasteboard: SettingsPasteboardWriting {
    var copied: [String] = []
    var succeeds = true

    func copy(_ text: String) -> Bool {
        copied.append(text)
        return succeeds
    }
}

/// Returns queued reports in order.
actor SettingsSequenceDeleter: SettingsLocalDataDeleting {
    private var reports: [SettingsLocalDataDeletionReport]
    private(set) var callCount = 0

    init(reports: [SettingsLocalDataDeletionReport]) {
        self.reports = reports
    }

    func deleteAllLocalData() async -> SettingsLocalDataDeletionReport {
        callCount += 1
        guard !reports.isEmpty else {
            return SettingsTestFactory.report()
        }
        return reports.removeFirst()
    }
}

/// Diagnostics clearer that always fails.
struct SettingsFailingDiagnosticsClearer: SettingsDiagnosticsDataClearing {
    var error: SettingsDiagnosticsError = .logUnavailable

    func deleteDiagnosticData() async throws {
        throw error
    }
}

/// File-system double for residue and failure paths.
struct SettingsStubFileSystem: SettingsDataFileSystem {
    var failRemoval = false
    var appSupportResidue = false
    var directoryResidue = false

    func exists(_ url: URL) -> Bool {
        appSupportResidue
    }

    func remove(_ url: URL) throws {
        if failRemoval {
            throw SettingsTestError.fileOperation
        }
    }

    func removeContents(of directory: URL) throws {
        if failRemoval {
            throw SettingsTestError.fileOperation
        }
    }

    func directoryIsEmpty(_ directory: URL) -> Bool {
        !directoryResidue
    }
}
