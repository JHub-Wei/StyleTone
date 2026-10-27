import Foundation
import PerformanceKit
import StyleToneCore
import StyleToneGeometry
import StyleToneUI
import TestShared
import XCTest

/// End-to-end slider latency: edit state → proxy → real Metal warp → display.
///
/// Uses the real `EditorViewModel`, `EditorRenderPipeline`,
/// `EditorPreviewPreparer` and geometry engine; only the analyzer, retouch,
/// blemish and tone stages are doubles. This is the closest in-process proxy for
/// the contracts §10 "slider response ≤100 ms" target without a UI harness.
@MainActor
final class SliderResponsePerformanceTests: XCTestCase {
    func testSliderPreviewResponse() async throws {
        let engine = makeSyntheticGeometryEngine(quality: .preview)
        guard await engine.isGPUAccelerated else {
            throw XCTSkip("Metal device unavailable; preview latency is not meaningful")
        }

        let scenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "preview.sliderResponse")
        )
        let session = try PerformanceSession(source: "SliderResponsePerformanceTests")
        defer { session.finish() }

        let size = PixelSize(width: 4_032, height: 3_024)
        let image = try PerformanceFixtures.gradientImage(size: size)
        let analysis = try PerformanceFixtures.analysis(
            size: size,
            includesMasks: false
        )

        let model = EditorViewModel(
            dependencies: EditorDependencies(
                analyzer: MockPortraitAnalyzer(analysis: analysis),
                retoucher: MockRetoucher.passthrough(),
                blemishRemover: MockBlemishRemover.passthrough(),
                geometryRenderer: engine,
                exporter: MockImageExporter.succeeding(),
                previewPreparer: EditorPreviewPreparer(),
                styleProvider: StaticEditorStyleProvider(style: .editorNaturalDefault),
                logger: NoopLogger()
            )
        )
        await model.load(image: image)
        XCTAssertTrue(model.isReadyForEditing)
        XCTAssertTrue(model.canEdit)

        model.beginInteraction()
        var values: [Double] = []
        let clock = ContinuousClock()

        // Two unrecorded warm-up previews so the proxy cache and Metal pipeline
        // are ready before the measurement.
        for value in [0.30, 0.35] {
            model.setAdjustment(.faceSlim, to: value)
            await model.waitForRenderIdle()
        }

        for index in 0 ..< 12 {
            let value = index.isMultiple(of: 2) ? 0.50 : 0.60
            let start = clock.now
            model.setAdjustment(.faceSlim, to: value)
            await model.waitForRenderIdle()
            values.append(PerformanceStatistics.seconds(clock.now - start))
        }

        model.cancelInteraction()
        model.cancelRendering()
        await model.waitForRenderIdle()

        let measurement = try PerformanceMeasurement(
            scenarioID: scenario.id,
            unit: .seconds,
            values: values
        )
        session.record(
            measurement,
            scenario: scenario,
            notes: "12 MP source → 1280 proxy → Metal preview; performanceLevel="
                + model.performanceLevel.rawValue
        )

        if PerformanceTestProfile.enforcesContractBudget {
            XCTAssertLessThanOrEqual(
                measurement.p95,
                0.1,
                "slider response p95 \(measurement.p95)s exceeds 100 ms: "
                    + measurement.summary
            )
        }
    }
}
