import Foundation

/// Events that may be written to the local diagnostic log.
///
/// The type is an enum, not a free-form message. This is the primary PII guard:
/// callers can choose an event and an error code, but cannot pass photo names,
/// paths, email addresses or other user text into the log.
public enum SettingsDiagnosticEventKind: String, CaseIterable, Codable, Sendable, Equatable {
    case appLaunch = "app.launch"
    case appForeground = "app.foreground"
    case settingsOpened = "settings.opened"
    case calibrationCompleted = "calibration.completed"
    case exportSucceeded = "export.succeeded"
    case exportFailed = "export.failed"
    case renderFailed = "render.failed"
    case shareOpened = "share.opened"
    case purchaseRestored = "purchase.restored"
    case purchaseFailed = "purchase.failed"
}

/// One whitelisted diagnostic event.
public struct SettingsDiagnosticEvent: Sendable, Equatable {
    public let kind: SettingsDiagnosticEventKind
    /// A validated error code such as `E_EXPORT`, or `nil`.
    public let code: String?

    public init(kind: SettingsDiagnosticEventKind, code: String? = nil) {
        self.kind = kind
        self.code = Self.normalizedCode(code)
    }

    /// Keeps an error code only when it matches a bounded ASCII alphabet.
    ///
    /// Accepted: 2-32 characters, an uppercase ASCII letter first, then
    /// uppercase letters, digits or underscores. Paths, file names, email
    /// addresses and localized prose fail this check and become `nil`.
    public static func normalizedCode(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == rawValue else { return nil }
        guard trimmed.count >= 2, trimmed.count <= SettingsDiagnosticsLimits.maximumCodeLength else {
            return nil
        }
        guard let first = trimmed.unicodeScalars.first, isUppercaseASCII(first) else {
            return nil
        }
        guard trimmed.unicodeScalars.allSatisfy({ scalar in
            isUppercaseASCII(scalar) || isDigitASCII(scalar) || scalar.value == 95 // "_"
        }) else {
            return nil
        }
        return trimmed
    }

    /// Whether a raw string would be accepted as an error code.
    public static func isValidCode(_ rawValue: String) -> Bool {
        normalizedCode(rawValue) != nil
    }

    private static func isUppercaseASCII(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value)
    }

    private static func isDigitASCII(_ scalar: Unicode.Scalar) -> Bool {
        (48...57).contains(scalar.value)
    }
}

/// One stored diagnostic entry.
///
/// There is intentionally no device name, advertising identifier, photo
/// reference or free-form message here.
public struct SettingsDiagnosticEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let kind: SettingsDiagnosticEventKind
    public let code: String?
    public let recordedAt: Date
    public let appVersion: String
    public let buildNumber: String
    public let platform: String
    public let osVersion: String

    public init(
        id: UUID = UUID(),
        kind: SettingsDiagnosticEventKind,
        code: String? = nil,
        recordedAt: Date,
        appVersion: String,
        buildNumber: String,
        platform: String,
        osVersion: String
    ) {
        self.id = id
        self.kind = kind
        self.code = code
        self.recordedAt = recordedAt
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.platform = platform
        self.osVersion = osVersion
    }
}

/// The current diagnostics state shown by the screen.
public struct SettingsDiagnosticsSnapshot: Sendable, Equatable {
    public let isEnabled: Bool
    public let entries: [SettingsDiagnosticEntry]
    public let code: String
    public let updatedAt: Date

    public init(
        isEnabled: Bool,
        entries: [SettingsDiagnosticEntry],
        code: String,
        updatedAt: Date
    ) {
        self.isEnabled = isEnabled
        self.entries = entries
        self.code = code
        self.updatedAt = updatedAt
    }

    /// A snapshot with diagnostics off and no entries.
    public static func disabled(
        version: SettingsVersionInfo,
        at date: Date
    ) -> SettingsDiagnosticsSnapshot {
        SettingsDiagnosticsSnapshot(
            isEnabled: false,
            entries: [],
            code: SettingsDiagnosticCode.make(
                version: version,
                isEnabled: false,
                entryCount: 0
            ),
            updatedAt: date
        )
    }
}

/// Bounds that keep the local log small and the code stable.
public enum SettingsDiagnosticsLimits {
    /// Oldest entries are dropped past this count.
    public static let maximumEntries = 200
    /// A corrupt or unexpectedly large file is ignored.
    public static let maximumFileSize = 256 * 1024
    /// Error-code alphabet bound.
    public static let maximumCodeLength = 32
    /// Counts embedded in the diagnostic code are clamped.
    public static let maximumCodeEntryCount = 99_999
}

/// Errors surfaced by the diagnostics service.
///
/// The cases carry no user data; the UI maps them to fixed copy.
public enum SettingsDiagnosticsError: Error, Sendable, Equatable {
    case preferenceUnavailable
    case logUnavailable
}

/// Controls the optional local diagnostic log.
public protocol SettingsDiagnosticsControlling: Sendable {
    /// Reads the current opt-in state along with the stored entries.
    func snapshot() async -> SettingsDiagnosticsSnapshot

    /// Persists the opt-in state. Turning diagnostics off clears the log.
    func setEnabled(_ enabled: Bool) async throws -> SettingsDiagnosticsSnapshot

    /// Appends an event when diagnostics are enabled; otherwise does nothing.
    func record(_ event: SettingsDiagnosticEvent) async

    /// Removes every local diagnostic entry.
    func clear() async throws -> SettingsDiagnosticsSnapshot
}

/// The deletion path used by "Delete all local data".
///
/// Separate from the screen protocol so the deletion coordinator cannot depend
/// on UI state; an implementation must fail if the log cannot be removed.
public protocol SettingsDiagnosticsDataClearing: Sendable {
    func deleteDiagnosticData() async throws
}
