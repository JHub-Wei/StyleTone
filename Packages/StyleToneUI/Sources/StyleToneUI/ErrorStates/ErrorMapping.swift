import Foundation
import StyleToneCore

// MARK: - Purchase reasons

/// StoreKit-shaped failure reasons.
///
/// `StyleToneCommerce` (WP-20) maps its `StoreKit` / verification errors onto
/// this small enum so the UI does not depend on StoreKit and so the offline
/// rules stay identical across product loading, purchase and restore.
public enum PurchaseFailureReason: String, CaseIterable, Sendable, Codable, Hashable {
    case offline
    case cancelled
    case productUnavailable
    case paymentNotAllowed
    case verificationFailed
    case purchaseFailed
    case restoreFailed
    case unknown
}

// MARK: - Mapper

/// Maps engine, export, import, network and file errors onto ``ErrorState``.
///
/// Mapping is total: any error produces a state, and the state always carries
/// copy, at least one action (unless it is a cancellation) and a diagnostic
/// code. Error descriptions are never read, because those strings can contain
/// file names or other user data.
public enum ErrorMapper {
    // MARK: General

    public static func state(
        for error: Error,
        context: ErrorContext = .general
    ) -> ErrorState {
        if isCancellation(error) {
            return ErrorState(
                kind: .cancelled,
                context: context,
                sourceCode: cancellationSourceCode(for: error)
            )
        }

        if let failure = error as? ExportFailure {
            return state(for: failure, context: context)
        }
        if let library = error as? ExportLibraryError {
            return state(for: library, context: context)
        }
        if let pipeline = error as? ExportPipelineError {
            return state(for: pipeline, context: context)
        }
        if let styleTone = error as? StyleToneError {
            return state(for: styleTone, context: context)
        }
        if let importError = error as? PairingImportError {
            return state(for: importError, context: context)
        }
        if let sessionError = error as? PairingSessionStoreError {
            return state(for: sessionError, context: context)
        }
        if let assessment = error as? PairingAssessmentFailure {
            return state(for: assessment, context: context)
        }
        if let urlError = error as? URLError {
            return state(for: urlError, context: context)
        }
        if let storageKind = storageFailureKind(for: error) {
            return ErrorState(
                kind: storageKind,
                context: context,
                sourceCode: storageSourceCode(for: error)
            )
        }

        return ErrorState(
            kind: .unknown,
            context: context,
            sourceCode: sourceCode(for: error)
        )
    }

    /// Cancellation is a normal outcome, not an error: the presenter drops it
    /// without showing an alert.
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let styleTone = error as? StyleToneError, styleTone.isCancellation {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        if let assessment = error as? PairingAssessmentFailure,
           assessment.code == .cancelled {
            return true
        }
        return false
    }

