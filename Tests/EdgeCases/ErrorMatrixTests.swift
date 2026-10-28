import StyleToneCore
import StyleToneUI
import XCTest

/// The error matrix: every kind, every mapping and the copy/action invariants.
final class ErrorMatrixTests: XCTestCase {
    // MARK: - Kind invariants

    func testEveryKindHasCopyActionsAndDiagnosticCode() {
        for kind in ErrorKind.allCases {
            let state = ErrorState(kind: kind)

            XCTAssertFalse(state.title.text.isEmpty, "empty title for \(kind)")
            XCTAssertFalse(state.message.text.isEmpty, "empty message for \(kind)")
            XCTAssertEqual(state.title.key.prefix, LocalizationPrefix.error, "title prefix for \(kind)")
            XCTAssertEqual(state.message.key.prefix, LocalizationPrefix.error, "message prefix for \(kind)")
            XCTAssertTrue(state.title.key.isValid, "title key for \(kind)")
            XCTAssertTrue(state.message.key.isValid, "message key for \(kind)")
            XCTAssertTrue(state.diagnosticCode.isValid, "code for \(kind)")
            XCTAssertEqual(state.domain, kind.domain)

            if kind.isSilent {
                XCTAssertTrue(state.recoveryActions.isEmpty, "cancelled actions")
                XCTAssertTrue(state.isSilent)
                XCTAssertNil(state.primaryAction)
            } else {
                XCTAssertFalse(state.recoveryActions.isEmpty, "actions for \(kind)")
                XCTAssertTrue(
                    state.recoveryActions.contains(.dismiss),
                    "missing dismiss for \(kind)"
                )
                XCTAssertEqual(
                    Set(state.recoveryActions).count,
                    state.recoveryActions.count,
                    "duplicate actions for \(kind)"
                )
                XCTAssertNotNil(state.primaryAction, "no primary action for \(kind)")
            }
        }
    }

    func testDiagnosticCodesAreStableAndUnique() {
        let codes = ErrorKind.allCases.map(\.diagnosticCode.rawValue)
        XCTAssertEqual(Set(codes).count, codes.count, "duplicate diagnostic code")

        XCTAssertEqual(ErrorState(kind: .offline).diagnosticCode.rawValue, "ST-NET-001")
        XCTAssertEqual(
            ErrorState(kind: .photoPermissionDenied).diagnosticCode.rawValue,
            "ST-PERM-001"
        )
        XCTAssertEqual(ErrorState(kind: .storageFull).diagnosticCode.rawValue, "ST-STOR-002")
        XCTAssertEqual(ErrorState(kind: .lowBattery).diagnosticCode.rawValue, "ST-SYS-001")
        XCTAssertEqual(ErrorState(kind: .interrupted).diagnosticCode.rawValue, "ST-SYS-003")
        XCTAssertEqual(ErrorState(kind: .unknown).diagnosticCode.rawValue, "ST-UNKNOWN-001")

        XCTAssertFalse(DiagnosticCode("").isValid)
        XCTAssertFalse(DiagnosticCode("ST-").isValid)
        XCTAssertFalse(DiagnosticCode("/Users/alice/photo.jpg").isValid)
        XCTAssertFalse(DiagnosticCode("ST-NET-001 ").isValid)
        XCTAssertFalse(DiagnosticCode("ST-net-001").isValid)
    }

    func testSeverityMatchesTheNoticeContract() {
        let notices: Set<ErrorKind> = [
            .offline,
            .networkUnavailable,
            .lowBattery,
            .thermalPressure,
            .interrupted,
            .cancelled,
            .storageLow,
        ]
        for kind in ErrorKind.allCases {
            XCTAssertEqual(
                kind.severity,
                notices.contains(kind) ? .notice : .recoverable,
                "severity for \(kind)"
            )
        }
    }

