import Foundation

// MARK: - Domain

/// The product area an error came from.
///
/// Domains are diagnostic only: user copy never depends on them, and they carry
/// no device, file or account information.
public enum ErrorDomain: String, CaseIterable, Sendable, Codable, Hashable {
    case network
    case permission
    case storage
    case purchase
    case importing
    case analysis
    case rendering
    case export
    case persistence
    case system
    case state
    case unknown

    /// Stable three-to-five letter segment of a diagnostic code.
    var codePrefix: String {
        switch self {
        case .network: return "NET"
        case .permission: return "PERM"
        case .storage: return "STOR"
        case .purchase: return "PUR"
        case .importing: return "IMG"
        case .analysis: return "ANL"
        case .rendering: return "RND"
        case .export: return "EXP"
        case .persistence: return "DATA"
        case .system: return "SYS"
        case .state: return "STATE"
        case .unknown: return "UNKNOWN"
        }
    }
}

// MARK: - Diagnostic code

/// A stable, path-free support code such as `ST-NET-001`.
///
/// Codes are shown to the user ("Support code: …") and written to the local
/// diagnostic log. They must never contain a file name, an album identifier, a
/// URL or any other value derived from user content.
public struct DiagnosticCode: RawRepresentable, Hashable, Sendable, Codable,
    CustomStringConvertible
{
    public static let prefix = "ST-"
    public static let maximumLength = 32

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    /// Whether the code follows the fixed `ST-<AREA>-<NUMBER>` shape.
    ///
    /// The check is intentionally conservative: uppercase ASCII letters,
    /// digits, hyphens and underscores only, so a code can never smuggle in a
    /// path separator, an email address or localized text.
    public var isValid: Bool {
        guard rawValue.hasPrefix(Self.prefix),
              rawValue.count >= 6,
              rawValue.count <= Self.maximumLength
        else {
            return false
        }
        return rawValue.unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value)
                || (48...57).contains(scalar.value)
                || scalar.value == 45 // -
                || scalar.value == 95 // _
        }
    }
}

// MARK: - Kind

/// Every user-visible error the app can present.
///
/// The list is deliberately exhaustive: mapping code must switch over all
/// cases, so a new engine error cannot silently fall back to empty copy.
public enum ErrorKind: String, CaseIterable, Sendable, Codable, Hashable {
    // Network and system
    case offline
    case networkUnavailable
    case lowBattery
    case thermalPressure
    case interrupted
    case cancelled

    // Permission
    case photoPermissionDenied
    case photoPermissionRestricted
    case photoLibraryUnavailable

    // Storage
    case storageLow
    case storageFull
    case storageUnavailable
    case storageWriteFailed

    // Purchase
    case purchaseUnavailable
    case purchaseFailed
    case purchaseVerificationFailed
    case restoreFailed

    // Export
    case exportUnavailable
    case exportRenderFailed
    case exportResolutionMismatch
    case exportEncodeFailed
    case exportShareUnavailable
    case exportLibrarySaveFailed
    case exportQuotaExhausted
    case exportQuotaUnavailable
    case exportInvalidImage

    // Import and analysis
    case invalidImage
    case unsupportedFormat
    case imageTooSmall
    case analysisFailed
    case noFace
    case noBody

    // Rendering
    case renderFailed
    case invalidMask
    case invalidState

    // Persistence
    case persistenceFailed
    case schemaUnsupported

    // Anything else
    case unknown

    // MARK: Classification

    public var domain: ErrorDomain {
        switch self {
        case .offline, .networkUnavailable:
            return .network
        case .lowBattery, .thermalPressure, .interrupted, .cancelled:
            return .system
        case .photoPermissionDenied, .photoPermissionRestricted,
             .photoLibraryUnavailable:
            return .permission
        case .storageLow, .storageFull, .storageUnavailable, .storageWriteFailed:
            return .storage
        case .purchaseUnavailable, .purchaseFailed, .purchaseVerificationFailed,
             .restoreFailed:
            return .purchase
        case .exportUnavailable, .exportRenderFailed, .exportResolutionMismatch,
             .exportEncodeFailed, .exportShareUnavailable,
             .exportLibrarySaveFailed, .exportQuotaExhausted,
             .exportQuotaUnavailable, .exportInvalidImage:
            return .export
        case .invalidImage, .unsupportedFormat, .imageTooSmall:
            return .importing
        case .analysisFailed, .noFace, .noBody:
            return .analysis
        case .renderFailed, .invalidMask:
            return .rendering
        case .invalidState:
            return .state
        case .persistenceFailed, .schemaUnsupported:
            return .persistence
        case .unknown:
            return .unknown
        }
    }

    /// Notices are advisory; recoverable errors interrupt one action.
    public var severity: ErrorSeverity {
        switch self {
        case .offline, .networkUnavailable, .lowBattery, .thermalPressure,
             .interrupted, .cancelled, .storageLow:
            return .notice
        default:
            return .recoverable
        }
    }

