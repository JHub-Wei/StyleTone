import XCTest
import StyleToneCore
import TestShared
@testable import StyleToneUI

final class CalibrationMockStyleLearningTests: XCTestCase {
    private let learner = CalibrationMockStyleLearning(now: FixedDateProvider.reference)

    func testConfidenceScalesWithPairCount() async throws {
        for pairCount in [3, 5, 8] {
            let profile = try await learner.learn(
                samples: try CalibrationTestSupport.pairs(pairCount),
                answers: []
            )
            XCTAssertEqual(profile.pairCount, pairCount)
            XCTAssertEqual(profile.updatedAt, FixedDateProvider.reference)
            XCTAssertEqual(profile.algorithmVersion, "st-3.0.0-mock")

            let expected: ConfidenceLevel
            if pairCount == 3 {
                expected = .trial
            } else if pairCount == 5 {
                expected = .standard
            } else {
                expected = .stable
            }
            XCTAssertEqual(profile.confidence, expected)
        }
    }

    func testMorePairsProduceLessShrink() async throws {
        let three = try await learner.learn(
            samples: try CalibrationTestSupport.pairs(3),
            answers: [CalibrationAnswer(dimension: .smoothing, choseA: false, strengthDelta: 0.35)]
        )
        let eight = try await learner.learn(
            samples: try CalibrationTestSupport.pairs(8),
            answers: [CalibrationAnswer(dimension: .smoothing, choseA: false, strengthDelta: 0.35)]
        )

        XCTAssertGreaterThan(eight.skin.smoothing, three.skin.smoothing)
        XCTAssertGreaterThanOrEqual(eight.skin.smoothing, 0)
        XCTAssertLessThanOrEqual(eight.skin.smoothing, 1)
    }

    func testABDirectionMovesTheRelevantParameters() async throws {
        let low = try await learner.learn(
            samples: try CalibrationTestSupport.pairs(8),
            answers: [CalibrationAnswer(dimension: .tone, choseA: true, strengthDelta: -0.35)]
        )
        let high = try await learner.learn(
            samples: try CalibrationTestSupport.pairs(8),
            answers: [CalibrationAnswer(dimension: .tone, choseA: false, strengthDelta: 0.35)]
        )

        XCTAssertLessThan(low.tone.contrast, high.tone.contrast)
        XCTAssertLessThan(low.tone.saturation, high.tone.saturation)
    }

    func testNaturalnessChoiceAddsTagAndStaysInRange() async throws {
        let profile = try await learner.learn(
            samples: try CalibrationTestSupport.pairs(8),
            answers: [CalibrationAnswer(dimension: .naturalness, choseA: false, strengthDelta: 0.35)]
        )

        XCTAssertTrue(profile.tags.contains("style.tag.editorial"))
        XCTAssertGreaterThanOrEqual(profile.skin.smoothing, 0)
        XCTAssertLessThanOrEqual(profile.skin.smoothing, 1)
        XCTAssertGreaterThanOrEqual(profile.body.legLength, 1)
        XCTAssertLessThanOrEqual(profile.body.legLength, 1.15)
    }

    func testEmptySamplesThrowWithoutCrashing() async {
        do {
            _ = try await learner.learn(samples: [], answers: [])
            XCTFail("Expected invalidState")
        } catch let error as StyleToneError {
            XCTAssertEqual(error, .invalidState)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
