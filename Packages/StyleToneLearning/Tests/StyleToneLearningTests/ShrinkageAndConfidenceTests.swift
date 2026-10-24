import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneLearning

final class ShrinkageAndConfidenceTests: XCTestCase {
    private func makeEngine() -> StyleLearningEngine {
        StyleLearningEngine(dateProvider: FixedDateProvider())
    }

    private var strongEdit: SyntheticEdit {
        SyntheticEdit(
            exposure: 1.20,
            redGain: 1.06,
            blueGain: 0.94,
            contrast: 1.12,
            saturation: 1.20,
            blurRadius: 2
        )
    }

    func testThreePairsShrinkHardAndEightPairsStayStable() async throws {
        let three = try await makeEngine().learn(
            StyleLearningRequest(
                samples: try SyntheticPairFactory.pairs(count: 3, edit: strongEdit)
            )
        )
        let eight = try await makeEngine().learn(
            StyleLearningRequest(
                samples: try SyntheticPairFactory.pairs(count: 8, edit: strongEdit)
            )
        )

        XCTAssertEqual(three.profile.pairCount, 3)
        XCTAssertEqual(eight.profile.pairCount, 8)
        XCTAssertEqual(three.profile.confidence, .trial)
        XCTAssertEqual(eight.profile.confidence, .stable)
        XCTAssertLessThan(three.diagnostics.shrinkage, 0.45)
        XCTAssertGreaterThan(eight.diagnostics.shrinkage, 0.85)
        XCTAssertLessThan(
            abs(three.profile.tone.exposure),
            abs(eight.profile.tone.exposure)
        )
        XCTAssertLessThan(
            three.profile.skin.smoothing,
            eight.profile.skin.smoothing
        )
    }

    func testFivePairsAreStandardConfidenceAndWithinTimeBudget() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: strongEdit
        )
        let start = Date()
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )
        let duration = Date().timeIntervalSince(start)

        XCTAssertEqual(result.profile.confidence, .standard)
        XCTAssertGreaterThan(result.diagnostics.shrinkage, 0.5)
        XCTAssertLessThan(result.diagnostics.shrinkage, 0.85)
        XCTAssertLessThan(
            duration,
            90,
            "five-pair learning took \(duration) s"
        )

        let attachment = XCTAttachment(
            string: String(format: "5-pair learning duration: %.3f s", duration)
        )
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDisagreementRaisesHoldoutErrorAndDowngradesConfidence() async throws {
        var pairs = try SyntheticPairFactory.pairs(
            count: 4,
            edit: SyntheticEdit(exposure: 1.15, redGain: 1.05)
        )
        pairs += try SyntheticPairFactory.pairs(
            count: 4,
            edit: SyntheticEdit(
                exposure: 0.72,
                redGain: 0.90,
                blueGain: 1.20,
                saturation: 0.60
            )
        )
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )

        XCTAssertNotEqual(result.profile.confidence, .stable)
        XCTAssertGreaterThan(
            result.diagnostics.holdoutError,
            StyleLearningConfiguration.standard.standardHoldoutError
        )
        XCTAssertTrue(result.diagnostics.issues.contains(.highHoldoutError))
    }

    func testSingleOutlierIsDownWeighted() async throws {
        let consistentEdit = SyntheticEdit(exposure: 1.10, redGain: 1.04)
        let outlierEdit = SyntheticEdit(
            exposure: 0.70,
            redGain: 0.90,
            blueGain: 0.55,
            saturation: 0.55
        )
        let baselinePairs = try SyntheticPairFactory.pairs(
            count: 6,
            edit: consistentEdit
        )
        var mixedPairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: consistentEdit
        )
        mixedPairs.append(
            try SyntheticPairFactory.pair(edit: outlierEdit)
        )

        let engine = makeEngine()
        let baseline = try await engine.learn(
            StyleLearningRequest(samples: baselinePairs)
        )
        let mixed = try await engine.learn(
            StyleLearningRequest(samples: mixedPairs)
        )

        XCTAssertTrue(mixed.diagnostics.issues.contains(.outlierPair))
        XCTAssertEqual(
            mixed.profile.tone.exposure,
            baseline.profile.tone.exposure,
            accuracy: 0.08
        )
        XCTAssertEqual(
            mixed.profile.tone.temperature,
            baseline.profile.tone.temperature,
            accuracy: 0.08
        )
        XCTAssertEqual(
            mixed.profile.tone.saturation,
            baseline.profile.tone.saturation,
            accuracy: 0.10
        )
    }
}
