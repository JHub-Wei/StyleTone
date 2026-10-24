import Foundation
import StyleToneCore

/// The visual and spoken summary of one pair's quality state.
public struct PairingQualityPresentation: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case waiting
        case checking
        case good
        case warning
        case rejected
        case failed
    }

    public let kind: Kind
    public let title: String
    /// Readable reasons or hints, already localized.
    public let messages: [String]
    public let colorToken: ColorToken
    public let systemImage: String
    public let accessibilityLabel: String
    /// A red pair is excluded from learning.
    public let isBlocking: Bool
    public let canRetry: Bool

    public init(
        kind: Kind,
        title: String,
        messages: [String],
        colorToken: ColorToken,
        systemImage: String,
        accessibilityLabel: String,
        isBlocking: Bool,
        canRetry: Bool
    ) {
        self.kind = kind
        self.title = title
        self.messages = messages
        self.colorToken = colorToken
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.isBlocking = isBlocking
        self.canRetry = canRetry
    }

    public var isProblem: Bool {
        kind == .rejected || kind == .failed
    }

    /// Compact label for the badge in the card header.
    public var shortTitle: String {
        switch kind {
        case .waiting: return PairingCopy.qualityShortWaiting.text
        case .checking: return PairingCopy.qualityShortChecking.text
        case .good: return PairingCopy.qualityShortGood.text
        case .warning: return PairingCopy.qualityShortWarning.text
        case .rejected: return PairingCopy.qualityShortRejected.text
        case .failed: return PairingCopy.qualityShortFailed.text
        }
    }

    /// Builds the presentation for a pair's current assessment state.
    public static func make(
        for assessment: PairingAssessmentState,
        isComplete: Bool
    ) -> PairingQualityPresentation {
        guard isComplete else {
            return waitingPresentation
        }

        switch assessment {
        case .waitingForImages:
            return waitingPresentation

        case .assessing:
            let title = PairingCopy.qualityChecking.text
            return PairingQualityPresentation(
                kind: .checking,
                title: title,
                messages: [],
                colorToken: .textSecondary,
                systemImage: "clock",
                accessibilityLabel: title,
                isBlocking: false,
                canRetry: false
            )

        case let .completed(quality):
            return presentation(for: quality)

        case let .failed(failure):
            let title = PairingCopy.qualityFailed.text
            let message = failure.text.text
            return PairingQualityPresentation(
                kind: .failed,
                title: title,
                messages: [message],
                colorToken: failure.isRetryable ? .warning : .error,
                systemImage: "arrow.triangle.2.circlepath",
                accessibilityLabel: "\(title). \(message)",
                isBlocking: false,
                canRetry: failure.isRetryable
            )
        }
    }

    private static var waitingPresentation: PairingQualityPresentation {
        let title = PairingCopy.qualityWaiting.text
        return PairingQualityPresentation(
            kind: .waiting,
            title: title,
            messages: [PairingCopy.importHint.text],
            colorToken: .textSecondary,
            systemImage: "rectangle.on.rectangle",
            accessibilityLabel: title,
            isBlocking: false,
            canRetry: false
        )
    }

    private static func presentation(for quality: PairQuality) -> PairingQualityPresentation {
        let reasons = PairingCopy.reasonTexts(for: quality.reasons)

        switch quality.grade {
        case .good:
            let title = PairingCopy.qualityGood.text
            let hint = PairingCopy.qualityGoodHint.text
            return PairingQualityPresentation(
                kind: .good,
                title: title,
                messages: [hint],
                colorToken: .success,
                systemImage: "checkmark.circle.fill",
                accessibilityLabel: "\(title). \(hint)",
                isBlocking: false,
                canRetry: false
            )

        case .warning:
            let title = PairingCopy.qualityWarning.text
            let hint = PairingCopy.qualityWarningHint.text
            let messages = reasons.isEmpty ? [hint] : reasons
            return PairingQualityPresentation(
                kind: .warning,
                title: title,
                messages: messages,
                colorToken: .warning,
                systemImage: "exclamationmark.triangle.fill",
                accessibilityLabel: ([title] + messages).joined(separator: ". "),
                isBlocking: false,
                canRetry: false
            )

        case .rejected:
            let title = PairingCopy.qualityRejected.text
            let hint = PairingCopy.qualityRejectedHint.text
            let messages = reasons + [hint]
            return PairingQualityPresentation(
                kind: .rejected,
                title: title,
                messages: messages,
                colorToken: .error,
                systemImage: "xmark.octagon.fill",
                accessibilityLabel: ([title] + messages).joined(separator: ". "),
                isBlocking: true,
                canRetry: false
            )
        }
    }
}

// MARK: - Failure copy

public extension PairingAssessmentFailure {
    /// Readable explanation for the failure code.
    var text: PairingText {
        switch code {
        case .analyzerUnavailable:
            return PairingCopy.qualityFailureAnalyzerUnavailable
        case .analysisFailed:
            return PairingCopy.qualityFailureAnalysisFailed
        case .cancelled:
            return PairingCopy.qualityFailureCancelled
        case .unknown:
            return PairingCopy.qualityFailureUnknown
        }
    }
}

public extension PairingImportError {
    /// Notice title for an import failure.
    var title: PairingText {
        switch self {
        case .noImageData:
            return PairingCopy.importNoDataTitle
        case .unsupportedFormat:
            return PairingCopy.importUnsupportedTitle
        case .imageTooSmall:
            return PairingCopy.importTooSmallTitle
        case .unreadableData, .decodingFailed, .unknown:
            return PairingCopy.importFailedTitle
        }
    }

    /// Notice message for an import failure.
    var message: PairingText {
        switch self {
        case .noImageData:
            return PairingCopy.importNoDataMessage
        case .unsupportedFormat:
            return PairingCopy.importUnsupportedMessage
        case .imageTooSmall:
            return PairingCopy.importTooSmallMessage
        case .unreadableData, .decodingFailed, .unknown:
            return PairingCopy.importFailedMessage
        }
    }
}

public extension PairingSessionStoreError {
    /// Notice title for a session-store failure.
    var title: PairingText {
        switch self {
        case .corrupted:
            return PairingCopy.sessionCorruptedTitle
        case .unsupportedSchema:
            return PairingCopy.sessionSchemaTitle
        case .writeFailed:
            return PairingCopy.sessionSaveTitle
        case .readFailed, .clearFailed:
            return PairingCopy.sessionLoadTitle
        }
    }

    /// Notice message for a session-store failure.
    var message: PairingText {
        switch self {
        case .corrupted:
            return PairingCopy.sessionCorruptedMessage
        case .unsupportedSchema:
            return PairingCopy.sessionSchemaMessage
        case .writeFailed:
            return PairingCopy.sessionSaveMessage
        case .readFailed, .clearFailed:
            return PairingCopy.sessionLoadMessage
        }
    }
}
