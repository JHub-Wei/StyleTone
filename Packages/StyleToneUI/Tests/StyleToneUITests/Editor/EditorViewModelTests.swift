import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneUI

@MainActor
final class EditorViewModelTests: XCTestCase {
    // MARK: - No-op and export

    func testNeutralLoadDisplaysOriginalAndExportsIt() async throws {
        let renderer = EditorRecordingRenderer()
        let exporter = EditorRecordingExporter()
        let (model, image, _) = try await loaded(renderer: renderer, exporter: exporter)

        let displayed = try XCTUnwrap(model.displayedImage)
        XCTAssertTrue(displayed.cgImage === image.cgImage)
        XCTAssertEqual(model.displayedQuality, .full)
        XCTAssertEqual(model.renderState, .ready(.full))
        XCTAssertTrue(model.isReadyForEditing)
        XCTAssertTrue(model.warnings.isEmpty)

        let calls = await renderer.callCount
        XCTAssertEqual(calls, 0)

        let result = try await model.export()
        XCTAssertEqual(result.pixelSize, image.pixelSize)
        XCTAssertEqual(model.exportState, .completed)
        XCTAssertNotNil(model.lastExport)

        let exportedImages = await exporter.images
        let exported = try XCTUnwrap(exportedImages.first)
        XCTAssertTrue(exported.cgImage === image.cgImage)
    }

    func testZeroStrengthReturnsOriginalEvenWithStyledProfile() async throws {
        let renderer = EditorRecordingRenderer()
        let exporter = EditorRecordingExporter()
        let (model, image, _) = try await loaded(
            renderer: renderer,
            exporter: exporter,
            style: MockStyleProfileFactory.standard()
        )

        let initialCalls = await renderer.callCount
        XCTAssertEqual(initialCalls, 1)

        model.setStrength(0)
        await model.waitForRenderIdle()

        let displayed = try XCTUnwrap(model.displayedImage)
        XCTAssertTrue(displayed.cgImage === image.cgImage)
        XCTAssertEqual(model.displayedQuality, .full)

        let callsAfterReset = await renderer.callCount
        XCTAssertEqual(callsAfterReset, 1)

        _ = try await model.export()
        let exportedImages = await exporter.images
        let exported = try XCTUnwrap(exportedImages.first)
        XCTAssertTrue(exported.cgImage === image.cgImage)
    }

    func testStyledProfileRendersOnLoadAndExportReusesFullImage() async throws {
        let renderer = EditorRecordingRenderer()
        let exporter = EditorRecordingExporter()
        let (model, image, _) = try await loaded(
            renderer: renderer,
            exporter: exporter,
            style: MockStyleProfileFactory.standard()
        )

        let callsAfterLoad = await renderer.callCount
        XCTAssertEqual(callsAfterLoad, 1)
        let displayed = try XCTUnwrap(model.displayedImage)
        XCTAssertEqual(displayed.pixelSize, image.pixelSize)
        XCTAssertEqual(model.displayedQuality, .full)

        _ = try await model.export()

        let callsAfterExport = await renderer.callCount
        XCTAssertEqual(callsAfterExport, 1)
        let exportedImages = await exporter.images
        let exported = try XCTUnwrap(exportedImages.first)
        XCTAssertTrue(exported.cgImage === displayed.cgImage)
    }

    // MARK: - Preview pipeline

