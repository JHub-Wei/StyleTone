import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneLearning

final class ABPreferenceTests: XCTestCase {
    private func makeEngine() -> StyleLearningEngine {
        StyleLearningEngine(dateProvider: FixedDateProvider())
    }

    private func answer(
        _ dimension: CalibrationDimension,
        _ delta: Double
    ) -> CalibrationAnswer {
        CalibrationAnswer(dimension: dimension, choseA: delta >= 0, strengthDelta: delta)
    }

    func testPositivePreferencesRaiseMatchingStrengths() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit(exposure: 1.05)
        )
        let answers = [
            answer(.smoothing, 1),
            answer(.faceSlim, 1),
            answer(.bodySlim, 1),
            answer(.legLength, 1),
            answer(.tone, 1),
            answer(.skinTone, 1)
        ]
        let engine = makeEngine()
        let baseline = try await engine.learn(
            StyleLearningRequest(samples: pairs)
        )
        let tuned = try await engine.learn(
            StyleLearningRequest(samples: pairs, answers: answers)
        )

        XCTAssertGreaterThan(
            tuned.profile.skin.smoothing,
            baseline.profile.skin.smoothing + 0.005
        )
        XCTAssertGreaterThan(
            tuned.profile.face.slim,
            baseline.profile.face.slim + 0.005
        )
        XCTAssertGreaterThan(
            tuned.profile.body.waist,
            baseline.profile.body.waist + 0.005
        )
        XCTAssertGreaterThan(
            tuned.profile.body.legLength,
            baseline.profile.body.legLength + 0.002
        )
        XCTAssertGreaterThan(
            tuned.profile.tone.temperature,
            baseline.profile.tone.temperature + 0.005
        )
        XCTAssertGreaterThan(
            tuned.profile.tone.exposure,
            baseline.profile.tone.exposure + 0.002
        )
    }

    func testNegativeNaturalnessLowersStrengths() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit()
        )
        let signals = PairStrengthSignals(
            smoothing: 0.5,
            evenness: 0.4,
            faceSlim: 0.5,
            jaw: 0.3,
            waist: 0.4,
            arm: 0.3
        )
        let signalsByPair = Dictionary(
            uniqueKeysWithValues: pairs.map { ($0.id, signals) }
        )
        let engine = makeEngine()
        let baseline = try await engine.learn(
            StyleLearningRequest(samples: pairs, strengthSignals: signalsByPair)
        )
        let answers = Array(
            repeating: answer(.naturalness, -1),
            count: 6
        )
        let quieter = try await engine.learn(
            StyleLearningRequest(
                samples: pairs,
                answers: answers,
                strengthSignals: signalsByPair
            )
        )

        XCTAssertLessThan(
            quieter.profile.skin.smoothing,
            baseline.profile.skin.smoothing - 0.005
        )
        XCTAssertLessThan(
            quieter.profile.face.slim,
            baseline.profile.face.slim - 0.005
        )
        XCTAssertLessThan(
            quieter.profile.body.waist,
            baseline.profile.body.waist - 0.005
        )
        XCTAssertLessThan(
            quieter.profile.tone.saturation,
            baseline.profile.tone.saturation - 0.005
        )
    }

    func testABOnlyProducesTrialProfileWithinSafety() async throws {
        let answers = CalibrationDimension.allCases.map { answer($0, 1) }
        let engine = makeEngine()
        let result = try await engine.learn(
            StyleLearningRequest(samples: [], answers: answers)
        )

        XCTAssertEqual(result.profile.pairCount, 0)
        XCTAssertEqual(result.profile.confidence, .trial)
        XCTAssertTrue(result.profile.tags.contains("style.tag.natural"))
        XCTAssertTrue(result.diagnostics.issues.contains(.abOnly))
        XCTAssertGreaterThan(result.profile.face.slim, 0)
        XCTAssertGreaterThan(result.profile.skin.smoothing, 0)
        XCTAssertGreaterThan(result.profile.tone.temperature, 0)
        XCTAssertTrue(engine.configuration.safety.contains(result.profile))
    }

    func testABInfluenceIsBounded() async throws {
        let answers = Array(
            repeating: answer(.faceSlim, 1),
            count: 8
        )
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: [], answers: answers)
        )

        XCTAssertGreaterThan(result.profile.face.slim, 0.03)
        XCTAssertLessThan(result.profile.face.slim, 0.08)
        XCTAssertLessThan(
            result.profile.face.slim,
            StyleSafetyRanges.standard.faceSlim
        )
    }

    func testABAnswersAreOptionalAndDeterministic() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit(exposure: 1.08)
        )
        let answers = [
            answer(.smoothing, 0.4),
            answer(.faceSlim, -0.3),
            answer(.bodySlim, 0.2),
            answer(.legLength, 0.6),
            answer(.tone, 0.1),
            answer(.skinTone, -0.5)
        ]
        let engine = makeEngine()
        let first = try await engine.learn(
            StyleLearningRequest(samples: pairs, answers: answers)
        )
        let second = try await engine.learn(
            StyleLearningRequest(samples: pairs, answers: answers)
        )

        XCTAssertEqual(first.profile, second.profile)
        XCTAssertEqual(first.diagnostics, second.diagnostics)
    }
}
