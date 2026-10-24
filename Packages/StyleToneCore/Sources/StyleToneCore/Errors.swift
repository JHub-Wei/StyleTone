import Foundation

/// Low-level, module-facing error taxonomy. It must not carry file paths,
/// image identifiers, user text or any other PII.
public enum StyleToneError: Error, Sendable, Equatable {
    case invalidImage
    case unsupportedFormat
    case imageTooSmall(minimumLongEdge: Int)
    case imageDecodingFailed
    case imageAnalysisFailed
    case noFaceDetected
    case noBodyDetected
    case renderingFailed
    case retouchingFailed
    case warpingFailed
    case exportFailed
    case persistenceFailed
    case purchaseFailed
    case invalidMask
    case unsupportedSchema(version: Int)
    case cancelled
    case invalidState

    public var code: String {
        switch self {
        case .invalidImage: return "E_IMAGE_INVALID"
        case .unsupportedFormat: return "E_UNSUPPORTED_FORMAT"
        case .imageTooSmall: return "E_IMAGE_TOO_SMALL"
        case .imageDecodingFailed: return "E_IMAGE_DECODE"
        case .imageAnalysisFailed: return "E_ANALYSIS"
        case .noFaceDetected: return "E_NO_FACE"
        case .noBodyDetected: return "E_NO_BODY"
        case .renderingFailed: return "E_RENDER"
        case .retouchingFailed: return "E_RETOUCH"
        case .warpingFailed: return "E_WARP"
        case .exportFailed: return "E_EXPORT"
        case .persistenceFailed: return "E_PERSISTENCE"
        case .purchaseFailed: return "E_PURCHASE"
        case .invalidMask: return "E_MASK"
        case .unsupportedSchema: return "E_SCHEMA"
        case .cancelled: return "E_CANCELLED"
        case .invalidState: return "E_STATE"
        }
    }

    public var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

/// User-presentable error with localization keys and a recovery action.
/// `titleKey` and `messageKey` are resolved by the UI layer.
public struct AppError: Error, Sendable, Equatable, Identifiable {
    public enum Recovery: String, Sendable, Equatable {
        case retry
        case chooseAnotherPhoto
        case useNaturalStyle
        case reduceStrength
        case restorePurchase
        case recalibrate
        case openSettings
        case none
    }

    public let id: UUID
    public let code: String
    public let titleKey: String
    public let messageKey: String
    public let recovery: Recovery
    public let diagnosticCode: String
    public let underlying: StyleToneError?

    public init(
        id: UUID = UUID(),
        code: String,
        titleKey: String,
        messageKey: String,
        recovery: Recovery,
        diagnosticCode: String,
        underlying: StyleToneError? = nil
    ) {
        self.id = id
        self.code = code
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.recovery = recovery
        self.diagnosticCode = diagnosticCode
        self.underlying = underlying
    }

    public static func map(
        _ error: StyleToneError,
        diagnosticCode: String? = nil
    ) -> AppError {
        let mapping: (title: String, message: String, recovery: Recovery)

        switch error {
        case .invalidImage, .unsupportedFormat, .imageDecodingFailed:
            mapping = ("error.image.title", "error.image.message", .chooseAnotherPhoto)
        case .imageTooSmall:
            mapping = ("error.imageTooSmall.title", "error.imageTooSmall.message", .chooseAnotherPhoto)
        case .imageAnalysisFailed:
            mapping = ("error.analysis.title", "error.analysis.message", .retry)
        case .noFaceDetected:
            mapping = ("error.noFace.title", "error.noFace.message", .useNaturalStyle)
        case .noBodyDetected:
            mapping = ("error.noBody.title", "error.noBody.message", .useNaturalStyle)
        case .renderingFailed, .retouchingFailed, .warpingFailed:
            mapping = ("error.render.title", "error.render.message", .reduceStrength)
        case .exportFailed:
            mapping = ("error.export.title", "error.export.message", .retry)
        case .persistenceFailed:
            mapping = ("error.storage.title", "error.storage.message", .retry)
        case .purchaseFailed:
            mapping = ("error.purchase.title", "error.purchase.message", .restorePurchase)
        case .invalidMask:
            mapping = ("error.mask.title", "error.mask.message", .retry)
        case .unsupportedSchema:
            mapping = ("error.schema.title", "error.schema.message", .recalibrate)
        case .cancelled:
            mapping = ("error.cancelled.title", "error.cancelled.message", .none)
        case .invalidState:
            mapping = ("error.state.title", "error.state.message", .retry)
        }

        return AppError(
            code: error.code,
            titleKey: mapping.title,
            messageKey: mapping.message,
            recovery: mapping.recovery,
            diagnosticCode: diagnosticCode ?? "ST-\(error.code)",
            underlying: error
        )
    }
}
