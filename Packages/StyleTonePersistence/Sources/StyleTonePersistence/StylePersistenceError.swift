import Foundation
import StyleToneCore

/// Persistence failures that are safe to show to the user.
///
/// Cases carry no file paths, image identifiers, user text or other PII. The
/// associated values are schema/version numbers only. Callers map ``appError``
/// (or ``styleToneError``) into the shared ``AppError`` presentation contract.
public enum StylePersistenceError: Error, Sendable, Equatable {
    /// The SwiftData index could not be opened or recreated.
    case storeUnavailable
    /// A file could not be read, written or deleted.
    case ioFailed
    /// The profile JSON is unreadable or structurally invalid.
    case profileCorrupt
    /// The profile was written by a newer schema than this app understands.
    case profileUnsupportedSchema(version: Int)
    /// A legacy profile could not be transformed into the current schema.
    case profileMigrationFailed(sourceVersion: Int)
    /// The index points at a profile file that no longer exists.
    case profileFileMissing
    /// A record argument was outside its documented bounds.
    case invalidRecord
    /// A requested record does not exist (used by deliberate mutations).
    case recordNotFound
}

extension StylePersistenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "The local style index is unavailable; it can be rebuilt on the next attempt."
        case .ioFailed:
            return "A local file operation failed."
        case .profileCorrupt:
            return "The stored style profile is unreadable and must be recalibrated."
        case let .profileUnsupportedSchema(version):
            return "The stored style profile uses schema version \(version), which is newer than this app."
        case let .profileMigrationFailed(sourceVersion):
            return "A schema version \(sourceVersion) style profile could not be migrated."
        case .profileFileMissing:
            return "The active style profile file is missing."
        case .invalidRecord:
            return "The local record is invalid."
        case .recordNotFound:
            return "The requested local record does not exist."
        }
    }
}

public extension StylePersistenceError {
    /// Core-level taxonomy used by non-UI callers.
    var styleToneError: StyleToneError {
        switch self {
        case let .profileUnsupportedSchema(version):
            return .unsupportedSchema(version: version)
        case .profileMigrationFailed:
            return .unsupportedSchema(version: StyleProfile.currentSchemaVersion)
        case .profileCorrupt, .profileFileMissing:
            return .persistenceFailed
        case .storeUnavailable, .ioFailed:
            return .persistenceFailed
        case .invalidRecord, .recordNotFound:
            return .invalidState
        }
    }

    /// User-presentable error with localization keys and a recovery action.
    ///
    /// Corrupt, missing and unreadable profiles all recommend recalibration,
    /// which is the same recovery the shared schema error uses. Storage-level
    /// failures keep the shared retry action.
    var appError: AppError {
        switch self {
        case .profileCorrupt, .profileFileMissing, .profileMigrationFailed:
            return AppError.map(
                .unsupportedSchema(version: StyleProfile.currentSchemaVersion),
                diagnosticCode: diagnosticCode
            )
        case let .profileUnsupportedSchema(version):
            return AppError.map(
                .unsupportedSchema(version: version),
                diagnosticCode: diagnosticCode
            )
        case .storeUnavailable, .ioFailed:
            return AppError.map(.persistenceFailed, diagnosticCode: diagnosticCode)
        case .invalidRecord, .recordNotFound:
            return AppError.map(.invalidState, diagnosticCode: diagnosticCode)
        }
    }

    /// Stable diagnostic code; contains no paths or user data.
    var diagnosticCode: String {
        switch self {
        case .storeUnavailable:
            return "ST-PERSIST-STORE"
        case .ioFailed:
            return "ST-PERSIST-IO"
        case .profileCorrupt:
            return "ST-PERSIST-CORRUPT"
        case .profileUnsupportedSchema:
            return "ST-PERSIST-SCHEMA-NEW"
        case .profileMigrationFailed:
            return "ST-PERSIST-SCHEMA-MIGRATE"
        case .profileFileMissing:
            return "ST-PERSIST-MISSING"
        case .invalidRecord:
            return "ST-PERSIST-RECORD"
        case .recordNotFound:
            return "ST-PERSIST-NOT-FOUND"
        }
    }

    var titleKey: String { appError.titleKey }

    var messageKey: String { appError.messageKey }

    var recovery: AppError.Recovery { appError.recovery }
}
