import Foundation
import StyleToneCore

/// A user-presentable export failure.
///
/// The value carries localization keys, a recovery list and a diagnostic code;
/// it never carries a file path, a photo-library identifier or any other PII.
/// `ExportFailure.map` is the single place where engine/library errors become
/// user-facing failures.
public struct ExportFailure: Error, Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable, Hashable {
        case unavailable
        case renderFailed
        case resolutionMismatch
        case encodeFailed
        case permissionDenied
        case permissionRestricted
        case photoLibraryUnavailable
        case librarySaveFailed
        case shareUnavailable
        case quotaExhausted
        case quotaUnavailable
        case invalidImage
        case unknown
    }

    /// One button offered by the failure card.
    public enum Recovery: String, Sendable, CaseIterable, Hashable {
        case retry
        case shareInstead
        case saveInstead
        case openSettings
        case upgrade
        case dismiss
    }

    public let id: UUID
    public let kind: Kind
    public let stage: ExportStage
    public let recoveries: [Recovery]
    public let diagnosticCode: String
    public let underlyingCode: String?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        stage: ExportStage,
        recoveries: [Recovery],
        diagnosticCode: String,
        underlyingCode: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.stage = stage
        self.recoveries = recoveries
        self.diagnosticCode = diagnosticCode
        self.underlyingCode = underlyingCode
    }

    public var title: ExportText {
        ExportCopy.failureTitle(kind)
    }

    public var message: ExportText {
        ExportCopy.failureMessage(kind)
    }

    /// The failure path may keep the encoded file so "Share instead" does not
    /// have to render and encode again.
    public var keepsStagedFile: Bool {
        recoveries.contains(.shareInstead)
    }

    public var isRetryable: Bool {
        recoveries.contains(.retry)
    }

    // MARK: - Mapping

    /// Maps any engine, pipeline, photo-library or unknown error.
    ///
    /// Cancellation is handled by the view model before mapping and therefore
    /// maps to `.unknown` here only if a caller misuses this function.
    public static func map(_ error: Error, stage: ExportStage) -> ExportFailure {
        let underlying = code(for: error)

        if let pipeline = error as? ExportPipelineError {
            switch pipeline {
            case .resolutionMismatch:
                return make(kind: .resolutionMismatch, stage: stage, underlyingCode: underlying)
            case .exportSizeMismatch, .formatMismatch, .missingOutput:
                return make(kind: .encodeFailed, stage: stage, underlyingCode: underlying)
            }
        }

        if let library = error as? ExportLibraryError {
            switch library {
            case .permissionDenied:
                return make(kind: .permissionDenied, stage: stage, underlyingCode: underlying)
            case .permissionRestricted:
                return make(kind: .permissionRestricted, stage: stage, underlyingCode: underlying)
            case .saveFailed:
                return make(kind: .librarySaveFailed, stage: stage, underlyingCode: underlying)
            case .unavailable:
                return make(
                    kind: .photoLibraryUnavailable,
                    stage: stage,
                    underlyingCode: underlying
                )
            }
        }

        if let styleTone = error as? StyleToneError {
            switch styleTone {
            case .exportFailed:
                return make(kind: .encodeFailed, stage: stage, underlyingCode: underlying)
            case .invalidImage, .imageDecodingFailed, .unsupportedFormat,
                 .imageTooSmall:
                return make(kind: .invalidImage, stage: stage, underlyingCode: underlying)
            case .invalidState:
                return make(kind: .unavailable, stage: stage, underlyingCode: underlying)
            case .renderingFailed, .retouchingFailed, .warpingFailed,
                 .imageAnalysisFailed, .noFaceDetected, .noBodyDetected,
                 .invalidMask:
                return make(kind: .renderFailed, stage: stage, underlyingCode: underlying)
            default:
                return make(kind: .unknown, stage: stage, underlyingCode: underlying)
            }
        }

        return make(kind: .unknown, stage: stage, underlyingCode: underlying)
    }

    /// Builds a failure with the recovery list owned by `kind`.
    static func make(
        kind: Kind,
        stage: ExportStage,
        underlyingCode: String? = nil
    ) -> ExportFailure {
        ExportFailure(
            kind: kind,
            stage: stage,
            recoveries: recoveries(for: kind),
            diagnosticCode: "ST-EXPORT-\(kind.codeSuffix)",
            underlyingCode: underlyingCode
        )
    }

    // MARK: - Private

    private static func recoveries(for kind: Kind) -> [Recovery] {
        switch kind {
        case .unavailable, .renderFailed, .resolutionMismatch, .encodeFailed,
             .unknown:
            return [.retry, .dismiss]
        case .permissionDenied:
            return [.openSettings, .shareInstead, .retry, .dismiss]
        case .permissionRestricted:
            return [.shareInstead, .dismiss]
        case .photoLibraryUnavailable:
            return [.shareInstead, .dismiss]
        case .librarySaveFailed:
            return [.retry, .shareInstead, .dismiss]
        case .shareUnavailable:
            return [.saveInstead, .dismiss]
        case .quotaExhausted:
            return [.upgrade, .dismiss]
        case .quotaUnavailable:
            // The quota card owns "Check again"; a failure-card retry would
            // simply re-read the same failed store.
            return [.dismiss]
        case .invalidImage:
            return [.dismiss]
        }
    }

    private static func code(for error: Error) -> String? {
        if let styleTone = error as? StyleToneError {
            return styleTone.code
        }
        if let library = error as? ExportLibraryError {
            return library.code
        }
        if let pipeline = error as? ExportPipelineError {
            return pipeline.code
        }
        return nil
    }
}

extension ExportFailure.Kind {
    /// Stable suffix used by `diagnosticCode`; never localized.
    var codeSuffix: String {
        switch self {
        case .unavailable: return "UNAVAILABLE"
        case .renderFailed: return "RENDER"
        case .resolutionMismatch: return "RESOLUTION"
        case .encodeFailed: return "ENCODE"
        case .permissionDenied: return "PERMISSION"
        case .permissionRestricted: return "RESTRICTED"
        case .photoLibraryUnavailable: return "LIBRARY"
        case .librarySaveFailed: return "SAVE"
        case .shareUnavailable: return "SHARE"
        case .quotaExhausted: return "QUOTA"
        case .quotaUnavailable: return "QUOTA_READ"
        case .invalidImage: return "IMAGE"
        case .unknown: return "UNKNOWN"
        }
    }
}