    /// Whether an error means the device has no usable connection.
    public static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .callIsActive:
            return true
        default:
            return false
        }
    }

    // MARK: StyleTone

    public static func state(
        for error: StyleToneError,
        context: ErrorContext = .general
    ) -> ErrorState {
        ErrorState(
            kind: kind(for: error),
            context: context,
            sourceCode: error.code
        )
    }

    public static func kind(for error: StyleToneError) -> ErrorKind {
        switch error {
        case .invalidImage, .imageDecodingFailed:
            return .invalidImage
        case .unsupportedFormat:
            return .unsupportedFormat
        case .imageTooSmall(_):
            return .imageTooSmall
        case .imageAnalysisFailed:
            return .analysisFailed
        case .noFaceDetected:
            return .noFace
        case .noBodyDetected:
            return .noBody
        case .renderingFailed, .retouchingFailed, .warpingFailed:
            return .renderFailed
        case .exportFailed:
            return .exportRenderFailed
        case .persistenceFailed:
            return .persistenceFailed
        case .purchaseFailed:
            return .purchaseFailed
        case .invalidMask:
            return .invalidMask
        case .unsupportedSchema(_):
            return .schemaUnsupported
        case .cancelled:
            return .cancelled
        case .invalidState:
            return .invalidState
        }
    }

    /// Maps a page-level `AppError` while preserving its chosen diagnostic code.
    public static func state(
        for error: AppError,
        context: ErrorContext = .general
    ) -> ErrorState {
        if let underlying = error.underlying {
            let mapped = state(for: underlying, context: context)
            return ErrorState(
                kind: mapped.kind,
                context: context,
                recoveryActions: mapped.recoveryActions,
                sourceCode: error.diagnosticCode
            )
        }
        if let kind = kind(forStyleToneCode: error.code) {
            return ErrorState(
                kind: kind,
                context: context,
                sourceCode: error.diagnosticCode
            )
        }
        return ErrorState(
            kind: .unknown,
            context: context,
            sourceCode: error.diagnosticCode
        )
    }

    public static func kind(forStyleToneCode code: String) -> ErrorKind? {
        switch code {
        case "E_IMAGE_INVALID", "E_IMAGE_DECODE":
            return .invalidImage
        case "E_UNSUPPORTED_FORMAT":
            return .unsupportedFormat
        case "E_IMAGE_TOO_SMALL":
            return .imageTooSmall
        case "E_ANALYSIS":
            return .analysisFailed
        case "E_NO_FACE":
            return .noFace
        case "E_NO_BODY":
            return .noBody
        case "E_RENDER", "E_RETOUCH", "E_WARP":
            return .renderFailed
        case "E_EXPORT":
            return .exportRenderFailed
        case "E_PERSISTENCE":
            return .persistenceFailed
        case "E_PURCHASE":
            return .purchaseFailed
        case "E_MASK":
            return .invalidMask
        case "E_SCHEMA":
            return .schemaUnsupported
        case "E_CANCELLED":
            return .cancelled
        case "E_STATE":
            return .invalidState
        default:
            return nil
        }
    }

    // MARK: Export

    public static func state(
        for failure: ExportFailure,
        context: ErrorContext = .export
    ) -> ErrorState {
        ErrorState(
            kind: kind(for: failure.kind),
            context: context,
            recoveryActions: failure.recoveries.map {
                RecoveryAction(exportRecovery: $0)
            },
            sourceCode: failure.underlyingCode ?? failure.diagnosticCode
        )
    }

    public static func kind(for kind: ExportFailure.Kind) -> ErrorKind {
        switch kind {
        case .unavailable:
            return .exportUnavailable
        case .renderFailed:
            return .exportRenderFailed
        case .resolutionMismatch:
            return .exportResolutionMismatch
        case .encodeFailed:
            return .exportEncodeFailed
        case .permissionDenied:
            return .photoPermissionDenied
        case .permissionRestricted:
            return .photoPermissionRestricted
        case .photoLibraryUnavailable:
            return .photoLibraryUnavailable
        case .librarySaveFailed:
            return .exportLibrarySaveFailed
        case .shareUnavailable:
            return .exportShareUnavailable
        case .quotaExhausted:
            return .exportQuotaExhausted
        case .quotaUnavailable:
            return .exportQuotaUnavailable
        case .invalidImage:
            return .exportInvalidImage
        case .unknown:
            return .unknown
        }
    }

    public static func state(
        for error: ExportLibraryError,
        context: ErrorContext = .export
    ) -> ErrorState {
        let kind: ErrorKind
        switch error {
        case .permissionDenied:
            kind = .photoPermissionDenied
        case .permissionRestricted:
            kind = .photoPermissionRestricted
        case .saveFailed:
            kind = .exportLibrarySaveFailed
        case .unavailable:
            kind = .photoLibraryUnavailable
        }
        return ErrorState(kind: kind, context: context, sourceCode: error.code)
    }

    public static func state(
        for error: ExportPipelineError,
        context: ErrorContext = .export
    ) -> ErrorState {
        let kind: ErrorKind
        switch error {
        case .resolutionMismatch:
            kind = .exportResolutionMismatch
        case .missingOutput, .exportSizeMismatch, .formatMismatch:
            kind = .exportEncodeFailed
        }
        return ErrorState(kind: kind, context: context, sourceCode: error.code)
    }

    // MARK: Pairing

    public static func state(
        for error: PairingImportError,
        context: ErrorContext = .pairing
    ) -> ErrorState {
        let kind: ErrorKind
        let source: String
        switch error {
        case .noImageData:
            kind = .invalidImage
            source = "PAIRING_IMPORT_NO_DATA"
        case .unreadableData:
            kind = .invalidImage
            source = "PAIRING_IMPORT_UNREADABLE"
        case .unsupportedFormat:
            kind = .unsupportedFormat
            source = "PAIRING_IMPORT_UNSUPPORTED"
        case .imageTooSmall(_):
            kind = .imageTooSmall
            source = "PAIRING_IMPORT_TOO_SMALL"
        case .decodingFailed:
            kind = .invalidImage
            source = "PAIRING_IMPORT_DECODE"
        case .unknown:
            kind = .unknown
            source = "PAIRING_IMPORT_UNKNOWN"
        }
        return ErrorState(kind: kind, context: context, sourceCode: source)
    }

    public static func state(
        for error: PairingSessionStoreError,
        context: ErrorContext = .pairing
    ) -> ErrorState {
        let kind: ErrorKind
        let source: String
        switch error {
        case .corrupted:
            kind = .persistenceFailed
            source = "PAIRING_SESSION_CORRUPTED"
        case .unsupportedSchema(_):
            kind = .schemaUnsupported
            source = "PAIRING_SESSION_SCHEMA"
        case .writeFailed:
            kind = .persistenceFailed
            source = "PAIRING_SESSION_WRITE"
        case .readFailed:
            kind = .persistenceFailed
            source = "PAIRING_SESSION_READ"
        case .clearFailed:
            kind = .persistenceFailed
            source = "PAIRING_SESSION_CLEAR"
        }
        return ErrorState(kind: kind, context: context, sourceCode: source)
    }

    public static func state(
        for failure: PairingAssessmentFailure,
        context: ErrorContext = .pairing
    ) -> ErrorState {
        let kind: ErrorKind
        switch failure.code {
        case .cancelled:
            kind = .cancelled
        case .analysisFailed, .analyzerUnavailable:
            kind = .analysisFailed
        case .unknown:
            kind = .unknown
        }
        return ErrorState(
            kind: kind,
            context: context,
            sourceCode: "PAIRING_ASSESSMENT_\(failure.code.rawValue.uppercased())"
        )
    }

    // MARK: Network

    public static func state(
        for error: URLError,
        context: ErrorContext = .paywall
    ) -> ErrorState {
        let kind: ErrorKind
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .callIsActive:
            kind = .offline
        case .cancelled:
            kind = .cancelled
        default:
            kind = .networkUnavailable
        }
        return ErrorState(
            kind: kind,
            context: context,
            sourceCode: "URLError.\(error.code.rawValue)"
        )
    }

    // MARK: Purchase

    public static func state(
        for reason: PurchaseFailureReason,
        context: ErrorContext = .paywall
    ) -> ErrorState {
        let kind: ErrorKind
        switch reason {
        case .offline:
            kind = .offline
        case .cancelled:
            kind = .cancelled
        case .productUnavailable, .paymentNotAllowed:
            kind = .purchaseUnavailable
        case .verificationFailed:
            kind = .purchaseVerificationFailed
        case .purchaseFailed:
            kind = .purchaseFailed
        case .restoreFailed:
            kind = .restoreFailed
        case .unknown:
            kind = .unknown
        }
        return ErrorState(
            kind: kind,
            context: context,
            sourceCode: "PURCHASE_\(reason.rawValue.uppercased())"
        )
    }

    // MARK: Permission

    /// Maps add-only photo access; `nil` means the operation can proceed.
    public static func state(
        for access: PhotoLibraryAccess,
        context: ErrorContext = .export
    ) -> ErrorState? {
        let kind: ErrorKind
        switch access {
        case .denied:
            kind = .photoPermissionDenied
        case .restricted:
            kind = .photoPermissionRestricted
        case .unavailable:
            kind = .photoLibraryUnavailable
        case .authorized, .limited, .notDetermined:
            return nil
        }
        return ErrorState(
            kind: kind,
            context: context,
            sourceCode: "PHOTO_ACCESS_\(access.rawValue.uppercased())"
        )
    }

    /// The state raised when a network action is attempted without a link.
    public static func offline(context: ErrorContext = .paywall) -> ErrorState {
        ErrorState(kind: .offline, context: context, sourceCode: "OFFLINE")
    }

    // MARK: Storage

    /// Detects out-of-space, read-only and permission failures without reading
    /// the localized description (which could contain a path).
    public static func storageFailureKind(for error: Error) -> ErrorKind? {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain {
            let code = nsError.code
            if code == CocoaError.Code.fileWriteOutOfSpace.rawValue {
                return .storageFull
            }
            if code == CocoaError.Code.fileWriteVolumeReadOnly.rawValue
                || code == CocoaError.Code.fileWriteNoPermission.rawValue
                || code == CocoaError.Code.fileReadNoPermission.rawValue {
                return .storageUnavailable
            }
            if code == CocoaError.Code.fileWriteUnknown.rawValue
                || code == CocoaError.Code.fileReadUnknown.rawValue {
                return .storageWriteFailed
            }
            if code == CocoaError.Code.fileReadCorruptFile.rawValue
                || code == CocoaError.Code.fileReadNoSuchFile.rawValue {
                return .persistenceFailed
            }
            return nil
        }

        if nsError.domain == NSPOSIXErrorDomain {
            // Stable errno values; keeping them numeric avoids importing a
            // platform-specific POSIX overlay into the UI module.
            switch nsError.code {
            case 28, 69: // ENOSPC, EDQUOT
                return .storageFull
            case 13, 1, 30: // EACCES, EPERM, EROFS
                return .storageUnavailable
            case 5: // EIO
                return .storageWriteFailed
            default:
                return nil
            }
        }

        return nil
    }

    /// Path-free source code for a file error, for example
    /// `NSCocoaErrorDomain.640`.
    static func storageSourceCode(for error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain).\(nsError.code)"
    }

    // MARK: Private

    private static func sourceCode(for error: Error) -> String? {
        let nsError = error as NSError
        guard nsError.domain != NSCocoaErrorDomain || nsError.code != 0 else {
            return nil
        }
        return "\(nsError.domain).\(nsError.code)"
    }

    private static func cancellationSourceCode(for error: Error) -> String {
        if let styleTone = error as? StyleToneError {
            return styleTone.code
        }
        if let urlError = error as? URLError {
            return "URLError.\(urlError.code.rawValue)"
        }
        if let assessment = error as? PairingAssessmentFailure {
            return "PAIRING_ASSESSMENT_\(assessment.code.rawValue.uppercased())"
        }
        return "CANCELLED"
    }
}