    func testInitializerNormalizesActions() {
        let duplicate = ErrorState(
            kind: .renderFailed,
            recoveryActions: [.retry, .retry]
        )
        XCTAssertEqual(duplicate.recoveryActions, [.retry, .dismiss])
        XCTAssertEqual(duplicate.primaryAction, .retry)

        let silent = ErrorState(
            kind: .cancelled,
            recoveryActions: [.retry, .dismiss]
        )
        XCTAssertTrue(silent.recoveryActions.isEmpty)

        let customCode = DiagnosticCode("ST-CUSTOM-999")
        let custom = ErrorState(kind: .unknown, diagnosticCode: customCode)
        XCTAssertEqual(custom.diagnosticCode, customCode)
        XCTAssertTrue(custom.diagnosticCode.isValid)

        let unsafe = ErrorState(
            kind: .storageFull,
            diagnosticCode: DiagnosticCode("/Users/alice/photo.jpg")
        )
        XCTAssertEqual(unsafe.diagnosticCode, ErrorKind.storageFull.diagnosticCode)
    }

    func testSourceCodeSanitizerKeepsOnlyMachineCodes() {
        XCTAssertEqual(
            ErrorState(kind: .unknown, sourceCode: "URLError.-1009").sourceCode,
            "URLError.-1009"
        )
        XCTAssertEqual(
            ErrorState(kind: .unknown, sourceCode: "NSCocoaErrorDomain.640").sourceCode,
            "NSCocoaErrorDomain.640"
        )
        for unsafe in [
            "/Users/alice/private-portrait.jpg",
            "alice@example.com",
            "https://example.com/photo",
            "private portrait",
            String(repeating: "A", count: 65),
        ] {
            XCTAssertNil(
                ErrorState(kind: .unknown, sourceCode: unsafe).sourceCode,
                "source should be rejected: \(unsafe)"
            )
        }
    }

    // MARK: - StyleToneError

    func testEveryStyleToneErrorMapsToAnExpectedKind() {
        let cases: [(StyleToneError, ErrorKind)] = [
            (.invalidImage, .invalidImage),
            (.unsupportedFormat, .unsupportedFormat),
            (.imageTooSmall(minimumLongEdge: 512), .imageTooSmall),
            (.imageDecodingFailed, .invalidImage),
            (.imageAnalysisFailed, .analysisFailed),
            (.noFaceDetected, .noFace),
            (.noBodyDetected, .noBody),
            (.renderingFailed, .renderFailed),
            (.retouchingFailed, .renderFailed),
            (.warpingFailed, .renderFailed),
            (.exportFailed, .exportRenderFailed),
            (.persistenceFailed, .persistenceFailed),
            (.purchaseFailed, .purchaseFailed),
            (.invalidMask, .invalidMask),
            (.unsupportedSchema(version: 99), .schemaUnsupported),
            (.invalidState, .invalidState),
        ]

        XCTAssertEqual(cases.count, 16, "StyleToneError gained a case; update the matrix")
        for (error, expected) in cases {
            let state = ErrorMapper.state(for: error, context: .editor)
            XCTAssertEqual(state.kind, expected, "mapping \(error.code)")
            XCTAssertEqual(state.sourceCode, error.code)
            XCTAssertEqual(state.context, .editor)
            XCTAssertFalse(state.isSilent)
        }

        let cancelled = ErrorMapper.state(for: StyleToneError.cancelled)
        XCTAssertTrue(cancelled.isSilent)
    }

    func testStyleToneCodeLookupCoversEveryErrorCode() {
        let codes: [(String, ErrorKind)] = [
            ("E_IMAGE_INVALID", .invalidImage),
            ("E_UNSUPPORTED_FORMAT", .unsupportedFormat),
            ("E_IMAGE_TOO_SMALL", .imageTooSmall),
            ("E_IMAGE_DECODE", .invalidImage),
            ("E_ANALYSIS", .analysisFailed),
            ("E_NO_FACE", .noFace),
            ("E_NO_BODY", .noBody),
            ("E_RENDER", .renderFailed),
            ("E_RETOUCH", .renderFailed),
            ("E_WARP", .renderFailed),
            ("E_EXPORT", .exportRenderFailed),
            ("E_PERSISTENCE", .persistenceFailed),
            ("E_PURCHASE", .purchaseFailed),
            ("E_MASK", .invalidMask),
            ("E_SCHEMA", .schemaUnsupported),
            ("E_CANCELLED", .cancelled),
            ("E_STATE", .invalidState),
        ]
        for (code, expected) in codes {
            XCTAssertEqual(ErrorMapper.kind(forStyleToneCode: code), expected, code)
        }
        XCTAssertNil(ErrorMapper.kind(forStyleToneCode: "E_NOT_A_REAL_CODE"))
    }

