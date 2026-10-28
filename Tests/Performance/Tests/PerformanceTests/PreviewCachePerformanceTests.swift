import Foundation
import PerformanceKit
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

/// Preview proxy scaling and cache behavior.
///
/// WP-17 caches one proxy per source image and tier. A cache miss would rescale
/// every mask on every slider tick, which is the main reason a fast device can
/// still feel sluggish with masks enabled.
final class PreviewCachePerformanceTests: XCTestCase {
    func testProxyCacheHitAvoidsRescaling() async throws {
        let scenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "preview.proxyCacheHit")
        )
        let session = try PerformanceSession(source: "PreviewCachePerformanceTests")
        defer { session.finish(test: self) }

        let image = try PerformanceFixtures.gradientImage(
            size: PixelSize(width: 2_048, height: 1_536)
        )
        let analysis = try PerformanceFixtures.analysis(
            size: image.pixelSize,
            includesMasks: true
        )
        let scaler = CountingPreviewScaler()
        let preparer = EditorPreviewPreparer(scaler: scaler)

        let first = try await preparer.preparePreview(
            image: image,
            analysis: analysis,
            maximumLongEdge: 1_280
        )
        XCTAssertEqual(first.image.pixelSize.longEdge, 1_280)
        let firstCount = await preparer.preparationCount
        XCTAssertEqual(firstCount, 1)

        let measurement = try await PerformanceClock.measureAsync(
            scenario: scenario,
            iterations: 10,
            warmUpIterations: 1
        ) {
            _ = try await preparer.preparePreview(
                image: image,
                analysis: analysis,
                maximumLongEdge: 1_280
            )
        }

        let finalCount = await preparer.preparationCount
        XCTAssertEqual(finalCount, 1, "repeated previews must hit the cache")
        XCTAssertEqual(scaler.invocationCount, 1, "the scaler ran more than once")

        session.record(
            measurement,
            scenario: scenario,
            notes: "one scaler invocation for 11 preparations"
        )
    }

    func testProxyScaleCost() throws {
        let scenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "preview.proxyScale")
        )
        let session = try PerformanceSession(source: "PreviewScalePerformanceTests")
        defer { session.finish(test: self) }

        let image = try PerformanceFixtures.gradientImage(
            size: PixelSize(width: 2_048, height: 1_536)
        )
        let analysis = try PerformanceFixtures.analysis(
            size: image.pixelSize,
            includesMasks: true
        )
        let scaler = CoreGraphicsPreviewScaler()

        let measurement = try PerformanceClock.measure(
            scenario: scenario,
            iterations: 5,
            warmUpIterations: 1
        ) {
            let context = try scaler.preparePreview(
                image: image,
                analysis: analysis,
                maximumLongEdge: 1_280
            )
            XCTAssertEqual(context.image.pixelSize.longEdge, 1_280)
        }

        session.record(
            measurement,
            scenario: scenario,
            notes: "2048 image + 3 masks → 1280 preview"
        )
    }
}
