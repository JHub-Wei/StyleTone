import Foundation
import StyleToneCore

// MARK: - Report

/// One part of the local data that "Delete all local data" removes.
public enum SettingsLocalDataComponent: String, CaseIterable, Sendable, Hashable {
    /// Style profiles, edits, pair sessions and quota, through WP-08's
    /// `StyleProfileStore.deleteAll()`.
    case profilesAndEdits
    /// The local diagnostic log.
    case diagnostics
    /// App preferences, including first-run/onboarding state and the
    /// diagnostics opt-in.
    case preferences
    /// Remaining files under Application Support/StyleTone (calibration
    /// drafts, pairing metadata, thumbnails, caches and profile backups).
    case appFiles
    /// The app's Library/Caches contents (image/export caches and URL cache).
    case caches
    /// Temporary files created while exporting or rendering.
    case temporaryFiles
}

/// Why a component could not be deleted. Cases are path-free by design.
public enum SettingsLocalDataDeletionFailure: String, Error, Sendable, Hashable {
    case profileDeletionFailed
    case profileResidue
    case diagnosticsDeletionFailed
    case preferencesDeletionFailed
    case fileDeletionFailed
    case fileResidue
}

/// The result of a full local-data deletion.
///
/// ``isComplete`` is true only when every component was removed *and* verified
/// empty. The UI must never show a success state for a partial report.
public struct SettingsLocalDataDeletionReport: Sendable, Equatable {
    public let completedComponents: [SettingsLocalDataComponent]
    public let failures: [SettingsLocalDataComponent: SettingsLocalDataDeletionFailure]
    public let finishedAt: Date

    public init(
        completedComponents: [SettingsLocalDataComponent],
        failures: [SettingsLocalDataComponent: SettingsLocalDataDeletionFailure],
        finishedAt: Date
    ) {
        self.completedComponents = completedComponents
        self.failures = failures
        self.finishedAt = finishedAt
    }

    /// A report with every component deleted.
    public static func complete(at date: Date) -> SettingsLocalDataDeletionReport {
        SettingsLocalDataDeletionReport(
            completedComponents: SettingsLocalDataComponent.allCases,
            failures: [:],
            finishedAt: date
        )
    }

    public var isComplete: Bool {
        failures.isEmpty
            && Set(completedComponents) == Set(SettingsLocalDataComponent.allCases)
    }

    /// The host should show onboarding immediately after a complete deletion.
    ///
    /// A relaunch also lands on onboarding because the profile store and the
    /// preference domain are empty; this value is the immediate handoff signal.
    public var requiresOnboarding: Bool {
        isComplete
    }

    /// Components that were not deleted, in declaration order.
    public var failedComponents: [SettingsLocalDataComponent] {
        SettingsLocalDataComponent.allCases.filter { failures[$0] != nil }
    }
}

// MARK: - Protocols

/// Performs and verifies a complete local-data deletion.
public protocol SettingsLocalDataDeleting: Sendable {
    func deleteAllLocalData() async -> SettingsLocalDataDeletionReport
}

/// Narrow file-system boundary used by the deletion coordinator, so tests can
/// inject missing files, residue and failures without touching real paths.
public protocol SettingsDataFileSystem: Sendable {
    func exists(_ url: URL) -> Bool
    func remove(_ url: URL) throws
    func removeContents(of directory: URL) throws
    func directoryIsEmpty(_ directory: URL) -> Bool
}

/// File-system implementation used by the app.
public struct LocalSettingsDataFileSystem: SettingsDataFileSystem {
    public init() {}

    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func removeContents(of directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
    }

    public func directoryIsEmpty(_ directory: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else { return true }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        return contents.isEmpty
    }
}

// MARK: - Locations

/// The sandbox locations the deletion coordinator empties.
public struct SettingsDataDeletionLocations: Sendable, Equatable {
    /// `Application Support/StyleTone`: profiles, thumbnails, calibration,
    /// pairing metadata, diagnostics and migration/quarantine backups.
    public let appSupportDirectory: URL
    /// The app's Library/Caches directory, emptied but not removed.
    public let cachesDirectory: URL
    /// The app's temporary directory, emptied but not removed.
    public let temporaryDirectory: URL

    public init(
        appSupportDirectory: URL,
        cachesDirectory: URL,
        temporaryDirectory: URL
    ) {
        self.appSupportDirectory = appSupportDirectory
        self.cachesDirectory = cachesDirectory
        self.temporaryDirectory = temporaryDirectory
    }

