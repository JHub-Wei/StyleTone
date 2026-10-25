import Foundation
import StyleToneCore

// MARK: - Preference keys

/// Keys owned by the settings feature in the app's preference domain.
public enum SettingsPreferenceKeys {
    /// The diagnostics opt-in. Absent or `false` means off.
    public static let diagnosticsOptIn = "settings.diagnostics.optIn"

    /// Every key the settings feature may write.
    public static let all: [String] = [diagnosticsOptIn]
}

// MARK: - Diagnostics preferences

/// Persists the diagnostics opt-in.
public protocol SettingsDiagnosticsPreferencesStoring: Sendable {
    func diagnosticsOptIn() async -> Bool
    func setDiagnosticsOptIn(_ enabled: Bool) async throws
    func clear() async throws
}

/// `UserDefaults`-backed opt-in, off by default.
public struct UserDefaultsSettingsDiagnosticsPreferences: SettingsDiagnosticsPreferencesStoring {
    private let suiteName: String?
    private let key: String

    public init(
        suiteName: String? = nil,
        key: String = SettingsPreferenceKeys.diagnosticsOptIn
    ) {
        self.suiteName = suiteName
        self.key = key
    }

    private var defaults: UserDefaults {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            return suite
        }
        return .standard
    }

    public func diagnosticsOptIn() async -> Bool {
        defaults.bool(forKey: key)
    }

    public func setDiagnosticsOptIn(_ enabled: Bool) async throws {
        defaults.set(enabled, forKey: key)
    }

    public func clear() async throws {
        defaults.removeObject(forKey: key)
    }
}

/// In-memory opt-in for previews and tests.
public actor InMemorySettingsDiagnosticsPreferences: SettingsDiagnosticsPreferencesStoring {
    private var enabled: Bool
    private let setError: SettingsDiagnosticsError?
    private let clearError: SettingsDiagnosticsError?

    public private(set) var setCount = 0
    public private(set) var clearCount = 0

    public init(
        enabled: Bool = false,
        setError: SettingsDiagnosticsError? = nil,
        clearError: SettingsDiagnosticsError? = nil
    ) {
        self.enabled = enabled
        self.setError = setError
        self.clearError = clearError
    }

    public func diagnosticsOptIn() async -> Bool {
        enabled
    }

    public func setDiagnosticsOptIn(_ enabled: Bool) async throws {
        setCount += 1
        if let setError {
            throw setError
        }
        self.enabled = enabled
    }

    public func clear() async throws {
        clearCount += 1
        if let clearError {
            throw clearError
        }
        enabled = false
    }

    /// Test helper: the currently stored opt-in.
    public func currentValue() async -> Bool {
        enabled
    }
}

// MARK: - Local preferences deletion

/// Clears every preference the app owns, including first-run/onboarding state.
///
/// The diagnostics key alone is not enough: after "Delete all local data" a
/// relaunch must return to onboarding, so the whole app preference domain is
/// removed. Keychain entitlement caches are intentionally out of scope (the
/// purchase is managed by Apple and is not cancelled by this action).
public protocol SettingsLocalPreferencesClearing: Sendable {
    func clearLocalPreferences() async throws
}

/// Removes the app's persistent preference domain.
public struct UserDefaultsSettingsLocalPreferences: SettingsLocalPreferencesClearing {
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    public func clearLocalPreferences() async throws {
        if let suiteName {
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                throw SettingsDiagnosticsError.preferenceUnavailable
            }
            defaults.removePersistentDomain(forName: suiteName)
            return
        }

