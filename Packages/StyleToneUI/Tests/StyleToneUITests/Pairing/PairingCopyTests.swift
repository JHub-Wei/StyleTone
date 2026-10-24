import StyleToneCore
import StyleToneUI
import XCTest

/// Localization keys, fallbacks and the quality copy mapping.
final class PairingCopyTests: XCTestCase {
    // MARK: - Catalog

    func testCatalogKeysAreValidUniqueAndPrefixed() {
        for text in PairingCopy.all {
            XCTAssertTrue(
                text.key.isValid,
                "invalid localization key: \(text.key.rawValue)"
            )
            let prefix = text.key.prefix
            XCTAssertTrue(
                prefix == .pairing || prefix == .error,
                "pairing copy must stay under pairing.* or error.*: \(text.key.rawValue)"
            )
            XCTAssertFalse(text.fallback.isEmpty, "missing fallback for \(text.key.rawValue)")
            XCTAssertNotEqual(
                text.fallback,
                text.key.rawValue,
                "fallback must be readable copy, not the key"
            )
        }
        let values = PairingCopy.all.map(\.key.rawValue)
        XCTAssertEqual(Set(values).count, values.count, "duplicate localization key")
    }

    func testResolvedCopyIsNotTheKey() {
        for text in PairingCopy.all {
            XCTAssertFalse(text.text.isEmpty)
            XCTAssertNotEqual(text.text, text.key.rawValue)
        }
    }

    // MARK: - Reasons

    func testEveryAnalyzerReasonHasItsOwnCopy() {
        for key in PairingQualityReasonKeys.analyzerKeys {
            let text = PairingCopy.reasonText(for: key)
            XCTAssertNotEqual(
                text.key,
                PairingCopy.dynamicReason.key,
                "reason \(key) fell through to the dynamic label"
            )
            XCTAssertFalse(text.text.isEmpty)
        }
    }

    func testSamePhotoReasonIsDefinedByTheUI() {
        let text = PairingCopy.reasonText(for: PairingQualityReasonKeys.samePhoto)
        XCTAssertEqual(text.key, PairingCopy.reasonSamePhoto.key)
        XCTAssertTrue(text.key.isValid)
    }

    func testUnknownReasonIsHumanized() {
        let text = PairingCopy.reasonText(for: "pair.reason.brandNewReason")
        XCTAssertEqual(text.key, PairingCopy.dynamicReason.key)
        XCTAssertEqual(text.text, "Brand new reason.")
    }

    func testReasonsAreDeduplicatedInOrder() {
        let reasons = [
            PairingQualityReasonKeys.semanticMismatch,
            PairingQualityReasonKeys.semanticMismatch,
            PairingQualityReasonKeys.misaligned,
        ]
        let texts = PairingCopy.reasonTexts(for: reasons)
        XCTAssertEqual(texts.count, 2)
        XCTAssertEqual(texts[0], PairingCopy.reasonSemanticMismatch.text)
        XCTAssertEqual(texts[1], PairingCopy.reasonMisaligned.text)
    }

    // MARK: - Quality presentation

    func testGoodPresentation() {
        let quality = PairingTestFactory.quality(.good)
        let presentation = PairingQualityPresentation.make(
            for: .completed(quality),
            isComplete: true
        )
        XCTAssertEqual(presentation.kind, .good)
        XCTAssertEqual(presentation.colorToken, .success)
        XCTAssertEqual(presentation.systemImage, "checkmark.circle.fill")
        XCTAssertFalse(presentation.isBlocking)
        XCTAssertFalse(presentation.canRetry)
        XCTAssertEqual(presentation.shortTitle, PairingCopy.qualityShortGood.text)
    }

    func testWarningPresentationShowsReasons() {
        let quality = PairingTestFactory.quality(
            .warning,
            reasons: [PairingQualityReasonKeys.structureChanged]
        )
        let presentation = PairingQualityPresentation.make(
            for: .completed(quality),
            isComplete: true
        )
        XCTAssertEqual(presentation.kind, .warning)
        XCTAssertEqual(presentation.colorToken, .warning)
        XCTAssertFalse(presentation.isBlocking)
        XCTAssertTrue(presentation.messages.contains(PairingCopy.reasonStructureChanged.text))
    }