    /// Standard sandbox locations, or `nil` when Application Support cannot be
    /// resolved. Callers should fail closed rather than delete a partial set.
    public static func standard(fileManager: FileManager = .default) -> SettingsDataDeletionLocations? {
        guard let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        guard let caches = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return SettingsDataDeletionLocations(
            appSupportDirectory: applicationSupport.appendingPathComponent("StyleTone", isDirectory: true),
            cachesDirectory: caches,
            temporaryDirectory: fileManager.temporaryDirectory
        )
    }
}

// MARK: - Coordinator

/// Deletes and verifies every local data store in a fixed order.
///
/// Order matters:
/// 1. WP-08's `deleteAll()` clears SwiftData and profile files.
/// 2. `loadActive()` verifies the store is empty.
/// 3. Diagnostics and preferences are cleared explicitly.
/// 4. The whole Application Support/StyleTone tree is removed, and the
///    caches and temporary directories are emptied, catching calibration
///    drafts, cache files and residues.
///
/// A failure in one component does not stop the others; the report keeps the
/// failure so the UI can offer a retry and avoid a false success.
public actor SettingsDataDeletionCoordinator: SettingsLocalDataDeleting {
    private let profileStore: any StyleProfileStore
    private let diagnostics: any SettingsDiagnosticsDataClearing
    private let preferences: any SettingsLocalPreferencesClearing
    private let locations: SettingsDataDeletionLocations
    private let fileSystem: any SettingsDataFileSystem
    private let dateProvider: any DateProviding

    public init(
        profileStore: any StyleProfileStore,
        diagnostics: any SettingsDiagnosticsDataClearing,
        preferences: any SettingsLocalPreferencesClearing,
        locations: SettingsDataDeletionLocations,
        fileSystem: any SettingsDataFileSystem = LocalSettingsDataFileSystem(),
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.profileStore = profileStore
        self.diagnostics = diagnostics
        self.preferences = preferences
        self.locations = locations
        self.fileSystem = fileSystem
        self.dateProvider = dateProvider
    }

    public func deleteAllLocalData() async -> SettingsLocalDataDeletionReport {
        var failures: [SettingsLocalDataComponent: SettingsLocalDataDeletionFailure] = [:]

        if let profileFailure = await deleteProfiles() {
            failures[.profilesAndEdits] = profileFailure
        }

        do {
            try await diagnostics.deleteDiagnosticData()
        } catch {
            failures[.diagnostics] = .diagnosticsDeletionFailed
        }

        do {
            try await preferences.clearLocalPreferences()
        } catch {
            failures[.preferences] = .preferencesDeletionFailed
        }

        do {
            try fileSystem.remove(locations.appSupportDirectory)
            if fileSystem.exists(locations.appSupportDirectory) {
                failures[.appFiles] = .fileResidue
            }
        } catch {
            failures[.appFiles] = .fileDeletionFailed
        }

        do {
            try fileSystem.removeContents(of: locations.cachesDirectory)
            if !fileSystem.directoryIsEmpty(locations.cachesDirectory) {
                failures[.caches] = .fileResidue
            }
        } catch {
            failures[.caches] = .fileDeletionFailed
        }

        do {
            try fileSystem.removeContents(of: locations.temporaryDirectory)
            if !fileSystem.directoryIsEmpty(locations.temporaryDirectory) {
                failures[.temporaryFiles] = .fileResidue
            }
        } catch {
            failures[.temporaryFiles] = .fileDeletionFailed
        }

        let completed = SettingsLocalDataComponent.allCases.filter { failures[$0] == nil }
        return SettingsLocalDataDeletionReport(
            completedComponents: completed,
            failures: failures,
            finishedAt: dateProvider.now
        )
    }

    // MARK: Private

    private func deleteProfiles() async -> SettingsLocalDataDeletionFailure? {
        do {
            try await profileStore.deleteAll()
        } catch {
            return .profileDeletionFailed
        }

        do {
            if try await profileStore.loadActive() != nil {
                return .profileResidue
            }
        } catch {
            return .profileResidue
        }
        return nil
    }
}

// MARK: - Preview / test double

/// A deleter with a fixed report, for previews and unit tests.
public actor InMemorySettingsLocalDataDeleter: SettingsLocalDataDeleting {
    private var report: SettingsLocalDataDeletionReport
    public private(set) var callCount = 0

    public init(
        failures: [SettingsLocalDataComponent: SettingsLocalDataDeletionFailure] = [:],
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        let completed = SettingsLocalDataComponent.allCases.filter { failures[$0] == nil }
        self.report = SettingsLocalDataDeletionReport(
            completedComponents: completed,
            failures: failures,
            finishedAt: dateProvider.now
        )
    }

    public func deleteAllLocalData() async -> SettingsLocalDataDeletionReport {
        callCount += 1
        return report
    }

    /// Replaces the next report, for retry-path tests.
    public func setReport(_ report: SettingsLocalDataDeletionReport) {
        self.report = report
    }
}
