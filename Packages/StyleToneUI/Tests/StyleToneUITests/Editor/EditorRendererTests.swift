import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneUI

final class EditorRendererTests: XCTestCase {
    func testNoOpReturnsExactOriginalWithoutInvokingEngines() async throws {
        let image = try EditorTestFactory.image()
        let analysis = try EditorTestFactory.analysis()
        let renderer = EditorRenderer(
            retoucher: MockRetoucher.failing(),
            blemishRemover: MockBlemishRemover.failing(),
            geometryRenderer: MockGeometryRenderer.failing(),
            toneRenderer: EditorFailingToneRenderer(),
            dateProvider: FixedDateProvider()
        )

        let request = RenderRequest(
            image: image,
            analysis: analysis,
            style: MockStyleProfileFactory.natural()
        )
        let output = try await renderer.render(request)

        XCTAssertTrue(output.image.cgImage === image.cgImage)
        XCTAssertTrue(output.warnings.isEmpty)
    }

    func testPipelineOrderIsRetouchBlemishGeometryTone() async throws {
        let log = EditorCallLog()
        let renderer = makeLoggingRenderer(log: log)
        let image = try EditorTestFactory.image()
        let analysis = try EditorTestFactory.analysis()
        let point = BlemishPoint(point: NormalizedPoint(x: 0.4, y: 0.4), radius: 0.02)
        let request = RenderRequest(
            image: image,
            analysis: analysis,
            style: MockStyleProfileFactory.standard(),
            strength: 1.0,
            adjustments: ManualAdjustments(faceSlim: 0.2, smoothing: 0.2),
            backgroundProtection: true,
            blemishPoints: [point]
        )

        _ = try await renderer.render(request)

        let entries = await log.entries
        XCTAssertEqual(entries, ["retouch", "blemish", "geometry:protected", "tone"])
    }

    func testOnlyFaceAdjustmentRunsGeometry() async throws {
        let log = EditorCallLog()
        let renderer = makeLoggingRenderer(log: log)
        var adjustments = ManualAdjustments()
        adjustments.faceSlim = 0.3
        let request = RenderRequest(
            image: try EditorTestFactory.image(),
            analysis: try EditorTestFactory.analysis(),
            style: MockStyleProfileFactory.natural(),
            adjustments: adjustments
        )

        _ = try await renderer.render(request)

        let entries = await log.entries
        XCTAssertEqual(entries, ["geometry:protected"])
    }

    func testOnlyManualSmoothingRunsRetouch() async throws {
        let log = EditorCallLog()
        let renderer = makeLoggingRenderer(log: log)
        var adjustments = ManualAdjustments()
        adjustments.smoothing = 0.3
        let request = RenderRequest(
            image: try EditorTestFactory.image(),
            analysis: try EditorTestFactory.analysis(),
            style: MockStyleProfileFactory.natural(),
            adjustments: adjustments
        )

        _ = try await renderer.render(request)

        let entries = await log.entries
        XCTAssertEqual(entries, ["retouch"])
    }

    func testOnlyManualExposureRunsTone() async throws {
        let log = EditorCallLog()
        let renderer = makeLoggingRenderer(log: log)
        var adjustments = ManualAdjustments()
        adjustments.exposure = 0.4
        let request = RenderRequest(
            image: try EditorTestFactory.image(),
            analysis: try EditorTestFactory.analysis(),
            style: MockStyleProfileFactory.natural(),
            adjustments: adjustments
        )

        _ = try await renderer.render(request)

        let entries = await log.entries
        XCTAssertEqual(entries, ["tone"])
    }

    func testOnlyBlemishPointRunsBlemishStage() async throws {
        let log = EditorCallLog()
        let renderer = makeLoggingRenderer(log: log)
        let point = BlemishPoint(point: NormalizedPoint(x: 0.5, y: 0.5), radius: 0.02)
        let request = RenderRequest(
            image: try EditorTestFactory.image(),
            analysis: try EditorTestFactory.analysis(),
            style: MockStyleProfileFactory.natural(),
            blemishPoints: [point]
        )

        _ = try await renderer.render(request)

        let entries = await log.entries
        XCTAssertEqual(entries, ["blemish"])
    }

    func testBackgroundProtectionOffAddsRiskWarning() async throws {
        let log = EditorCallLog()
        let renderer = makeLoggingRenderer(log: log)
        let request = RenderRequest(
            image: try EditorTestFactory.image(),
            analysis: try EditorTestFactory.analysis(),
            style: MockStyleProfileFactory.standard(),
            backgroundProtection: false
        )

        let output = try await renderer.render(request)

        XCTAssertTrue(output.warnings.contains { $0.kind.rawValue == "backgroundRisk" })
        let entries = await log.entries
        XCTAssertEqual(entries.last, "geometry:open")
    }

