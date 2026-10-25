import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

/// Error mapping, recovery lists and the small value types around export.
final class ExportFailureTests: XCTestCase {
    // MARK: - Mapping

    func testStyleToneErrorsMapToActionableFailures() {
        let render = ExportFailure.map(StyleToneError.warpingFailed, stage: .rendering)
        XCTAssertEqual(render.kind, .renderFailed)
        XCTAssertEqual(render.stage, .rendering)
        XCTAssertTrue(render.isRetryable)
        XCTAssertEqual(render.underlyingCode, "E_WARP")

        let encode = ExportFailure.map(StyleToneError.exportFailed, stage: .encoding)
        XCTAssertEqual(encode.kind, .encodeFailed)
        XCTAssertEqual(encode.underlyingCode, "E_EXPORT")

        let image = ExportFailure.map(StyleToneError.invalidImage, stage: .rendering)
        XCTAssertEqual(image.kind, .invalidImage)
        XCTAssertFalse(image.isRetryable)

        let unavailable = ExportFailure.map(StyleToneError.invalidState, stage: .preparing)
        XCTAssertEqual(unavailable.kind, .unavailable)
        XCTAssertTrue(unavailable.isRetryable)
    }

    func testLibraryErrorsMapToPermissionAndSaveFailures() {
        let denied = ExportFailure.map(
            ExportLibraryError.permissionDenied,
            stage: .requestingAccess
        )
        XCTAssertEqual(denied.kind, .permissionDenied)
        XCTAssertEqual(denied.recoveries, [.openSettings, .shareInstead, .retry, .dismiss])
        XCTAssertTrue(denied.keepsStagedFile)
        XCTAssertEqual(denied.underlyingCode, "E_LIBRARY_PERMISSION")

        let restricted = ExportFailure.map(
            ExportLibraryError.permissionRestricted,
            stage: .requestingAccess
        )
        XCTAssertEqual(restricted.kind, .permissionRestricted)
        XCTAssertEqual(restricted.recoveries, [.shareInstead, .dismiss])

        let unavailable = ExportFailure.map(
            ExportLibraryError.unavailable,
            stage: .requestingAccess
        )
        XCTAssertEqual(unavailable.kind, .photoLibraryUnavailable)
        XCTAssertEqual(unavailable.recoveries, [.shareInstead, .dismiss])

        let save = ExportFailure.map(ExportLibraryError.saveFailed, stage: .savingToLibrary)
        XCTAssertEqual(save.kind, .librarySaveFailed)
        XCTAssertEqual(save.recoveries, [.retry, .shareInstead, .dismiss])
        XCTAssertTrue(save.keepsStagedFile)
    }

    func testPipelineErrorsMapToResolutionOrEncodingFailures() {
        let size = PixelSize(width: 640, height: 480)
        let smaller = PixelSize(width: 320, height: 240)

        let resolution = ExportFailure.map(
            ExportPipelineError.resolutionMismatch(expected: size, actual: smaller),
            stage: .rendering
        )
        XCTAssertEqual(resolution.kind, .resolutionMismatch)
        XCTAssertEqual(resolution.underlyingCode, "E_EXPORT_RESOLUTION")
        XCTAssertFalse(resolution.keepsStagedFile)

        let missing = ExportFailure.map(ExportPipelineError.missingOutput, stage: .encoding)
        XCTAssertEqual(missing.kind, .encodeFailed)

        let mismatch = ExportFailure.map(
            ExportPipelineError.exportSizeMismatch(expected: size, actual: smaller),
            stage: .encoding
        )
        XCTAssertEqual(mismatch.kind, .encodeFailed)

        let format = ExportFailure.map(
            ExportPipelineError.formatMismatch(expected: .heic, actual: .jpeg),
            stage: .encoding
        )
        XCTAssertEqual(format.kind, .encodeFailed)
    }

    func testUnknownErrorsMapToRetryableUnknownFailure() {
        struct CustomError: Error {}
        let failure = ExportFailure.map(CustomError(), stage: .preparing)
        XCTAssertEqual(failure.kind, .unknown)
        XCTAssertEqual(failure.recoveries, [.retry, .dismiss])
        XCTAssertNil(failure.underlyingCode)
    }