    // MARK: - AppError

    func testAppErrorPreservesThePageDiagnosticCode() {
        let appError = AppError.map(
            .renderingFailed,
            diagnosticCode: "ST-EDITOR-RENDER"
        )
        let state = ErrorState(appError, context: .editor)

        XCTAssertEqual(state.kind, .renderFailed)
        XCTAssertEqual(state.context, .editor)
        XCTAssertEqual(state.sourceCode, "ST-EDITOR-RENDER")
        XCTAssertTrue(state.recoveryActions.contains(.retry))
    }

    func testAppErrorWithoutUnderlyingUsesTheCodeLookup() {
        let appError = AppError(
            code: "E_STATE",
            titleKey: "error.state.title",
            messageKey: "error.state.message",
            recovery: .retry,
            diagnosticCode: "ST-PAGE-STATE"
        )
        let state = ErrorState(appError)

        XCTAssertEqual(state.kind, .invalidState)
        XCTAssertEqual(state.sourceCode, "ST-PAGE-STATE")
    }

    func testAppErrorWithUnknownCodeFallsBackToUnknown() {
        let appError = AppError(
            code: "E_FUTURE_ERROR",
            titleKey: "error.future.title",
            messageKey: "error.future.message",
            recovery: .none,
            diagnosticCode: "ST-FUTURE"
        )
        let state = ErrorState(appError)

        XCTAssertEqual(state.kind, .unknown)
        XCTAssertEqual(state.sourceCode, "ST-FUTURE")
    }

    // MARK: - ExportFailure

    func testEveryExportFailureKindMapsToAUnifiedKind() {
        let expectations: [ExportFailure.Kind: ErrorKind] = [
            .unavailable: .exportUnavailable,
            .renderFailed: .exportRenderFailed,
            .resolutionMismatch: .exportResolutionMismatch,
            .encodeFailed: .exportEncodeFailed,
            .permissionDenied: .photoPermissionDenied,
            .permissionRestricted: .photoPermissionRestricted,
            .photoLibraryUnavailable: .photoLibraryUnavailable,
            .librarySaveFailed: .exportLibrarySaveFailed,
            .shareUnavailable: .exportShareUnavailable,
            .quotaExhausted: .exportQuotaExhausted,
            .quotaUnavailable: .exportQuotaUnavailable,
            .invalidImage: .exportInvalidImage,
            .unknown: .unknown,
        ]
        XCTAssertEqual(expectations.count, ExportFailure.Kind.allCases.count)

        for kind in ExportFailure.Kind.allCases {
            guard let expected = expectations[kind] else {
                XCTFail("missing expectation for \(kind)")
                continue
            }
            XCTAssertEqual(ErrorMapper.kind(for: kind), expected, "kind \(kind)")

            let failure = ExportFailure(
                kind: kind,
                stage: .preparing,
                recoveries: [.dismiss],
                diagnosticCode: "ST-EXPORT-\(kind.rawValue.uppercased())"
            )
            let state = ErrorState(failure)
            XCTAssertEqual(state.kind, expected, "state \(kind)")
            XCTAssertEqual(state.context, .export)
            XCTAssertEqual(state.sourceCode, failure.diagnosticCode)
            XCTAssertFalse(state.title.text.isEmpty)
            XCTAssertTrue(state.recoveryActions.contains(.dismiss))
        }
    }

    func testExportRecoveriesArePreservedInOrder() {
        let denied = ExportFailure.map(
            ExportLibraryError.permissionDenied,
            stage: .requestingAccess
        )
        let state = ErrorState(denied)
        XCTAssertEqual(
            state.recoveryActions,
            [.openSettings, .shareInstead, .retry, .dismiss]
        )
        XCTAssertEqual(state.sourceCode, "E_LIBRARY_PERMISSION")

        let quota = ExportFailure(
            kind: .quotaUnavailable,
            stage: .preparing,
            recoveries: [.dismiss],
            diagnosticCode: "ST-EXPORT-QUOTA_READ"
        )
        XCTAssertEqual(ErrorState(quota).recoveryActions, [.dismiss])
    }