// MARK: - Page adapters

public extension ErrorState {
    /// Adapter for WP-17's `EditorIssue` / any page that already mapped a
    /// `StyleToneError` into an `AppError`.
    init(_ appError: AppError, context: ErrorContext = .general) {
        let mapped = ErrorMapper.state(for: appError, context: context)
        self.init(
            kind: mapped.kind,
            context: context,
            recoveryActions: mapped.recoveryActions,
            sourceCode: mapped.sourceCode
        )
    }

    /// Adapter for WP-19's `ExportFailure`.
    init(_ failure: ExportFailure, context: ErrorContext = .export) {
        let mapped = ErrorMapper.state(for: failure, context: context)
        self.init(
            kind: mapped.kind,
            context: context,
            recoveryActions: mapped.recoveryActions,
            sourceCode: mapped.sourceCode
        )
    }

    /// Adapter for WP-09's import/assessment failures.
    init(_ error: PairingImportError, context: ErrorContext = .pairing) {
        let mapped = ErrorMapper.state(for: error, context: context)
        self.init(
            kind: mapped.kind,
            context: context,
            recoveryActions: mapped.recoveryActions,
            sourceCode: mapped.sourceCode
        )
    }

    init(_ error: PairingSessionStoreError, context: ErrorContext = .pairing) {
        let mapped = ErrorMapper.state(for: error, context: context)
        self.init(
            kind: mapped.kind,
            context: context,
            recoveryActions: mapped.recoveryActions,
            sourceCode: mapped.sourceCode
        )
    }

    init(_ failure: PairingAssessmentFailure, context: ErrorContext = .pairing) {
        let mapped = ErrorMapper.state(for: failure, context: context)
        self.init(
            kind: mapped.kind,
            context: context,
            recoveryActions: mapped.recoveryActions,
            sourceCode: mapped.sourceCode
        )
    }
}

// MARK: - Private helpers

private extension RecoveryAction {
    init(exportRecovery: ExportFailure.Recovery) {
        switch exportRecovery {
        case .retry: self = .retry
        case .shareInstead: self = .shareInstead
        case .saveInstead: self = .saveInstead
        case .openSettings: self = .openSettings
        case .upgrade: self = .upgrade
        case .dismiss: self = .dismiss
        }
    }
}
