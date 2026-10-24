import Foundation
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
        let weak = PairStrengthSignals(faceSlim: 0.10, jaw: 0.05)
        let strong = PairStrengthSignals(faceSlim: 0.30, jaw: 0.15)
        var signals: [UUID: PairStrengthSignals] = [:]
        for (index, pair) in pairs.enumerated() {
            signals[pair.id] = index < 4 ? weak : strong
        }
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs, strengthSignals: signals)
        )

        // Mean before shrink is 0.20 slim / 0.10 jaw. The engine also applies
        // hold-out shrink, so assert the averaged range instead of an exact
        // value; summing would saturate at the 0.35 safety cap.
        XCTAssertGreaterThan(result.profile.face.slim, 0.12)
        XCTAssertLessThan(result.profile.face.slim, 0.26)
        XCTAssertGreaterThan(result.profile.face.jaw, 0.05)
        XCTAssertLessThan(result.profile.face.jaw, 0.15)
    }

    func testPairAggregatorAveragesSymmetricPairs() {
        var fits: [PairFit] = []
        for index in 0..<8 {
            let value = index < 4 ? 0.10 : 0.30
            fits.append(
                PairFit(
                    id: UUID(),
                    tone: .neutral,
                    skin: .neutral,
                    face: FaceParameters(slim: value, jaw: value / 2),
                    body: .neutral,
                    finish: .neutral,
                    toneWeight: 1,
                    strengthWeight: 1,
                    skinFraction: 0.2,
                    skinProtectionApplied: false,
                    issues: []
                )
            )
        }

        let aggregate = PairAggregator.aggregate(
            fits,
            safety: .standard
        )

        XCTAssertEqual(aggregate.face.slim, 0.20, accuracy: 0.01)
        XCTAssertEqual(aggregate.face.jaw, 0.10, accuracy: 0.01)
        XCTAssertEqual(aggregate.outlierCount, 0)
    }
}