    func testSliderDragUsesProxyThenFullQualityAndIsOneUndoStep() async throws {
        let renderer = EditorRecordingRenderer()
        let (model, image, _) = try await loaded(renderer: renderer)

        model.beginInteraction()
        model.setAdjustment(.faceSlim, to: 0.2)
        await model.waitForRenderIdle()

        XCTAssertEqual(model.displayedQuality, .preview)
        XCTAssertEqual(
            try XCTUnwrap(model.displayedImage).pixelSize,
            EditorTestFactory.previewSize
        )

        var requests = await renderer.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].image.pixelSize, EditorTestFactory.previewSize)
        XCTAssertEqual(requests[0].analysis.imageSize, EditorTestFactory.previewSize)

        model.endInteraction()
        await model.waitForRenderIdle()

        XCTAssertEqual(model.displayedQuality, .full)
        XCTAssertEqual(try XCTUnwrap(model.displayedImage).pixelSize, image.pixelSize)
        XCTAssertEqual(model.undoCount, 1)

        requests = await renderer.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].image.pixelSize, image.pixelSize)
        XCTAssertEqual(requests[1].analysis.imageSize, image.pixelSize)

        model.undo()
        await model.waitForRenderIdle()
        XCTAssertEqual(model.edits.adjustments.faceSlim, 0, accuracy: 0.0001)
    }

    func testCancelInteractionRestoresBaselineWithoutHistory() async throws {
        let renderer = EditorRecordingRenderer()
        let (model, image, _) = try await loaded(renderer: renderer)

        model.beginInteraction()
        model.setAdjustment(.faceSlim, to: 0.5)
        await model.waitForRenderIdle()

        model.cancelInteraction()
        await model.waitForRenderIdle()

        XCTAssertEqual(model.edits.adjustments.faceSlim, 0, accuracy: 0.0001)
        XCTAssertEqual(model.undoCount, 0)
        XCTAssertTrue(try XCTUnwrap(model.displayedImage).cgImage === image.cgImage)
    }

    func testStalePreviewCannotOverwriteNewerPreview() async throws {
        let renderer = EditorGatedRenderer()
        let (model, image, _) = try await loaded(renderer: renderer)

        model.beginInteraction()
        model.setAdjustment(.faceSlim, to: 0.2)
        await renderer.waitForRequestCount(1)

        model.setAdjustment(.faceSlim, to: 0.4)
        await renderer.releaseNext()
        await renderer.waitForRequestCount(2)

        // The first preview is stale and must not be committed.
        XCTAssertTrue(try XCTUnwrap(model.displayedImage).cgImage === image.cgImage)

        await renderer.releaseNext()
        await model.waitForRenderIdle()

        XCTAssertEqual(model.displayedQuality, .preview)
        XCTAssertEqual(model.edits.adjustments.faceSlim, 0.4, accuracy: 0.0001)
        XCTAssertEqual(
            try XCTUnwrap(model.displayedImage).pixelSize,
            EditorTestFactory.previewSize
        )

        model.endInteraction()
        await renderer.waitForRequestCount(3)
        await renderer.releaseNext()
        await model.waitForRenderIdle()

        XCTAssertEqual(model.displayedQuality, .full)
        XCTAssertEqual(try XCTUnwrap(model.displayedImage).pixelSize, image.pixelSize)
    }

    func testFullQualitySubmissionCancelsInFlightPreview() async throws {
        let renderer = EditorGatedRenderer()
        let (model, image, _) = try await loaded(renderer: renderer)

        model.beginInteraction()
        model.setAdjustment(.faceSlim, to: 0.3)
        await renderer.waitForRequestCount(1)

        model.endInteraction()
        await renderer.releaseNext()
        await renderer.waitForRequestCount(2)

        // The canceled preview never reached the display.
        XCTAssertTrue(try XCTUnwrap(model.displayedImage).cgImage === image.cgImage)
        XCTAssertEqual(model.displayedQuality, .full)

        await renderer.releaseNext()
        await model.waitForRenderIdle()

        let displayed = try XCTUnwrap(model.displayedImage)
        XCTAssertEqual(model.displayedQuality, .full)
        XCTAssertEqual(displayed.pixelSize, image.pixelSize)
        XCTAssertFalse(displayed.cgImage === image.cgImage)
    }

    // MARK: - Errors and recovery

    func testRenderFailureKeepsPreviousImageAndRecoveryRendersFullQuality() async throws {
        let renderer = EditorRecordingRenderer()
        let errors: [StyleToneError?] = [.renderingFailed, nil]
        await renderer.setErrors(errors)
        let (model, image, _) = try await loaded(renderer: renderer)

        model.beginInteraction()
        model.setAdjustment(.faceSlim, to: 0.2)
        await model.waitForRenderIdle()

        XCTAssertEqual(model.renderState, .failed)
        XCTAssertTrue(try XCTUnwrap(model.displayedImage).cgImage === image.cgImage)
        XCTAssertEqual(model.issue?.recovery, .retryRender)

        await model.recover()
        await model.waitForRenderIdle()

        XCTAssertNil(model.issue)
        XCTAssertEqual(model.displayedQuality, .full)
        XCTAssertEqual(model.renderState, .ready(.full))
    }

    func testExportDoesNotReachExporterWhenRenderFails() async throws {
        let renderer = EditorRecordingRenderer()
        let errors: [StyleToneError?] = Array(
            repeating: Optional(StyleToneError.renderingFailed),
            count: 10
        )
        await renderer.setErrors(errors)
        let exporter = EditorRecordingExporter()
        let (model, _, _) = try await loaded(renderer: renderer, exporter: exporter)

        model.setAdjustment(.faceSlim, to: 0.3)
        await model.waitForRenderIdle()
        XCTAssertEqual(model.renderState, .failed)

        do {
            _ = try await model.export()
            XCTFail("Expected the render failure to abort export")
        } catch {
            // Expected.
        }

        let exporterCalls = await exporter.callCount
        XCTAssertEqual(exporterCalls, 0)
        XCTAssertEqual(model.issue?.recovery, .retryRender)
    }

    func testExporterFailureSurfacesRecoverableIssue() async throws {
        let renderer = EditorRecordingRenderer()
        let exporter = EditorRecordingExporter()
        await exporter.setError(.exportFailed)
        let (model, _, _) = try await loaded(renderer: renderer, exporter: exporter)

        do {
            _ = try await model.export()
            XCTFail("Expected export failure")
        } catch {
            // Expected.
        }

        XCTAssertNil(model.lastExport)
        XCTAssertEqual(model.exportState, .failed)
        XCTAssertEqual(model.issue?.recovery, .retryExport)
    }

    func testAnalysisFailureFallsBackAndRecoveryReanalyzes() async throws {
        let image = try EditorTestFactory.image()
        let analysis = try EditorTestFactory.analysis()
        let analyzer = EditorScriptedAnalyzer(
            steps: [.failure(.imageAnalysisFailed), .success(analysis)]
        )
        let model = EditorViewModel(
            dependencies: EditorDependencies(
                analyzer: analyzer,
                renderer: EditorRecordingRenderer(),
                exporter: EditorRecordingExporter(),
                previewPreparer: EditorStubPreviewPreparer(size: EditorTestFactory.previewSize),
                styleProvider: StaticEditorStyleProvider(),
                dateProvider: FixedDateProvider(),
                logger: NoopLogger()
            )
        )

        await model.load(image: image)
        await model.waitForRenderIdle()

        XCTAssertEqual(model.issue?.recovery, .retryAnalysis)
        XCTAssertTrue(model.isReadyForEditing)
        XCTAssertEqual(model.analysis?.hasFace, false)
        let firstCalls = await analyzer.callCount
        XCTAssertEqual(firstCalls, 1)

        await model.recover()
        await model.waitForRenderIdle()

        XCTAssertNil(model.issue)
        XCTAssertEqual(model.analysis?.hasFace, true)
        let secondCalls = await analyzer.callCount
        XCTAssertEqual(secondCalls, 2)
    }

    // MARK: - Undo, redo, reset

    func testUndoRedoSupportsAtLeastTwentySteps() async throws {
        let renderer = EditorRecordingRenderer()
        let (model, _, _) = try await loaded(renderer: renderer)

        for index in 1...25 {
            model.setStrength(1.0 + Double(index) / 100)
        }
        await model.waitForRenderIdle()

        XCTAssertEqual(model.undoCount, 25)

        for _ in 0..<20 {
            model.undo()
        }
        await model.waitForRenderIdle()

        XCTAssertEqual(model.edits.strength, 1.05, accuracy: 0.0001)
        XCTAssertEqual(model.undoCount, 5)
        XCTAssertEqual(model.redoCount, 20)

        for _ in 0..<5 {
            model.undo()
        }
        for _ in 0..<25 {
            model.redo()
        }
        await model.waitForRenderIdle()

        XCTAssertEqual(model.edits.strength, 1.25, accuracy: 0.0001)
        XCTAssertFalse(model.canRedo)
    }

    func testNaturalPresetAndReset() async throws {
        let renderer = EditorRecordingRenderer()
        let (model, image, _) = try await loaded(
            renderer: renderer,
            style: MockStyleProfileFactory.standard()
        )

        model.setStrength(1.2)
        model.applyNaturalPreset()
        XCTAssertEqual(model.edits.strength, EditorEditState.naturalStrength, accuracy: 0.0001)

        model.undo()
        await model.waitForRenderIdle()
        XCTAssertEqual(model.edits.strength, 1.2, accuracy: 0.0001)

        model.setAdjustment(.faceSlim, to: 0.4)
        await model.waitForRenderIdle()
        model.reset()
        await model.waitForRenderIdle()

        XCTAssertEqual(model.edits, .original)
        XCTAssertTrue(try XCTUnwrap(model.displayedImage).cgImage === image.cgImage)

        model.undo()
        await model.waitForRenderIdle()
        XCTAssertEqual(model.edits.adjustments.faceSlim, 0.4, accuracy: 0.0001)
    }

    // MARK: - Background protection and blemish points

    func testBackgroundProtectionRequiresConfirmationAndShowsRisk() async throws {
        let renderer = EditorRecordingRenderer()
        let (model, _, _) = try await loaded(renderer: renderer)

        model.setAdjustment(.faceSlim, to: 0.3)
        await model.waitForRenderIdle()

        XCTAssertTrue(model.edits.backgroundProtection)
        model.requestBackgroundProtection(false)
        XCTAssertTrue(model.pendingBackgroundProtectionDisable)
        XCTAssertTrue(model.edits.backgroundProtection)

        model.cancelBackgroundProtectionDisable()
        XCTAssertFalse(model.pendingBackgroundProtectionDisable)
        XCTAssertTrue(model.edits.backgroundProtection)

        model.requestBackgroundProtection(false)
        model.confirmBackgroundProtectionDisable()
        await model.waitForRenderIdle()

        XCTAssertFalse(model.edits.backgroundProtection)
        XCTAssertTrue(model.warnings.contains { $0.kind == .backgroundRisk })

        let requests = await renderer.requests
        XCTAssertEqual(requests.last?.backgroundProtection, false)

        model.undo()
        await model.waitForRenderIdle()
        XCTAssertTrue(model.edits.backgroundProtection)
    }

    func testBlemishPointsArePassedRemovedAndUndoable() async throws {
        let renderer = EditorRecordingRenderer()
        let (model, _, _) = try await loaded(renderer: renderer)

        model.addBlemishPoint(at: NormalizedPoint(x: 0.4, y: 0.4), radius: 0.02)
        await model.waitForRenderIdle()

        var requests = await renderer.requests
        XCTAssertEqual(requests.last?.blemishPoints.count, 1)
        XCTAssertEqual(requests.last?.blemishPoints.first?.point.x ?? -1, 0.4, accuracy: 0.0001)

        // The same point twice is a no-op.
        model.addBlemishPoint(at: NormalizedPoint(x: 0.401, y: 0.401), radius: 0.02)
        await model.waitForRenderIdle()
        XCTAssertEqual(model.edits.blemishPoints.count, 1)

        model.removeLastBlemishPoint()
        await model.waitForRenderIdle()
        XCTAssertTrue(model.edits.blemishPoints.isEmpty)
        XCTAssertEqual(model.undoCount, 2)

        model.undo()
        await model.waitForRenderIdle()
        XCTAssertEqual(model.edits.blemishPoints.count, 1)

        requests = await renderer.requests
        XCTAssertEqual(requests.last?.blemishPoints.count, 1)
    }

    // MARK: - Scene warnings and tool availability

    func testNoFaceDisablesFaceAndSkinToolsAndWarns() async throws {
        let renderer = EditorRecordingRenderer()
        let analysis = try EditorTestFactory.analysis(faceCount: 0, includesBody: true)
        let (model, _, _) = try await loaded(renderer: renderer, analysis: analysis)

        XCTAssertFalse(model.isAdjustmentEnabled(.faceSlim))
        XCTAssertFalse(model.isAdjustmentEnabled(.smoothing))
        XCTAssertTrue(model.isAdjustmentEnabled(.waist))
        XCTAssertTrue(model.isAdjustmentEnabled(.exposure))
        XCTAssertTrue(model.warnings.contains { $0.kind == .noFace })
        XCTAssertNotEqual(model.selectedArea, .face)

        model.selectArea(.face)
        XCTAssertNotEqual(model.selectedArea, .face)

        model.setAdjustment(.faceSlim, to: 0.4)
        await model.waitForRenderIdle()

        let calls = await renderer.callCount
        XCTAssertEqual(calls, 0)
    }

    func testNoBodyDisablesBodyTools() async throws {
        let renderer = EditorRecordingRenderer()
        let analysis = try EditorTestFactory.analysis(faceCount: 1, includesBody: false)
        let (model, _, _) = try await loaded(renderer: renderer, analysis: analysis)

        XCTAssertTrue(model.isAdjustmentEnabled(.faceSlim))
        XCTAssertFalse(model.isAdjustmentEnabled(.waist))
        XCTAssertTrue(model.warnings.contains { $0.kind == .noBody })
    }

    // MARK: - Comparison and zoom

    func testComparisonAndZoomStateIsClamped() async throws {
        let renderer = EditorRecordingRenderer()
        let (model, _, _) = try await loaded(renderer: renderer)

        model.setShowingOriginal(true)
        XCTAssertTrue(model.isShowingOriginal)
        model.setShowingOriginal(false)

        model.toggleSplitComparison()
        XCTAssertTrue(model.isSplitComparisonEnabled)
        model.setSplitPosition(-1)
        XCTAssertEqual(model.splitPosition, 0.05, accuracy: 0.0001)
        model.setSplitPosition(2)
        XCTAssertEqual(model.splitPosition, 0.95, accuracy: 0.0001)
        model.toggleSplitComparison()
        XCTAssertFalse(model.isSplitComparisonEnabled)

        model.setZoomScale(10)
        XCTAssertEqual(model.zoom.scale, 4, accuracy: 0.0001)
        model.panBy(x: 10, y: -10)
        XCTAssertEqual(model.zoom.offsetX, 1, accuracy: 0.0001)
        XCTAssertEqual(model.zoom.offsetY, -1, accuracy: 0.0001)
        model.resetZoom()
        XCTAssertEqual(model.zoom.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(model.zoom.offsetX, 0, accuracy: 0.0001)

        model.toggleZoom()
        XCTAssertEqual(model.zoom.scale, 2, accuracy: 0.0001)
        model.toggleZoom()
        XCTAssertEqual(model.zoom.scale, 1, accuracy: 0.0001)
    }

    // MARK: - Performance

    func testSlowPreviewsDegradeAndFastPreviewsRecover() async throws {
        let renderer = EditorRecordingRenderer()
        await renderer.setDurations([0.5, 0.5, 0.02, 0.02, 0.02])
        let (model, _, _) = try await loaded(renderer: renderer)

        XCTAssertEqual(model.performanceLevel, .full)

        model.beginInteraction()
        model.setAdjustment(.faceSlim, to: 0.1)
        await model.waitForRenderIdle()
        model.setAdjustment(.faceSlim, to: 0.2)
        await model.waitForRenderIdle()
        XCTAssertEqual(model.performanceLevel, .reduced)
        XCTAssertTrue(model.isPerformanceDegraded)

        model.setAdjustment(.faceSlim, to: 0.3)
        await model.waitForRenderIdle()
        model.setAdjustment(.faceSlim, to: 0.4)
        await model.waitForRenderIdle()
        XCTAssertEqual(model.performanceLevel, .reduced)

        model.setAdjustment(.faceSlim, to: 0.5)
        await model.waitForRenderIdle()
        XCTAssertEqual(model.performanceLevel, .full)

        model.endInteraction()
        await model.waitForRenderIdle()
    }

    // MARK: - Helpers

    private func loaded(
        renderer: any ImageRendering,
        exporter: any ImageExporting = EditorRecordingExporter(),
        style: StyleProfile = .editorNaturalDefault,
        analysis: PortraitAnalysis? = nil
    ) async throws -> (EditorViewModel, ImageAsset, PortraitAnalysis) {
        try await EditorTestFactory.loadedViewModel(
            renderer: renderer,
            exporter: exporter,
            style: style,
            analysis: analysis
        )
    }
}
