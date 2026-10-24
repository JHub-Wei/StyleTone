import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneLearning

final class ToneFittingTests: XCTestCase {
    private func makeEngine(
        _ configuration: StyleLearningConfiguration = .standard
    ) -> StyleLearningEngine {
        StyleLearningEngine(
            configuration: configuration,
            dateProvider: FixedDateProvider()
        )
    }

    func testWarmExposureEditIsRecovered() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit(
                exposure: 1.15,
                redGain: 1.06,
                blueGain: 0.95
            )
        )
        let engine = makeEngine()
        let result = try await engine.learn(StyleLearningRequest(samples: pairs))

        XCTAssertEqual(result.profile.pairCount, 5)
        XCTAssertEqual(result.profile.schemaVersion, 3)
        XCTAssertEqual(
            result.profile.algorithmVersion,
            StyleProfile.currentAlgorithmVersion
        )
        XCTAssertGreaterThan(result.profile.tone.exposure, 0.02)
        XCTAssertGreaterThan(result.profile.tone.temperature, 0.02)
        XCTAssertTrue(engine.configuration.safety.contains(result.profile))
    }

    func testCoolDesaturatedEditIsRecovered() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit(
                exposure: 0.92,
                redGain: 0.95,
                blueGain: 1.08,
                saturation: 0.72
            )
        )
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )

        XCTAssertLessThan(result.profile.tone.temperature, -0.02)
        XCTAssertLessThan(result.profile.tone.saturation, -0.05)
    }

    func testContrastEditIsRecovered() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit(contrast: 1.18)
        )
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )

        XCTAssertGreaterThan(result.profile.tone.contrast, 0.02)
    }

    func testSaturationBoostIsRecovered() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit(saturation: 1.25)
        )
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )

        XCTAssertGreaterThan(result.profile.tone.saturation, 0.03)
    }

    func testIdenticalPairsStayNearNeutral() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit()
        )
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )

        XCTAssertEqual(result.profile.tone.exposure, 0, accuracy: 0.03)
        XCTAssertEqual(result.profile.tone.contrast, 0, accuracy: 0.03)
        XCTAssertEqual(result.profile.tone.temperature, 0, accuracy: 0.03)
        XCTAssertEqual(result.profile.tone.tint, 0, accuracy: 0.03)
        XCTAssertEqual(result.profile.tone.saturation, 0, accuracy: 0.05)
    }

    func testSkinProtectionReducesOverSaturatedSkinEdit() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit(saturation: 1.45)
        )
        var unguardedConfiguration = StyleLearningConfiguration.standard
        unguardedConfiguration.skinProtection.isEnabled = false

        let guarded = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )
        let unguarded = try await makeEngine(unguardedConfiguration).learn(
            StyleLearningRequest(samples: pairs)
        )

        XCTAssertTrue(
            guarded.diagnostics.skinProtectionApplied,
            "skin chroma guard did not trigger"
        )
        XCTAssertLessThanOrEqual(
            guarded.profile.tone.saturation,
            unguarded.profile.tone.saturation + 1e-9
        )
    }

    func testExtremeEditsStayInsideSafetyEnvelope() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 8,
            edit: SyntheticEdit(
                exposure: 2.2,
                redGain: 1.5,
                blueGain: 0.6,
                contrast: 1.8,
                saturation: 1.6,
                blurRadius: 2
            )
        )
        let engine = makeEngine()
        let result = try await engine.learn(StyleLearningRequest(samples: pairs))
        let profile = result.profile
        let safety = engine.configuration.safety

        XCTAssertTrue(safety.contains(profile))
        XCTAssertLessThanOrEqual(abs(profile.tone.exposure), safety.exposure)
        XCTAssertLessThanOrEqual(abs(profile.tone.temperature), safety.temperature)
        XCTAssertLessThanOrEqual(abs(profile.tone.saturation), safety.saturation)
        XCTAssertLessThanOrEqual(profile.skin.smoothing, safety.smoothing)
        XCTAssertLessThanOrEqual(profile.face.slim, safety.faceSlim)
        XCTAssertLessThanOrEqual(profile.body.legLength, safety.legLengthMax)
    }
}