        let defaults = UserDefaults.standard
        if let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        } else {
            for key in SettingsPreferenceKeys.all {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

/// In-memory local-preference cleaner for previews and tests.
public actor InMemorySettingsLocalPreferences: SettingsLocalPreferencesClearing {
    private let clearError: SettingsDiagnosticsError?
    public private(set) var clearCount = 0

    public init(clearError: SettingsDiagnosticsError? = nil) {
        self.clearError = clearError
    }

    public func clearLocalPreferences() async throws {
        clearCount += 1
        if let clearError {
            throw clearError
        }
    }
}

// MARK: - Diagnostic log storage

/// Persists the bounded local diagnostic log.
public protocol SettingsDiagnosticsLogStoring: Sendable {
    func load() async -> [SettingsDiagnosticEntry]
    func save(_ entries: [SettingsDiagnosticEntry]) async throws
    func clear() async throws
}

/// A JSON log under Application Support.
///
/// The file is bounded, atomic and, on iOS, written with complete file
/// protection. It contains only ``SettingsDiagnosticEntry`` values, never
/// photos, file names or free-form text. Corrupt or oversized files are ignored
/// rather than crashing diagnostics or the app.
public actor FileSettingsDiagnosticsLogStore: SettingsDiagnosticsLogStoring {
    public static let defaultFileName = "diagnostics.json"

    private let directory: URL
    private let logFileName: String
    private let maximumEntries: Int

    public init(
        directory: URL,
        logFileName: String = FileSettingsDiagnosticsLogStore.defaultFileName,
        maximumEntries: Int = SettingsDiagnosticsLimits.maximumEntries
    ) {
        self.directory = directory
        self.logFileName = logFileName
        self.maximumEntries = max(1, maximumEntries)
    }

    /// Full path of the log file. The file name is fixed by this type.
    public nonisolated var logFileURL: URL {
        directory.appendingPathComponent(logFileName, isDirectory: false)
    }

    /// Default directory inside the app sandbox.
    public static func defaultDirectory(fileManager: FileManager = .default) -> URL? {
        guard let base = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return base
            .appendingPathComponent("StyleTone", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    public func load() async -> [SettingsDiagnosticEntry] {
        let url = logFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= SettingsDiagnosticsLimits.maximumFileSize
        else {
            return []
        }
        guard let data = try? Data(contentsOf: url),
              let entries = try? Self.makeDecoder().decode([SettingsDiagnosticEntry].self, from: data)
        else {
            return []
        }
        return Array(entries.suffix(maximumEntries))
    }

    public func save(_ entries: [SettingsDiagnosticEntry]) async throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let bounded = Array(entries.suffix(maximumEntries))
            let data = try Self.makeEncoder().encode(bounded)
            try data.write(to: logFileURL, options: [.atomic])
            applyProtection(at: logFileURL)
        } catch {
            throw SettingsDiagnosticsError.logUnavailable
        }
    }

    public func clear() async throws {
        let url = logFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw SettingsDiagnosticsError.logUnavailable
        }
    }

    private func applyProtection(at url: URL) {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #else
        _ = url
        #endif
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// In-memory diagnostic log for previews and tests.
public actor InMemorySettingsDiagnosticsLogStore: SettingsDiagnosticsLogStoring {
    private var entries: [SettingsDiagnosticEntry]
    private let saveError: SettingsDiagnosticsError?
    private let clearError: SettingsDiagnosticsError?

    public private(set) var loadCount = 0
    public private(set) var saveCount = 0
    public private(set) var clearCount = 0

    public init(
        entries: [SettingsDiagnosticEntry] = [],
        saveError: SettingsDiagnosticsError? = nil,
        clearError: SettingsDiagnosticsError? = nil
    ) {
        self.entries = entries
        self.saveError = saveError
        self.clearError = clearError
    }

    public func load() async -> [SettingsDiagnosticEntry] {
        loadCount += 1
        return entries
    }

    public func save(_ entries: [SettingsDiagnosticEntry]) async throws {
        saveCount += 1
        if let saveError {
            throw saveError
        }
        self.entries = entries
    }

    public func clear() async throws {
        clearCount += 1
        if let clearError {
            throw clearError
        }
        entries = []
    }

    /// The currently stored entries, for assertions.
    public func currentEntries() async -> [SettingsDiagnosticEntry] {
        entries
    }
}

// MARK: - Diagnostics service

/// Owns the opt-in gate and the local log.
///
/// Every write goes through ``record(_:)``, which checks the opt-in on the
/// actor first. Disabling diagnostics clears the log, so "off" means both
/// "collect nothing new" and "keep nothing old". Diagnostics never fail a user
/// action: a write error is swallowed after the in-memory entry is updated, and
/// the next successful write persists the bounded ring.
public actor SettingsDiagnosticsService: SettingsDiagnosticsControlling, SettingsDiagnosticsDataClearing {
    private let preferences: any SettingsDiagnosticsPreferencesStoring
    private let store: any SettingsDiagnosticsLogStoring
    private let versionProvider: any SettingsVersionProviding
    private let dateProvider: any DateProviding
    private let maximumEntries: Int

    private var isLoaded = false
    private var enabled = false
    private var entries: [SettingsDiagnosticEntry] = []

    public init(
        preferences: any SettingsDiagnosticsPreferencesStoring,
        store: any SettingsDiagnosticsLogStoring,
        versionProvider: any SettingsVersionProviding,
        dateProvider: any DateProviding = SystemDateProvider(),
        maximumEntries: Int = SettingsDiagnosticsLimits.maximumEntries
    ) {
        self.preferences = preferences
        self.store = store
        self.versionProvider = versionProvider
        self.dateProvider = dateProvider
        self.maximumEntries = max(1, maximumEntries)
    }

    public func snapshot() async -> SettingsDiagnosticsSnapshot {
        await loadIfNeeded()
        return makeSnapshot()
    }

    public func setEnabled(_ enabled: Bool) async throws -> SettingsDiagnosticsSnapshot {
        await loadIfNeeded()
        guard self.enabled != enabled else { return makeSnapshot() }

        if enabled {
            do {
                try await preferences.setDiagnosticsOptIn(true)
            } catch {
                throw SettingsDiagnosticsError.preferenceUnavailable
            }
            self.enabled = true
            return makeSnapshot()
        }

        do {
            try await preferences.setDiagnosticsOptIn(false)
        } catch {
            throw SettingsDiagnosticsError.preferenceUnavailable
        }
        self.enabled = false
        entries = []
        do {
            try await store.clear()
        } catch {
            throw SettingsDiagnosticsError.logUnavailable
        }
        return makeSnapshot()
    }

    public func record(_ event: SettingsDiagnosticEvent) async {
        await loadIfNeeded()
        guard enabled else { return }

        let version = versionProvider.currentVersion()
        let entry = SettingsDiagnosticEntry(
            kind: event.kind,
            code: event.code,
            recordedAt: dateProvider.now,
            appVersion: version.marketingVersion,
            buildNumber: version.buildNumber,
            platform: version.platform,
            osVersion: version.osVersion
        )
        entries.append(entry)
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        // Diagnostics are best effort: a full disk or a locked file must not
        // interrupt editing, exporting or deletion recovery.
        try? await store.save(entries)
    }

    public func clear() async throws -> SettingsDiagnosticsSnapshot {
        await loadIfNeeded()
        entries = []
        do {
            try await store.clear()
        } catch {
            throw SettingsDiagnosticsError.logUnavailable
        }
        return makeSnapshot()
    }

    public func deleteDiagnosticData() async throws {
        await loadIfNeeded()
        enabled = false
        entries = []

        var failure: SettingsDiagnosticsError?
        do {
            try await preferences.clear()
        } catch {
            failure = .preferenceUnavailable
        }
        do {
            try await store.clear()
        } catch {
            if failure == nil {
                failure = .logUnavailable
            }
        }
        if let failure {
            throw failure
        }
    }

    // MARK: Private

    private func loadIfNeeded() async {
        guard !isLoaded else { return }

        let storedOptIn = await preferences.diagnosticsOptIn()
        let storedEntries = await store.load()
        enabled = storedOptIn
        entries = Array(storedEntries.suffix(maximumEntries))

        // Crash recovery: diagnostics were turned off but the clear did not
        // complete. Do not keep collecting and remove the orphaned log.
        if !enabled, !entries.isEmpty {
            entries = []
            try? await store.clear()
        }
        isLoaded = true
    }

    private func makeSnapshot() -> SettingsDiagnosticsSnapshot {
        let version = versionProvider.currentVersion()
        return SettingsDiagnosticsSnapshot(
            isEnabled: enabled,
            entries: entries,
            code: SettingsDiagnosticCode.make(
                version: version,
                isEnabled: enabled,
                entryCount: entries.count
            ),
            updatedAt: dateProvider.now
        )
    }
}
