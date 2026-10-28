import Foundation
import PerformanceKit
import StyleToneCore
import StyleToneImaging
import StyleToneUI
import TestShared
import XCTest

/// Preview memory budget (contracts §10: ≤300 MB).
///
/// The scenario keeps the source proxy, its full-size masks and the editor
/// preview alive at the same time, which is the worst case while a slider is
/// being dragged. The CI value is a peak delta because the XCTest host already
/// owns memory; a reference-device run records absolute `phys_footprint`.
final class MemoryPerformanceTests: XCTestCase {
    func testPreviewMemoryPeak() async throws {
        let scenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "preview.memoryPeak")
        )
        let session = try PerformanceSession(source: "MemoryPerformanceTests")
        defer { session.finish(test: self) }

        let temp = try TemporaryDirectory(prefix: "StyleTonePerfMemory")
        defer { temp.remove() }
        let size = PixelSize(width: 4_032, height: 3_024)
        let url = temp.url.appendingPathComponent("12mp.jpg")
        try PerformanceFixtures.jpegData(size: size).write(to: url)

        let probe = LockedMemoryProbe(reader: DarwinMemoryFootprintReader())
        try probe.start()

        let proxy = try await ImageLoader().load(url: url, options: .preview)
        try probe.sample()
        XCTAssertEqual(proxy.pixelSize.longEdge, 2_048)

        let analysis = try PerformanceFixtures.analysis(
            size: proxy.pixelSize,
            includesMasks: true
        )
        try probe.sample()

        let scaler = CoreGraphicsPreviewScaler()
        let context = try scaler.preparePreview(
            image: proxy,
            analysis: analysis,
            maximumLongEdge: 1_280
        )
        try probe.sample()

        // Keep the displayed state alive until the peak has been sampled.
        withExtendedLifetime((proxy, analysis, context)) {
            XCTAssertEqual(context.image.pixelSize.longEdge, 1_280)
        }

        let measurement = try probe.measurement(
            scenarioID: scenario.id,
            absolute: PerformanceTestEnvironment.isReferenceDevice
        )
        session.recordAndAssertContract(
            measurement,
            scenario: scenario,
            contract: 300,
            notes: PerformanceTestEnvironment.isReferenceDevice
                ? "absolute phys_footprint peak"
                : "peak delta: 12 MP JPEG → 2048 preview + masks → 1280 editor proxy"
        )
    }
}
