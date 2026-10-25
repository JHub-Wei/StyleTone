import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

/// Screen-level composition and complete UI scripts.
///
/// There is no XCUITest bundle in this repository yet (WP-24), so these tests
/// drive the exact view-model sequence the buttons perform and assert the state
/// and identifiers the future UI test will query.
@MainActor
final class ExportScreenTests: XCTestCase {
    func testScreenBuildsWithPlaceholderDependencies() throws {
        let source = try ExportTestFactory.source()
        let viewModel = ExportViewModel(source: source, dependencies: .placeholder)

        _ = ExportScreen(
            viewModel: viewModel,
            onClose: {},
            onUpgrade: {}
        )

        XCTAssertFalse(viewModel.hasLoaded)
        XCTAssertFalse(viewModel.canExport)
        XCTAssertEqual(viewModel.authorization, .notDetermined)
        XCTAssertEqual(viewModel.expectedPixelSize, ExportTestFactory.defaultSize)
        XCTAssertEqual(viewModel.pixelSizeText, "640 × 480")
    }

    func testScreenBuildsFromSourceSettingsAndDependencies() throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportScreenBuild")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let dependencies = ExportTestFactory.dependencies(
            directory: temp.url,
            exporter: exporter
        )

        _ = ExportScreen(
            source: try ExportTestFactory.source(),
            dependencies: dependencies,
            settings: ExportSettings(format: .jpeg),
            onClose: {},
            onUpgrade: {}
        )
    }

    func testPlaceholderDependenciesFailClosedUntilQuotaServiceIsInjected() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportFailClosed")
        defer { temp.remove() }

        let dependencies = ExportTestFactory.dependencies(
            directory: temp.url,
            exporter: FileWritingExporter(directory: temp.url),
            quota: UnavailableExportQuota()
        )
        let model = ExportViewModel(
            source: try ExportTestFactory.source(),
            dependencies: dependencies
        )

        await model.start()

        XCTAssertTrue(model.quotaLoadFailed)
        XCTAssertFalse(model.canExport)
        XCTAssertNil(model.quotaText)

        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.failure?.kind, .quotaUnavailable)
    }

    func testAcceptanceConstants() {
        XCTAssertEqual(ExportAcceptance.twelveMegapixelBudget, 6)
        XCTAssertEqual(ExportAcceptance.largeImageBudget, 20)
        XCTAssertEqual(ExportAcceptance.largeImagePixelCount, 24_000_000)
        XCTAssertEqual(ExportAcceptance.staleTemporaryFileAge, 600)
    }

    func testFlowScriptSaveThenShareCountsEachDeliveredExport() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportScreenFlow")
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
        XCTAssertTrue(model.canSaveToLibrary)
        XCTAssertTrue(model.canShare)
        XCTAssertEqual(model.quotaText, "3 free exports left")

        // 1. Tap "Save to Photos".
        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.stage, .finished)
        XCTAssertEqual(model.outcome?.destination, .photoLibrary)
        XCTAssertEqual(model.outcomeTitle.text, ExportCopy.outcomeSavedTitle.text)
        XCTAssertEqual(model.quotaText, "2 free exports left")

        // 2. Tap "Share".
        model.share()
        await model.waitForCompletion()
        XCTAssertEqual(model.stage, .awaitingShare)
        XCTAssertNotNil(model.pendingShare)
        XCTAssertEqual(model.stageText, ExportCopy.progressAwaitingShare.text)

        // 3. System share completes.
        let request = try XCTUnwrap(model.pendingShare)
        await model.completeShare(request, completed: true)
        XCTAssertEqual(model.stage, .finished)
        XCTAssertEqual(model.outcome?.destination, .share)
        XCTAssertEqual(model.outcomeTitle.text, ExportCopy.outcomeSharedTitle.text)
        XCTAssertEqual(model.quotaText, "1 free export left")

        let count = await quota.recordCount
        XCTAssertEqual(count, 2)
        let files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
    }

    func testFlowScriptPermissionDeniedShareThenRetrySave() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportScreenPermission")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let library = FakePhotoLibrary(status: .denied)
        let quota = FakeExportQuota(.free(remaining: 3))
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            photoLibrary: library,
            quota: quota
        )

        await model.start()
        XCTAssertFalse(model.canSaveToLibrary)
        XCTAssertTrue(model.canShare)

        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.failure?.kind, .permissionDenied)
        XCTAssertTrue(model.failure?.recoveries.contains(.openSettings) ?? false)

        // The permission card / failure card offers "Share instead".
        model.shareInstead()
        await model.waitForCompletion()
        let request = try XCTUnwrap(model.pendingShare)
        await model.completeShare(request, completed: true)
        XCTAssertEqual(model.stage, .finished)

        // Returning from Settings updates access and Retry saves normally.
        await library.setStatus(.authorized)
        await model.refreshAuthorization()
        XCTAssertTrue(model.canSaveToLibrary)

        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.stage, .finished)
        XCTAssertEqual(model.outcome?.destination, .photoLibrary)

        let count = await quota.recordCount
        XCTAssertEqual(count, 2)
    }

    func testFlowScriptQuotaExhaustedOffersUpgrade() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportScreenQuota")
        defer { temp.remove() }

        let exporter = FileWritingExporter(directory: temp.url)
        let model = try ExportTestFactory.model(
            directory: temp.url,
            exporter: exporter,
            quota: FakeExportQuota(.exhausted)
        )

        await model.start()
        XCTAssertTrue(model.isQuotaExhausted)
        XCTAssertFalse(model.canSaveToLibrary)
        XCTAssertFalse(model.canShare)

        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.failure?.kind, .quotaExhausted)
        XCTAssertTrue(model.failure?.recoveries.contains(.upgrade) ?? false)
    }

    func testCloseAfterFailureRemovesTheStagedFile() async throws {
        let temp = try TemporaryDirectory(prefix: "StyleToneExportScreenClose")
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
        var files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertEqual(files.count, 1)

        model.prepareForClose()
        files = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(files.isEmpty)
        XCTAssertEqual(model.stage, .idle)
    }

    func testLargeImageIsFlaggedForTheTimingNote() throws {
        let source = try ExportTestFactory.source(
            size: PixelSize(width: 64, height: 64),
            expectedPixelSize: PixelSize(width: 6_000, height: 4_000)
        )
        let model = ExportViewModel(source: source, dependencies: .placeholder)

        XCTAssertTrue(model.isLargeImage)
        XCTAssertEqual(model.megapixelsText, "24.0 MP")
        XCTAssertEqual(model.pixelSizeText, "6000 × 4000")
    }
}
