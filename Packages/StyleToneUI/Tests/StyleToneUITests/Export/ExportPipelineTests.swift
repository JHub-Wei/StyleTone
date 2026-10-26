import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

/// End-to-end export flows against protocol doubles.
///
/// These tests replace the renderer, encoder, PhotoKit and quota services, so
/// they run on macOS without a simulator or a photo library. They assert the
/// WP-19 contract: full-resolution output, one file handed to the destination,
/// no count on failure/cancel, retry without re-rendering when possible, and no
/// temporary file left behind.
@MainActor
final class ExportPipelineTests: XCTestCase {
    func testSaveExportsFullResolutionSavesTheSameFileAndCleansUp() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportSave")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let library = FakePhotoLibrary()
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            photoLibrary: library,
            quota: quota
        )

        await model.start()
        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.authorization, .authorized)
        XCTAssertEqual(model.entitlement, .free(remaining: 3))

        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.stage, .finished)
        XCTAssertEqual(model.progress?.stage, .finished)
        XCTAssertEqual(model.progress?.fraction, 1.0)
        XCTAssertEqual(model.outcome?.destination, .photoLibrary)
        XCTAssertEqual(model.outcome?.format, ExportTestFactory.defaultFormat)
        XCTAssertEqual(model.outcome?.pixelSize, ExportTestFactory.defaultSize)
        XCTAssertGreaterThan(model.outcome?.byteCount ?? 0, 0)
        XCTAssertEqual(model.outcome?.counted, true)
        XCTAssertFalse(model.outcomeCountPending)
        XCTAssertNil(model.failure)

        let receivedSizes = exporter.receivedPixelSizes
        let written = exporter.writtenURLs
        let saved = await library.savedFiles
        let recordCount = await quota.recordCount
        XCTAssertEqual(receivedSizes, [ExportTestFactory.defaultSize])
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(saved.map(\.url), written)
        XCTAssertEqual(recordCount, 1)

        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty, "temporary file must be removed after saving")
    }

    func testShareWaitsForSystemCompletionBeforeCounting() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportShare")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 2))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.share()
        await model.waitForCompletion()

        XCTAssertEqual(model.stage, .awaitingShare)
        let request = try XCTUnwrap(model.pendingShare)
        let countBefore = await quota.recordCount
        XCTAssertEqual(countBefore, 0)

        let filesBefore = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertEqual(filesBefore.count, 1)

        await model.completeShare(request, completed: true)

        XCTAssertEqual(model.stage, .finished)
        XCTAssertEqual(model.outcome?.destination, .share)
        let countAfter = await quota.recordCount
        XCTAssertEqual(countAfter, 1)
        XCTAssertEqual(model.entitlement, .free(remaining: 1))

        let filesAfter = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(filesAfter.isEmpty)
    }

    func testCancelledShareDoesNotCountAndRemovesTheFile() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportShareCancel")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 2))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.share()
        await model.waitForCompletion()
        let request = try XCTUnwrap(model.pendingShare)
        await model.completeShare(request, completed: false)

        XCTAssertEqual(model.stage, .idle)
        XCTAssertNotNil(model.infoNotice)
        XCTAssertNil(model.outcome)
        let count = await quota.recordCount
        XCTAssertEqual(count, 0)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testShareCompletionSurvivesSwiftUIClearingTheSheetItem() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportShareRace")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 2))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.share()
        await model.waitForCompletion()
        let request = try XCTUnwrap(model.pendingShare)

        // SwiftUI writes nil into the sheet item when the controller dismisses.
        // The completion handler still has to count and clean up.
        model.pendingShare = nil
        await model.completeShare(request, completed: true)

        XCTAssertEqual(model.stage, .finished)
        XCTAssertEqual(model.outcome?.destination, .share)
        let count = await quota.recordCount
        XCTAssertEqual(count, 1)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testPrepareForClosePreservesAPendingShareUntilCompletion() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportCloseShare")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 2))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.share()
        await model.waitForCompletion()
        let request = try XCTUnwrap(model.pendingShare)

        model.prepareForClose()
        XCTAssertEqual(model.stage, .awaitingShare)
        XCTAssertNotNil(model.pendingShare)
        var files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertEqual(files.count, 1)

        await model.completeShare(request, completed: false)
        XCTAssertEqual(model.stage, .idle)
        let count = await quota.recordCount
        XCTAssertEqual(count, 0)
        files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testAbandoningADismissedShareCleansUpWithoutCounting() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportAbandonShare")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 2))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.share()
        await model.waitForCompletion()
        let request = try XCTUnwrap(model.pendingShare)

        // The sheet item is dismissed but the completion handler never arrives.
        model.pendingShare = nil
        model.abandonShareIfPending()

        XCTAssertEqual(model.stage, .idle)
        XCTAssertNotNil(model.infoNotice)
        let count = await quota.recordCount
        XCTAssertEqual(count, 0)

        // A late completion must not resurrect the abandoned request.
        await model.completeShare(request, completed: true)
        let lateCount = await quota.recordCount
        XCTAssertEqual(lateCount, 0)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testRenderFailureIsRetryableAndDoesNotCount() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportRenderFail")
        defer { temp.remove() }

        let renderer = ScriptedRenderer(steps: [.failure(.renderingFailed), .echo])
        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            renderer: renderer,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .renderFailed)
        XCTAssertTrue(model.failure?.recoveries.contains(.retry) ?? false)
        var count = await quota.recordCount
        XCTAssertEqual(count, 0)
        var files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)

        model.retry()
        await model.waitForCompletion()

        XCTAssertEqual(model.stage, .finished)
        XCTAssertNil(model.failure)
        count = await quota.recordCount
        XCTAssertEqual(count, 1)
        files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testEncodeFailureIsRetryableAndDoesNotCount() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportEncodeFail")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url, failures: [.exportFailed, nil])
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .encodeFailed)
        var count = await quota.recordCount
        XCTAssertEqual(count, 0)

        model.retry()
        await model.waitForCompletion()

        XCTAssertEqual(model.stage, .finished)
        count = await quota.recordCount
        XCTAssertEqual(count, 1)
        let calls = exporter.callCount
        XCTAssertEqual(calls, 2)
    }

    func testSaveFailureKeepsTheFileForShareInsteadAndDoesNotCount() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportSaveFail")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let library = FakePhotoLibrary(saveError: .saveFailed)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            photoLibrary: library,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .librarySaveFailed)
        XCTAssertEqual(model.stage, .failed)
        XCTAssertTrue(model.failure?.keepsStagedFile ?? false)
        var count = await quota.recordCount
        XCTAssertEqual(count, 0)
        var files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertEqual(files.count, 1)

        model.shareInstead()
        XCTAssertEqual(model.stage, .awaitingShare)
        let request = try XCTUnwrap(model.pendingShare)
        await model.completeShare(request, completed: true)

        XCTAssertEqual(model.stage, .finished)
        XCTAssertEqual(model.outcome?.destination, .share)
        count = await quota.recordCount
        XCTAssertEqual(count, 1)
        files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testDismissFailureRemovesAStagedFile() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportDismiss")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let library = FakePhotoLibrary(saveError: .saveFailed)
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            photoLibrary: library
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertNotNil(model.failure)

        model.dismissFailure()
        XCTAssertNil(model.failure)
        XCTAssertEqual(model.stage, .idle)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testProxySizedRenderIsRejectedBeforeEncoding() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportProxy")
        defer { temp.remove() }

        let renderer = ScriptedRenderer(
            steps: [.sized(PixelSize(width: 320, height: 240))]
        )
        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            renderer: renderer,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .resolutionMismatch)
        XCTAssertTrue(model.failure?.isRetryable ?? false)
        let exportCalls = exporter.callCount
        XCTAssertEqual(exportCalls, 0)
        let count = await quota.recordCount
        XCTAssertEqual(count, 0)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testExporterSizeMismatchFailsAndCleansTheFile() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportSize")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        exporter.setSizeOverride(PixelSize(width: 320, height: 240))
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .encodeFailed)
        let calls = exporter.callCount
        XCTAssertEqual(calls, 1)
        let count = await quota.recordCount
        XCTAssertEqual(count, 0)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testLyingExporterMetadataIsCaughtByReadingTheEncodedFile() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportLyingMetadata")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        exporter.setSizeOverride(PixelSize(width: 320, height: 240))
        exporter.setReportedSizeOverride(ExportTestFactory.defaultSize)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .encodeFailed)
        let count = await quota.recordCount
        XCTAssertEqual(count, 0)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty, "proxy-sized file must be deleted")
    }

    func testMissingEncodedOutputFailsAndDoesNotCount() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportMissing")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        exporter.setRemovesOutput(true)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .encodeFailed)
        let count = await quota.recordCount
        XCTAssertEqual(count, 0)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testFormatQualityAndLocationOptionsAreForwarded() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportOptions")
        defer { temp.remove() }

        var settings = ExportSettings()
        settings.format = .jpeg
        settings.quality = .standard
        XCTAssertTrue(settings.stripLocation)

        let exporter = FileWritingExporter(directory: temp.url)
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            settings: settings
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()

        let options = exporter.receivedOptions
        let received = try XCTUnwrap(options.last)
        XCTAssertEqual(received.format, .jpeg)
        XCTAssertEqual(received.quality, ExportQuality.standard.value, accuracy: 0.0001)
        XCTAssertTrue(received.stripLocation)

        let written = exporter.writtenURLs
        XCTAssertEqual(written.last?.pathExtension, "jpg")
        XCTAssertEqual(model.outcome?.format, .jpeg)
    }

    func testCancellingDuringRenderLeavesNoFileAndDoesNotCount() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportCancelRender")
        defer { temp.remove() }

        let gate = RenderGate()
        let renderer = GatedRenderer(gate: gate)
        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            renderer: renderer,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        let wait = Task { await model.waitForCompletion() }
        await gate.waitUntilEntered()
        XCTAssertEqual(model.stage, .rendering)
        XCTAssertEqual(model.progress?.stage, .rendering)
        XCTAssertEqual(model.progress?.fraction, 0.10)
        XCTAssertTrue(model.canCancel)

        model.cancel()
        await gate.open()
        await wait.value

        XCTAssertEqual(model.stage, .cancelled)
        XCTAssertNil(model.failure)
        let count = await quota.recordCount
        XCTAssertEqual(count, 0)
        let exportCalls = exporter.callCount
        XCTAssertEqual(exportCalls, 0)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testCancelDuringLibrarySaveIsIgnoredAfterHandoff() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportCancelSave")
        defer { temp.remove() }

        let gate = RenderGate()
        let exporter = FileWritingExporter(directory: temp.url)
        let library = GatedPhotoLibrary(gate: gate)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            photoLibrary: library,
            quota: quota
        )

        await model.start()
        let wait = Task { await model.waitForCompletion() }
        await gate.waitUntilEntered()
        XCTAssertEqual(model.stage, .savingToLibrary)
        XCTAssertEqual(model.progress?.stage, .savingToLibrary)
        XCTAssertEqual(model.progress?.fraction, 0.94)
        XCTAssertFalse(model.canCancel)

        model.cancel()
        await gate.open()
        await wait.value

        XCTAssertEqual(model.stage, .finished)
        XCTAssertEqual(model.progress?.stage, .finished)
        XCTAssertEqual(model.progress?.fraction, 1.0)
        XCTAssertEqual(model.outcome?.destination, .photoLibrary)
        let count = await quota.recordCount
        XCTAssertEqual(count, 1)
        let saved = await library.savedFiles
        XCTAssertEqual(saved.count, 1)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testFreeQuotaDecrementsOnlyAfterEachSuccess() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportQuotaDecrement")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.entitlement, .free(remaining: 2))

        model.share()
        await model.waitForCompletion()
        let request = try XCTUnwrap(model.pendingShare)
        await model.completeShare(request, completed: true)

        XCTAssertEqual(model.entitlement, .free(remaining: 1))
        let count = await quota.recordCount
        XCTAssertEqual(count, 2)
    }

    func testExhaustedQuotaBlocksBeforeRenderingAndOffersUpgrade() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportQuotaExhausted")
        defer { temp.remove() }

        let renderer = ScriptedRenderer()
        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.exhausted)
        let model = try ExportTestFactory.model(
            directory: temp.url,
            renderer: renderer,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        XCTAssertFalse(model.canExport)
        XCTAssertTrue(model.isQuotaExhausted)
        XCTAssertEqual(model.quotaText, ExportCopy.quotaExhausted.text)

        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .quotaExhausted)
        XCTAssertTrue(model.failure?.recoveries.contains(.upgrade) ?? false)
        let renderCalls = await renderer.callCount
        XCTAssertEqual(renderCalls, 0)
        let count = await quota.recordCount
        XCTAssertEqual(count, 0)
    }

    func testQuotaLoadFailureFailsClosedAndCanBeRetried() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportQuotaLoad")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 2), entitlementError: .persistenceFailed)
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        XCTAssertTrue(model.quotaLoadFailed)
        XCTAssertFalse(model.canExport)

        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.failure?.kind, .quotaUnavailable)
        let recoveries = try XCTUnwrap(model.failure?.recoveries)
        XCTAssertEqual(recoveries, [.dismiss], "the quota card owns Check again")
        XCTAssertNil(model.quotaText)

        await quota.setEntitlementError(nil)
        await model.refreshEntitlement()
        XCTAssertFalse(model.quotaLoadFailed)
        XCTAssertNil(model.failure)
        XCTAssertTrue(model.canExport)
        XCTAssertEqual(model.quotaText, "2 free exports left")
    }

    func testQuotaRecordFailureDoesNotTurnDeliveredPhotoIntoAFailure() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportQuotaRecord")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 3), recordError: .persistenceFailed)
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()

        XCTAssertEqual(model.stage, .finished)
        XCTAssertNil(model.failure)
        XCTAssertEqual(model.outcome?.counted, false)
        XCTAssertTrue(model.outcomeCountPending)
        XCTAssertTrue(model.quotaLoadFailed)
        XCTAssertFalse(model.canExport)
        XCTAssertNil(model.quotaText)
        let count = await quota.recordCount
        XCTAssertEqual(count, 1)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)

        // The host can recover by re-reading the authoritative count.
        await quota.setRecordError(nil)
        await model.refreshEntitlement()
        XCTAssertFalse(model.quotaLoadFailed)
        XCTAssertTrue(model.canExport)
    }

    func testShareUnavailableOffersSaveInstead() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportNoShare")
        defer { temp.remove() }

        let renderer = ScriptedRenderer()
        let exporter = FileWritingExporter(directory: temp.url)
        let model = try ExportTestFactory.model(
            directory: temp.url,
            renderer: renderer,
            exporter: exporter,
            supportsShare: false
        )

        await model.start()
        XCTAssertFalse(model.canShare)

        model.share()
        await model.waitForCompletion()

        XCTAssertEqual(model.failure?.kind, .shareUnavailable)
        XCTAssertTrue(model.failure?.recoveries.contains(.saveInstead) ?? false)
        let renderCalls = await renderer.callCount
        XCTAssertEqual(renderCalls, 0)

        model.dismissFailure()
        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.stage, .finished)
    }

    func testStartIsIdempotent() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportStart")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 3))
        let library = FakePhotoLibrary()
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            photoLibrary: library,
            quota: quota
        )

        await model.start()
        await model.start()

        let entitlementCount = await quota.entitlementCount
        let authorizationCount = await library.authorizationCount
        XCTAssertEqual(entitlementCount, 1)
        XCTAssertEqual(authorizationCount, 1)
    }

    func testSecondExportAfterExhaustionIsBlocked() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportLastFree")
        defer { temp.remove() }

        let renderer = ScriptedRenderer()
        let exporter = FileWritingExporter(directory: temp.url)
        let quota = FakeExportQuota(.free(remaining: 1))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            renderer: renderer,
            exporter: exporter,
            quota: quota
        )

        await model.start()
        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.entitlement, .exhausted)
        XCTAssertFalse(model.canExport)

        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.failure?.kind, .quotaExhausted)

        let renderCalls = await renderer.callCount
        let count = await quota.recordCount
        XCTAssertEqual(renderCalls, 1)
        XCTAssertEqual(count, 1)
    }

    func testChangingFormatWhileBusyIsIgnored() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportBusy")
        defer { temp.remove() }

        let gate = RenderGate()
        let renderer = GatedRenderer(gate: gate)
        let exporter = FileWritingExporter(directory: temp.url)
        let model = try ExportTestFactory.model(
            directory: temp.url,
            renderer: renderer,
            exporter: exporter
        )

        await model.start()
        let wait = Task { await model.waitForCompletion() }
        await gate.waitUntilEntered()

        model.format = .jpeg
        model.quality = .standard
        XCTAssertEqual(model.format, ExportTestFactory.defaultFormat)
        XCTAssertEqual(model.quality, .high)

        model.cancel()
        await gate.open()
        await wait.value
    }
}
