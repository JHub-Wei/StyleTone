import Foundation
import PerformanceKit
import StyleToneCore
import StyleToneUI
import XCTest

/// Cancellation latency: a new photo or leaving the screen must stop pixel work
/// quickly and must never deliver a stale frame.
@MainActor
final class CancellationPerformanceTests: XCTestCase {
    func testCancelAllStopsAnInFlightRender() async throws {
        let scenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "cancellation.latency")
        )
        let session = try PerformanceSession(source: "CancellationPerformanceTests")
        defer { session.finish() }

        let size = PixelSize(width: 128, height: 128)
        let image = try PerformanceFixtures.gradientImage(size: size)
        let analysis = try PerformanceFixtures.analysis(
            size: size,
            includesMasks: false
        )
        let request = RenderRequest(
            image: image,
            analysis: analysis,
            style: PerformanceFixtures.style()
        )

        var values: [Double] = []
        let clock = ContinuousClock()

        for iteration in 0 ..< 5 {
            var deliveredCompletions = 0
            let pipeline = EditorRenderPipeline(
                renderer: HangingRenderer(),
                handler: { _ in deliveredCompletions += 1 }
            )
            pipeline.submit(
                EditorRenderJob(
                    id: iteration + 1,
                    quality: .full,
                    request: request,
                    previewLongEdge: 0
                )
            )
            let active = await waitForActiveRender(pipeline)
            XCTAssertTrue(active, "render \(iteration) never became active")

            let start = clock.now
            pipeline.cancelAll()
            await pipeline.waitForIdle()
            values.append(PerformanceStatistics.seconds(clock.now - start))
            XCTAssertEqual(
                deliveredCompletions,
                0,
                "cancelled render \(iteration) delivered a completion"
            )
        }

        let measurement = try PerformanceMeasurement(
            scenarioID: scenario.id,
            unit: .seconds,
            values: values
        )
        session.recordAndAssertContract(
            measurement,
            scenario: scenario,
            contract: 0.25,
            notes: "cancelAll → waitForIdle; no completion delivered"
        )
    }
}

/// A render that can only finish by being cancelled.
private struct HangingRenderer: ImageRendering {
    func render(_ request: RenderRequest) async throws -> RenderOutput {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return RenderOutput(image: request.image)
    }
}