    func testDiagnosticCodesAreStableAndContainNoPaths() {
        let failures: [ExportFailure] = [
            ExportFailure.map(StyleToneError.warpingFailed, stage: .rendering),
            ExportFailure.map(StyleToneError.exportFailed, stage: .encoding),
            ExportFailure.map(ExportLibraryError.permissionDenied, stage: .requestingAccess),
            ExportFailure.map(ExportLibraryError.saveFailed, stage: .savingToLibrary),
            ExportFailure.map(ExportLibraryError.unavailable, stage: .requestingAccess),
            ExportFailure.map(StyleToneError.invalidState, stage: .preparing),
        ]

        for failure in failures {
            XCTAssertTrue(
                failure.diagnosticCode.hasPrefix("ST-EXPORT-"),
                "unexpected diagnostic code \(failure.diagnosticCode)"
            )
            XCTAssertFalse(failure.diagnosticCode.contains("/"))
            XCTAssertFalse(failure.diagnosticCode.contains("\\"))
            XCTAssertFalse(failure.diagnosticCode.contains(".heic"))
            XCTAssertFalse(failure.diagnosticCode.contains(".jpg"))
        }
        let codes = failures.map(\.diagnosticCode)
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func testEveryFailureHasTitleMessageAndRecoveries() {
        let failures: [ExportFailure] = [
            ExportFailure.map(StyleToneError.invalidState, stage: .preparing),
            ExportFailure.map(StyleToneError.warpingFailed, stage: .rendering),
            ExportFailure.map(StyleToneError.exportFailed, stage: .encoding),
            ExportFailure.map(ExportLibraryError.permissionDenied, stage: .requestingAccess),
            ExportFailure.map(ExportLibraryError.permissionRestricted, stage: .requestingAccess),
            ExportFailure.map(ExportLibraryError.unavailable, stage: .requestingAccess),
            ExportFailure.map(ExportLibraryError.saveFailed, stage: .savingToLibrary),
            ExportFailure.map(StyleToneError.invalidImage, stage: .rendering),
        ]
        for failure in failures {
            XCTAssertFalse(failure.title.text.isEmpty)
            XCTAssertFalse(failure.message.text.isEmpty)
            XCTAssertFalse(failure.recoveries.isEmpty)
            XCTAssertEqual(
                Set(failure.recoveries.map(\.rawValue)).count,
                failure.recoveries.count,
                "duplicate recovery"
            )
        }
    }

    // MARK: - Value types

    func testProgressClampsAndPercentages() {
        let full = ExportProgress(stage: .rendering, fraction: 1.5)
        XCTAssertEqual(full.fraction, 1)
        XCTAssertEqual(full.percent, 100)

        let negative = ExportProgress(stage: .preparing, fraction: -2)
        XCTAssertEqual(negative.fraction, 0)
        XCTAssertEqual(negative.percent, 0)

        let mid = ExportProgress(stage: .encoding, fraction: 0.625)
        XCTAssertEqual(mid.percent, 63)
    }

    func testEntitlementRules() {
        XCTAssertTrue(ExportEntitlement.free(remaining: 3).canExport)
        XCTAssertEqual(ExportEntitlement.free(remaining: 3).remainingFreeExports, 3)
        XCTAssertFalse(ExportEntitlement.free(remaining: 0).canExport)
        XCTAssertTrue(ExportEntitlement.free(remaining: 0).isExhausted)
        XCTAssertTrue(ExportEntitlement.unlimited.canExport)
        XCTAssertTrue(ExportEntitlement.unlimited.isUnlimited)
        XCTAssertNil(ExportEntitlement.unlimited.remainingFreeExports)
        XCTAssertFalse(ExportEntitlement.exhausted.canExport)

        XCTAssertEqual(ExportEntitlement.freeExports(0), .exhausted)
        XCTAssertEqual(ExportEntitlement.freeExports(-4), .exhausted)
        XCTAssertEqual(ExportEntitlement.freeExports(2), .free(remaining: 2))
    }

    func testQualityClampsAndDefaults() {
        XCTAssertEqual(ExportQuality(id: "low", value: -1).value, 0)
        XCTAssertEqual(ExportQuality(id: "high", value: 4).value, 1)
        XCTAssertEqual(ExportQuality(id: "nan", value: Double.nan).value, 0.92)
        XCTAssertEqual(ExportQuality.all.map(\.id), ["high", "standard", "maximum"])
        XCTAssertEqual(ExportSettings().quality, .high)
        XCTAssertEqual(ExportSettings().format, .heic)
        XCTAssertTrue(ExportSettings().stripLocation)
    }

    func testSettingsBuildCoreOptionsAndExtensions() {
        let settings = ExportSettings(format: .jpeg, quality: .maximum, stripLocation: true)
        let options = settings.options
        XCTAssertEqual(options.format, .jpeg)
        XCTAssertEqual(options.quality, 1.0, accuracy: 0.0001)
        XCTAssertTrue(options.stripLocation)
        XCTAssertEqual(settings.filenameExtension, "jpg")
        XCTAssertEqual(ExportSettings(format: .heic).filenameExtension, "heic")
    }

    func testSourceDerivesSizeMegapixelsAndLargeFlag() throws {
        let request = RenderRequest(
            image: try MockImageAssetFactory.solid(size: PixelSize(width: 64, height: 48)),
            analysis: try MockPortraitAnalysisFactory.portrait(
                size: PixelSize(width: 64, height: 48),
                includesMasks: false
            ),
            style: MockStyleProfileFactory.standard(updatedAt: ExportTestFactory.referenceDate)
        )
        let source = ExportSource(
            request: request,
            expectedPixelSize: PixelSize(width: 4_032, height: 3_024)
        )

        XCTAssertEqual(source.expectedPixelSize, PixelSize(width: 4_032, height: 3_024))
        XCTAssertEqual(source.megapixels, 12.192768, accuracy: 0.0001)
        XCTAssertFalse(source.isLargeImage)
        XCTAssertEqual(source.aspectRatio, 4.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(source.previewImage.pixelSize, PixelSize(width: 64, height: 48))

        let large = ExportSource(
            request: request,
            expectedPixelSize: PixelSize(width: 8_064, height: 6_048)
        )
        XCTAssertTrue(large.isLargeImage)
    }

    func testStagedFileExtensionFollowsFormat() {
        let size = PixelSize(width: 100, height: 200)
        let heic = ExportStagedFile(
            url: URL(fileURLWithPath: "/tmp/a.heic"),
            format: .heic,
            pixelSize: size,
            byteCount: 10,
            createdAt: ExportTestFactory.referenceDate
        )
        let jpeg = ExportStagedFile(
            url: URL(fileURLWithPath: "/tmp/a.jpg"),
            format: .jpeg,
            pixelSize: size,
            byteCount: 10,
            createdAt: ExportTestFactory.referenceDate
        )
        XCTAssertEqual(heic.filenameExtension, "heic")
        XCTAssertEqual(jpeg.filenameExtension, "jpg")
        XCTAssertEqual(heic.byteCount, 10)
    }

    func testPhotoLibraryAccessRules() {
        XCTAssertTrue(PhotoLibraryAccess.authorized.canAddPhotos)
        XCTAssertTrue(PhotoLibraryAccess.limited.canAddPhotos)
        XCTAssertFalse(PhotoLibraryAccess.denied.canAddPhotos)
        XCTAssertFalse(PhotoLibraryAccess.restricted.canAddPhotos)
        XCTAssertFalse(PhotoLibraryAccess.unavailable.canAddPhotos)
        XCTAssertTrue(PhotoLibraryAccess.denied.isDenied)
        XCTAssertTrue(PhotoLibraryAccess.restricted.isDenied)
        XCTAssertFalse(PhotoLibraryAccess.notDetermined.isDenied)
        XCTAssertTrue(PhotoLibraryAccess.notDetermined.canRequestAccess)
        XCTAssertTrue(PhotoLibraryAccess.unavailable.isUnavailable)
    }
}