    func testExportPipelineAndLibraryErrorsMapDirectly() {
        XCTAssertEqual(
            ErrorMapper.state(for: ExportLibraryError.permissionRestricted).kind,
            .photoPermissionRestricted
        )
        XCTAssertEqual(
            ErrorMapper.state(for: ExportLibraryError.saveFailed).kind,
            .exportLibrarySaveFailed
        )
        XCTAssertEqual(
            ErrorMapper.state(for: ExportLibraryError.unavailable).kind,
            .photoLibraryUnavailable
        )
        XCTAssertEqual(
            ErrorMapper.state(
                for: ExportPipelineError.resolutionMismatch(
                    expected: PixelSize(width: 4_000, height: 3_000),
                    actual: PixelSize(width: 1_000, height: 750)
                )
            ).kind,
            .exportResolutionMismatch
        )
        XCTAssertEqual(
            ErrorMapper.state(for: ExportPipelineError.missingOutput).kind,
            .exportEncodeFailed
        )
    }

    // MARK: - Cancellation and unknown

    func testCancellationIsAlwaysSilent() {
        let cancellations: [Error] = [
            CancellationError(),
            StyleToneError.cancelled,
            URLError(.cancelled),
            PairingAssessmentFailure(code: .cancelled),
        ]
        for error in cancellations {
            XCTAssertTrue(ErrorMapper.isCancellation(error))
            let state = ErrorMapper.state(for: error)
            XCTAssertEqual(state.kind, .cancelled)
            XCTAssertTrue(state.isSilent)
            XCTAssertTrue(state.recoveryActions.isEmpty)
            XCTAssertFalse(state.diagnosticCode.rawValue.isEmpty)
        }
    }

    func testUnknownErrorsKeepPIIOutOfCopyAndCodes() {
        let state = ErrorMapper.state(for: EdgeCasePIIError(), context: .settings)

        XCTAssertEqual(state.kind, .unknown)
        XCTAssertEqual(state.diagnosticCode.rawValue, "ST-UNKNOWN-001")
        XCTAssertEqual(state.context, .settings)
        XCTAssertEqual(state.recoveryActions, [.retry, .dismiss])
        XCTAssertFalse(state.title.text.contains("private-portrait"))
        XCTAssertFalse(state.message.text.contains("private-portrait"))
        XCTAssertFalse(state.diagnosticCode.rawValue.contains("Users"))
        XCTAssertFalse(state.sourceCode?.contains("Users") ?? false)
        XCTAssertFalse(state.sourceCode?.contains(".jpg") ?? false)
    }

    func testPairingAdaptersMapWithoutLeakingThePayload() {
        XCTAssertEqual(ErrorState(PairingImportError.noImageData).kind, .invalidImage)
        XCTAssertEqual(
            ErrorState(PairingImportError.imageTooSmall(minimumLongEdge: 512)).kind,
            .imageTooSmall
        )
        XCTAssertEqual(
            ErrorState(PairingImportError.unsupportedFormat).kind,
            .unsupportedFormat
        )
        XCTAssertEqual(
            ErrorState(PairingSessionStoreError.unsupportedSchema(version: 4)).kind,
            .schemaUnsupported
        )
        XCTAssertEqual(
            ErrorState(PairingAssessmentFailure(code: .analysisFailed)).kind,
            .analysisFailed
        )

        for state in [
            ErrorState(PairingImportError.decodingFailed),
            ErrorState(PairingSessionStoreError.corrupted),
            ErrorState(PairingAssessmentFailure(code: .analyzerUnavailable)),
        ] {
            XCTAssertFalse(state.sourceCode?.isEmpty ?? true)
            XCTAssertFalse(
                state.diagnosticCode.rawValue.contains("private-portrait")
            )
        }
    }
}
