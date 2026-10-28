import Foundation
import PerformanceKit
import StyleToneCore
import StyleToneImaging
import StyleToneUI
import TestShared
import XCTest

/// First-frame budget: decode a 12 MP photo into the 2048 px preview and build
/// the 1280 px editor proxy. Display assignment is synchronous after this work,
/// so this is the dominant part of the contracts §10 first-frame target.
///
/// Real device runs should record a cold-launch XCUITest / Instruments trace in
/// addition; the method string in the scenario describes that split.
final class FirstFramePerformanceTests: XCTestCase {
    func testTwelveMegapixelFirstFrame() async throws {
        let scenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "preview.firstFrame")
        )
        let session = try PerformanceSession(source: "FirstFramePerformanceTests")
        defer { session.finish(test: self) }

        let temp = try TemporaryDirectory(prefix: "StyleTonePerfFirstFrame")
        defer { temp.remove() }

        let size = PixelSize(width: 4_032, height: 3_024)
        let url = temp.url.appendingPathComponent("12mp.jpg")
        try PerformanceFixtures.jpegData(size: size).write(to: url)

        let loader = ImageLoader()
        // Warm the ImageIO decoder and the file cache; this run is not recorded.
        let warm = try await loader.load(url: url, options: .preview)
        XCTAssertEqual(warm.pixelSize.longEdge, 2_048)

        // Analysis is precomputed at the proxy size: the first frame only has to
        // scale the image and masks, not run Vision.
        let analysis = try PerformanceFixtures.analysis(
            size: warm.pixelSize,
            includesMasks: true
        )
        let scaler = CoreGraphicsPreviewScaler()

        let measurement = try await PerformanceClock.measureAsync(
            scenario: scenario,
            iterations: 5,
            warmUpIterations: 1
        ) {
            let image = try await loader.load(url: url, options: .preview)
            let context = try scaler.preparePreview(
                image: image,
                analysis: analysis,
                maximumLongEdge: 1_280
            )
            XCTAssertEqual(context.image.pixelSize.longEdge, 1_280)
        }

        session.recordAndAssertContract(
            measurement,
            scenario: scenario,
            contract: 1.5,
            notes: "12 MP JPEG → 2048 decode → 1280 proxy; "
                + "\(measurement.fpsDescription)"
        )
    }

    /// The cold (first) decode is reported separately. It is excluded from the
    /// p95 because CI file caches cannot be controlled, but a device run should
    /// inspect it when signing off first-launch latency.
    func testColdDecodeIsReportedInformational() async throws {
        let scenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "preview.firstFrame")
        )
        let session = try PerformanceSession(source: "FirstFrameColdDecode")
        defer { session.finish(test: self) }

        let temp = try TemporaryDirectory(prefix: "StyleTonePerfCold")
        defer { temp.remove() }
        let url = temp.url.appendingPathComponent("12mp-cold.jpg")
        try PerformanceFixtures.jpegData(size: PixelSize(width: 4_032, height: 3_024))
            .write(to: url)

        let clock = ContinuousClock()
        let start = clock.now
        let image = try await ImageLoader().load(url: url, options: .preview)
        let duration = PerformanceStatistics.seconds(clock.now - start)
        XCTAssertEqual(image.pixelSize.longEdge, 2_048)

        let measurement = try PerformanceMeasurement(
            scenarioID: scenario.id,
            unit: .seconds,
            values: [duration]
        )
        // One sample is below the p95 minimum, so this is informational only.
        session.recordInformational(
            measurement,
            scenario: scenario,
            notes: "first decode after process start; informational only"
        )
    }
}