    /// Cancellation is never shown as an error.
    public var isSilent: Bool {
        self == .cancelled
    }

    /// Code suffix within the domain, for example `FULL` in `ST-STOR-002`.
    var codeSuffix: String {
        switch self {
        case .offline: return "001"
        case .networkUnavailable: return "002"
        case .lowBattery: return "001"
        case .thermalPressure: return "002"
        case .interrupted: return "003"
        case .cancelled: return "004"
        case .photoPermissionDenied: return "001"
        case .photoPermissionRestricted: return "002"
        case .photoLibraryUnavailable: return "003"
        case .storageLow: return "001"
        case .storageFull: return "002"
        case .storageUnavailable: return "003"
        case .storageWriteFailed: return "004"
        case .purchaseUnavailable: return "001"
        case .purchaseFailed: return "002"
        case .purchaseVerificationFailed: return "003"
        case .restoreFailed: return "004"
        case .exportUnavailable: return "001"
        case .exportRenderFailed: return "002"
        case .exportResolutionMismatch: return "003"
        case .exportEncodeFailed: return "004"
        case .exportShareUnavailable: return "005"
        case .exportLibrarySaveFailed: return "006"
        case .exportQuotaExhausted: return "007"
        case .exportQuotaUnavailable: return "008"
        case .exportInvalidImage: return "009"
        case .invalidImage: return "001"
        case .unsupportedFormat: return "002"
        case .imageTooSmall: return "003"
        case .analysisFailed: return "001"
        case .noFace: return "002"
        case .noBody: return "003"
        case .renderFailed: return "001"
        case .invalidMask: return "002"
        case .invalidState: return "001"
        case .persistenceFailed: return "001"
        case .schemaUnsupported: return "002"
        case .unknown: return "001"
        }
    }

    /// The canonical user-facing support code, for example `ST-STOR-002`.
    public var diagnosticCode: DiagnosticCode {
        DiagnosticCode("ST-\(domain.codePrefix)-\(codeSuffix)")
    }

    // MARK: Recovery

    /// The default recovery list, in display order.
    ///
    /// Every non-silent kind ends with `.dismiss`, so the user always has a way
    /// out even when no handler is wired.
    public var defaultRecoveries: [RecoveryAction] {
        switch self {
        case .offline:
            return [.continueOffline, .retry, .dismiss]
        case .networkUnavailable:
            return [.retry, .dismiss]
        case .lowBattery, .thermalPressure:
            return [.continueAnyway, .dismiss]
        case .interrupted:
            return [.resume, .dismiss]
        case .cancelled:
            return []
        case .photoPermissionDenied:
            return [.openSettings, .shareInstead, .retry, .dismiss]
        case .photoPermissionRestricted:
            return [.shareInstead, .dismiss]
        case .photoLibraryUnavailable:
            return [.shareInstead, .dismiss]
        case .storageLow:
            return [.freeUpSpace, .dismiss]
        case .storageFull:
            return [.freeUpSpace, .retry, .dismiss]
        case .storageUnavailable, .storageWriteFailed:
            return [.retry, .dismiss]
        case .purchaseUnavailable:
            return [.retry, .continueOffline, .dismiss]
        case .purchaseFailed:
            return [.retry, .restorePurchase, .dismiss]
        case .purchaseVerificationFailed:
            return [.restorePurchase, .retry, .dismiss]
        case .restoreFailed:
            return [.retry, .dismiss]
        case .exportUnavailable, .exportRenderFailed, .exportResolutionMismatch,
             .exportEncodeFailed:
            return [.retry, .dismiss]
        case .exportQuotaUnavailable:
            // The quota card owns "check again"; a card-level retry would read
            // the same failed store. Matches WP-19's mapping.
            return [.dismiss]
        case .exportShareUnavailable:
            return [.saveInstead, .dismiss]
        case .exportLibrarySaveFailed:
            return [.retry, .shareInstead, .dismiss]
        case .exportQuotaExhausted:
            return [.upgrade, .dismiss]
        case .exportInvalidImage:
            return [.chooseAnotherPhoto, .dismiss]
        case .invalidImage, .unsupportedFormat, .imageTooSmall:
            return [.chooseAnotherPhoto, .dismiss]
        case .analysisFailed:
            return [.retry, .dismiss]
        case .noFace, .noBody:
            return [.useNaturalStyle, .chooseAnotherPhoto, .dismiss]
        case .renderFailed:
            return [.reduceStrength, .retry, .dismiss]
        case .invalidMask, .invalidState:
            return [.retry, .dismiss]
        case .persistenceFailed:
            return [.retry, .dismiss]
        case .schemaUnsupported:
            return [.recalibrate, .dismiss]
        case .unknown:
            return [.retry, .dismiss]
        }
    }
}