    func testAnalysisWarningsAreMappedWithoutUnsupportedKinds() async throws {
        let analysis = try EditorTestFactory.analysis(
            faceCount: 0,
            includesBody: true,
            warnings: [.lowLight]
        )
        let renderer = makeLoggingRenderer(log: EditorCallLog())
        let request = RenderRequest(
            image: try EditorTestFactory.image(),
            analysis: analysis,
            style: MockStyleProfileFactory.natural()
        )

        let output = try await renderer.render(request)

        XCTAssertEqual(output.warnings.count, 1)
        XCTAssertEqual(output.warnings.first?.kind.rawValue, "noFace")
    }

    func testCancellingRetoucherStopsBeforeLaterStages() async throws {
        let log = EditorCallLog()
        let renderer = EditorRenderer(
            retoucher: EditorCancellingRetoucher(),
            blemishRemover: EditorLoggingBlemishRemover(log: log),
            geometryRenderer: EditorLoggingGeometryRenderer(log: log),
            toneRenderer: EditorLoggingToneRenderer(log: log),
            dateProvider: FixedDateProvider()
        )
        let request = RenderRequest(
            image: try EditorTestFactory.image(),
            analysis: try EditorTestFactory.analysis(),
            style: MockStyleProfileFactory.standard()
        )

        do {
            _ = try await renderer.render(request)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let entries = await log.entries
        XCTAssertTrue(entries.isEmpty)
    }

    func testCancellingBlemishRemoverStopsBeforeGeometryAndTone() async throws {
        let log = EditorCallLog()
        let renderer = EditorRenderer(
            retoucher: EditorLoggingRetoucher(log: log),
            blemishRemover: EditorCancellingBlemishRemover(),
            geometryRenderer: EditorLoggingGeometryRenderer(log: log),
            toneRenderer: EditorLoggingToneRenderer(log: log),
            dateProvider: FixedDateProvider()
        )
        let point = BlemishPoint(point: NormalizedPoint(x: 0.5, y: 0.5), radius: 0.02)
        let request = RenderRequest(
            image: try EditorTestFactory.image(),
            analysis: try EditorTestFactory.analysis(),
            style: MockStyleProfileFactory.standard(),
            blemishPoints: [point]
        )

        do {
            _ = try await renderer.render(request)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let entries = await log.entries
        XCTAssertEqual(entries, ["retouch"])
    }

    func testGeometryFailurePropagates() async throws {
        let log = EditorCallLog()
        let renderer = EditorRenderer(
            retoucher: MockRetoucher.passthrough(),
            blemishRemover: MockBlemishRemover.passthrough(),
            geometryRenderer: EditorFailingGeometryRenderer(error: .warpingFailed),
            toneRenderer: EditorLoggingToneRenderer(log: log),
            dateProvider: FixedDateProvider()
        )
        let request = RenderRequest(
            image: try EditorTestFactory.image(),
            analysis: try EditorTestFactory.analysis(),
            style: MockStyleProfileFactory.standard()
        )

        do {
            _ = try await renderer.render(request)
            XCTFail("Expected warping failure")
        } catch let error as StyleToneError {
            XCTAssertEqual(error, .warpingFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let entries = await log.entries
        XCTAssertTrue(entries.isEmpty)
    }

    func testDurationIsMeasuredWithInjectedClock() async throws {
        let reference = EditorTestFactory.referenceDate
        let clock = EditorSteppingDateProvider(
            dates: [reference, reference.addingTimeInterval(1.25)]
        )
        let renderer = EditorRenderer(
            retoucher: MockRetoucher.passthrough(),
            blemishRemover: MockBlemishRemover.passthrough(),
            geometryRenderer: MockGeometryRenderer.passthrough(),
            toneRenderer: PassthroughToneRenderer(),
            dateProvider: clock
        )
        var adjustments = ManualAdjustments()
        adjustments.smoothing = 0.2
        let request = RenderRequest(
            image: try EditorTestFactory.image(),
            analysis: try EditorTestFactory.analysis(),
            style: MockStyleProfileFactory.natural(),
            adjustments: adjustments
        )

        let output = try await renderer.render(request)

        XCTAssertEqual(output.duration, 1.25, accuracy: 0.0001)
    }

    // MARK: - Helpers

    private func makeLoggingRenderer(log: EditorCallLog) -> EditorRenderer {
        EditorRenderer(
            retoucher: EditorLoggingRetoucher(log: log),
            blemishRemover: EditorLoggingBlemishRemover(log: log),
            geometryRenderer: EditorLoggingGeometryRenderer(log: log),
            toneRenderer: EditorLoggingToneRenderer(log: log),
            dateProvider: FixedDateProvider()
        )
    }
}