    func testRejectedPresentationBlocksLearning() {
        let quality = PairingTestFactory.quality(
            .rejected,
            reasons: [PairingQualityReasonKeys.semanticMismatch]
        )
        let presentation = PairingQualityPresentation.make(
            for: .completed(quality),
            isComplete: true
        )
        XCTAssertEqual(presentation.kind, .rejected)
        XCTAssertEqual(presentation.colorToken, .error)
        XCTAssertTrue(presentation.isBlocking)
        XCTAssertTrue(presentation.isProblem)
        XCTAssertTrue(presentation.messages.contains(PairingCopy.qualityRejectedHint.text))
        XCTAssertTrue(presentation.accessibilityLabel.contains(PairingCopy.qualityRejected.text))
    }

    func testWaitingAndCheckingPresentations() {
        let waiting = PairingQualityPresentation.make(
            for: .waitingForImages,
            isComplete: false
        )
        XCTAssertEqual(waiting.kind, .waiting)
        XCTAssertEqual(waiting.shortTitle, PairingCopy.qualityShortWaiting.text)

        let checking = PairingQualityPresentation.make(
            for: .assessing,
            isComplete: true
        )
        XCTAssertEqual(checking.kind, .checking)
        XCTAssertEqual(checking.shortTitle, PairingCopy.qualityShortChecking.text)
        XCTAssertFalse(checking.isBlocking)
    }

    func testFailedPresentationOffersRetryWhenPossible() {
        let retryable = PairingQualityPresentation.make(
            for: .failed(PairingAssessmentFailure(code: .analysisFailed)),
            isComplete: true
        )
        XCTAssertEqual(retryable.kind, .failed)
        XCTAssertTrue(retryable.canRetry)
        XCTAssertEqual(retryable.colorToken, .warning)

        let permanent = PairingQualityPresentation.make(
            for: .failed(
                PairingAssessmentFailure(code: .unknown, isRetryable: false)
            ),
            isComplete: true
        )
        XCTAssertFalse(permanent.canRetry)
        XCTAssertEqual(permanent.colorToken, .error)
    }

    // MARK: - Error copy

    func testImportErrorCopy() {
        XCTAssertEqual(
            PairingImportError.imageTooSmall(minimumLongEdge: 512).title.key,
            PairingCopy.importTooSmallTitle.key
        )
        XCTAssertEqual(
            PairingImportError.unsupportedFormat.title.key,
            PairingCopy.importUnsupportedTitle.key
        )
        XCTAssertEqual(
            PairingImportError.noImageData.title.key,
            PairingCopy.importNoDataTitle.key
        )
        XCTAssertEqual(
            PairingImportError.unreadableData.title.key,
            PairingCopy.importFailedTitle.key
        )
        let importErrors: [PairingImportError] = [
            .noImageData,
            .unreadableData,
            .unsupportedFormat,
            .imageTooSmall(minimumLongEdge: 512),
            .decodingFailed,
            .unknown,
        ]
        for error in importErrors {
            XCTAssertFalse(error.title.text.isEmpty)
            XCTAssertFalse(error.message.text.isEmpty)
        }
    }

    func testStoreErrorCopy() {
        XCTAssertEqual(
            PairingSessionStoreError.corrupted.title.key,
            PairingCopy.sessionCorruptedTitle.key
        )
        XCTAssertEqual(
            PairingSessionStoreError.unsupportedSchema(version: 2).title.key,
            PairingCopy.sessionSchemaTitle.key
        )
        XCTAssertEqual(
            PairingSessionStoreError.writeFailed.title.key,
            PairingCopy.sessionSaveTitle.key
        )
        XCTAssertEqual(
            PairingSessionStoreError.readFailed.title.key,
            PairingCopy.sessionLoadTitle.key
        )
    }

    func testAssessmentFailureCopy() {
        for code in PairingAssessmentFailureCode.allCases {
            let failure = PairingAssessmentFailure(code: code)
            XCTAssertFalse(failure.text.text.isEmpty)
            XCTAssertFalse(failure.text.key.rawValue.isEmpty)
        }
    }

    func testStyleToneErrorMapping() {
        XCTAssertEqual(
            PairingAssessmentFailure.map(StyleToneError.invalidState).code,
            .analyzerUnavailable
        )
        XCTAssertEqual(
            PairingAssessmentFailure.map(StyleToneError.imageAnalysisFailed).code,
            .analysisFailed
        )
        XCTAssertEqual(
            PairingAssessmentFailure.map(StyleToneError.cancelled).code,
            .cancelled
        )
        XCTAssertEqual(
            PairingAssessmentFailure.map(StyleToneError.persistenceFailed).code,
            .unknown
        )
        XCTAssertEqual(
            PairingAssessmentFailure.map(CancellationError()).code,
            .cancelled
        )
    }
}
