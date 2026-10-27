import Foundation
import PerformanceKit
import StyleToneCore
import StyleToneLearning
import XCTest

/// 5-pair learning budget (contracts §10: ≤90 s on iPhone 13).
///
/// The synthetic scene is 160×160, matching the WP-11 performance fixture size,
/// so the CI baseline is comparable with the existing module measurement.
final class LearningPerformanceTests: XCTestCase {
    func testFivePairLearning() async throws {
        let scenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "learning.fivePairs")
        )
        let session = try PerformanceSession(source: "LearningPerformanceTests")
        defer { session.finish() }

        let pairs = try (0 ..< 5).map { _ in
            try PerformanceFixtures.portraitPair()
        }
        let engine = StyleLearningEngine()

        let measurement = try await PerformanceClock.measureAsync(
            scenario: scenario,
            iterations: 3,
            warmUpIterations: 0
        ) {
            let result = try await engine.learn(
                StyleLearningRequest(samples: pairs)
            )
            XCTAssertEqual(result.profile.pairCount, 5)
        }

        session.recordAndAssertContract(
            measurement,
            scenario: scenario,
            contract: 90,
            notes: "5 × 160×160 synthetic portrait pairs"
        )
    }

    func testEightPairLearning() async throws {
        try XCTSkipUnless(
            PerformanceTestProfile.heavy,
            "Set ST_PERF_HEAVY=1 or run on the reference device for the 8-pair budget"
        )
        let scenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "learning.eightPairs")
        )
        let session = try PerformanceSession(source: "LearningPerformanceTests8")
        defer { session.finish() }

        let pairs = try (0 ..< 8).map { _ in
            try PerformanceFixtures.portraitPair(editedExposure: 1.12)
        }
        let engine = StyleLearningEngine()

        let measurement = try await PerformanceClock.measureAsync(
            scenario: scenario,
            iterations: 3,
            warmUpIterations: 0
        ) {
            let result = try await engine.learn(
                StyleLearningRequest(samples: pairs)
            )
            XCTAssertEqual(result.profile.pairCount, 8)
        }

        session.recordAndAssertContract(
            measurement,
            scenario: scenario,
            contract: 150,
            notes: "8 × 160×160 synthetic portrait pairs"
        )
    }
}
