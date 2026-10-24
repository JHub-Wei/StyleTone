import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneLearning

final class StrengthFittingTests: XCTestCase {
    private func makeEngine() -> StyleLearningEngine {
        StyleLearningEngine(dateProvider: FixedDateProvider())
    }

    func testTextureLossRaisesSmoothingEstimate() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit(blurRadius: 3)
        )
        let engine = makeEngine()
        let result = try await engine.learn(StyleLearningRequest(samples: pairs))

        XCTAssertGreaterThan(result.profile.skin.smoothing, 0.05)
        XCTAssertLessThanOrEqual(
            result.profile.skin.smoothing,
            engine.configuration.safety.smoothing
        )
    }

    func testSignalsAreAveragedAndClampedToSafetyRanges() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 8,
            edit: SyntheticEdit()
        )
        let signals = PairStrengthSignals(
            smoothing: 2,
            evenness: 2,
            blemish: 2,
            faceSlim: 2,
            jaw: 2,
            arm: 2,
            waist: 2,
            leg: 2,
            legLength: 1.30,
            grain: 2,
            vignette: -3
        )
        let request = StyleLearningRequest(
            samples: pairs,
            strengthSignals: Dictionary(
                uniqueKeysWithValues: pairs.map { ($0.id, signals) }
            )
        )
        let engine = makeEngine()
        let result = try await engine.learn(request)
        let safety = engine.configuration.safety

        XCTAssertEqual(result.profile.skin.smoothing, safety.smoothing, accuracy: 1e-9)
        XCTAssertEqual(result.profile.face.slim, safety.faceSlim, accuracy: 1e-9)
        XCTAssertEqual(result.profile.body.arm, safety.arm, accuracy: 1e-9)
        XCTAssertEqual(result.profile.body.legLength, safety.legLengthMax, accuracy: 1e-9)
        XCTAssertEqual(result.profile.finish.grain, safety.grain, accuracy: 1e-9)
        XCTAssertEqual(result.profile.finish.vignette, safety.vignetteMin, accuracy: 1e-9)
        XCTAssertTrue(safety.contains(result.profile))
    }

    func testNoSignalsMeansNoAutomaticGeometry() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit()
        )
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )

        XCTAssertEqual(result.profile.face.slim, 0, accuracy: 1e-9)
        XCTAssertEqual(result.profile.face.jaw, 0, accuracy: 1e-9)
        XCTAssertEqual(result.profile.body.arm, 0, accuracy: 1e-9)
        XCTAssertEqual(result.profile.body.waist, 0, accuracy: 1e-9)
        XCTAssertEqual(result.profile.body.leg, 0, accuracy: 1e-9)
        XCTAssertEqual(result.profile.body.legLength, 1, accuracy: 1e-9)
    }

    func testStrengthSignalsAreAveragedRatherThanSummed() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 8,
            edit: SyntheticEdit()
        )
        let weak = PairStrengthSignals(faceSlim: 0.20, jaw: 0.10)
        let strong = PairStrengthSignals(faceSlim: 0.60, jaw: 0.30)
        var signals: [UUID: PairStrengthSignals] = [:]
        for (index, pair) in pairs.enumerated() {
            signals[pair.id] = index < 4 ? weak : strong
        }
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs, strengthSignals: signals)
        )

        // Mean face slim is 0.40 before safety and shrink; eight pairs keep
        // almost all of it.
        XCTAssertEqual(result.profile.face.slim, 0.40, accuracy: 0.05)
        XCTAssertEqual(result.profile.face.jaw, 0.20, accuracy: 0.03)
    }
}
