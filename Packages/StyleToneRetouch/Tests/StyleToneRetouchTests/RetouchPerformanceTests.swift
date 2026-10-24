import Foundation
import GoldenSupport
import StyleToneCore
import XCTest
@testable import StyleToneRetouch

final class RetouchPerformanceTests: XCTestCase {
    func testPreviewSizedRetouchIsInteractive() async throws {
        let size = PixelSize(width: 512, height: 512)
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[2].color
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size)
        )
        let parameters = SkinParameters(smoothing: 0.7, evenness: 0.4)
        let retoucher = SkinRetoucher()

        let measurement = try await PerformanceHarness.measureAsync(
            name: "retouch.512",
            iterations: 2,
            warmupIterations: 1
        ) {
            _ = try await retoucher.retouch(
                input,
                analysis: analysis,
                parameters: parameters
            )
        }
        XCTAssertLessThan(measurement.p95Seconds, 3.0, measurement.summary)
    }

    /// 12 MP acceptance test, opt-in because debug XCTest builds are not a
    /// valid target-device measurement. Run with:
    ///
    /// `ST_RUN_RETOUCH_12MP_PERF=1 swift test --filter RetouchPerformanceTests`
    ///
    /// on macOS or a device in Release configuration.
    func test12MPRetouchEnvelope() async throws {
        guard ProcessInfo.processInfo.environment["ST_RUN_RETOUCH_12MP_PERF"] == "1" else {
            throw XCTSkip(
                "Set ST_RUN_RETOUCH_12MP_PERF=1 for the 12 MP measurement"
            )
        }
        let size = PixelSize(width: 4032, height: 3024)
        let input = try MockImageAssetFactory.solid(
            color: RGB8(red: 224, green: 172, blue: 130),
            size: size
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size)
        )
        let parameters = SkinParameters(smoothing: 0.8, evenness: 0.5)
        let retoucher = SkinRetoucher()

        let measurement = try await PerformanceHarness.measureAsync(
            name: "retouch.12MP",
            iterations: 1,
            warmupIterations: 0
        ) {
            _ = try await retoucher.retouch(
                input,
                analysis: analysis,
                parameters: parameters
            )
        }
        let budget = PerformanceBudget(
            id: "retouch.12MP",
            targetSeconds: 2.0,
            allowanceFraction: 0
        )
        let verdict = budget.verdict(for: measurement)
        XCTAssertTrue(verdict.passed, verdict.message)
    }

    func test12MPBlemishRemovalIsLocalAndBounded() async throws {
        guard ProcessInfo.processInfo.environment["ST_RUN_RETOUCH_12MP_PERF"] == "1" else {
            throw XCTSkip(
                "Set ST_RUN_RETOUCH_12MP_PERF=1 for the 12 MP measurement"
            )
        }
        let size = PixelSize(width: 4032, height: 3024)
        let input = try MockImageAssetFactory.solid(
            color: RGB8(red: 224, green: 172, blue: 130),
            size: size
        )
        let point = BlemishPoint(
            point: NormalizedPoint(x: 0.5, y: 0.5),
            radius: 0.02
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size)
        )
        let retoucher = SkinRetoucher()
        let measurement = try await PerformanceHarness.measureAsync(
            name: "blemish.12MP",
            iterations: 1,
            warmupIterations: 0
        ) {
            _ = try await retoucher.removeBlemish(
                input,
                at: point,
                analysis: analysis
            )
        }
        XCTAssertLessThan(measurement.p95Seconds, 2.0, measurement.summary)
    }
}
