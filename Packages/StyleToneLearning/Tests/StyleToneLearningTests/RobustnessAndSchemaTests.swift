import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneLearning

final class RobustnessAndSchemaTests: XCTestCase {
    private func makeEngine() -> StyleLearningEngine {
        StyleLearningEngine(dateProvider: FixedDateProvider())
    }

    func testEmptyRequestReturnsNaturalTrialProfile() async throws {
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: [], answers: [])
        )

        XCTAssertEqual(result.profile.pairCount, 0)
        XCTAssertEqual(result.profile.confidence, .trial)
        XCTAssertEqual(result.profile.schemaVersion, 3)
        XCTAssertEqual(result.profile.algorithmVersion, "st-3.0.0")
        XCTAssertTrue(result.profile.isNeutral)
        XCTAssertTrue(result.profile.tags.contains("style.tag.natural"))
        XCTAssertEqual(result.diagnostics.acceptedPairCount, 0)
        XCTAssertEqual(result.diagnostics.rejectedPairCount, 0)
    }

    func testAllRejectedPairsReturnNaturalProfile() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 3,
            edit: SyntheticEdit(exposure: 1.2),
            quality: SyntheticPairFactory.quality(.rejected)
        )
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )

        XCTAssertEqual(result.diagnostics.acceptedPairCount, 0)
        XCTAssertEqual(result.diagnostics.rejectedPairCount, 3)
        XCTAssertTrue(result.diagnostics.issues.contains(.rejectedPair))
        XCTAssertTrue(result.profile.isNeutral)
        XCTAssertEqual(result.profile.confidence, .trial)
    }

    func testTinyAndMismatchedImagesDoNotCrash() async throws {
        let tiny = try SyntheticPairFactory.solidPair(
            originalSize: PixelSize(width: 16, height: 16),
            editedSize: PixelSize(width: 16, height: 16)
        )
        let mismatched = try SyntheticPairFactory.solidPair(
            originalSize: PixelSize(width: 96, height: 96),
            editedSize: PixelSize(width: 96, height: 48)
        )
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: [tiny, mismatched])
        )

        XCTAssertLessThanOrEqual(result.profile.pairCount, 2)
        XCTAssertTrue(
            StyleSafetyRanges.standard.contains(result.profile)
        )
        XCTAssertTrue(result.diagnostics.issues.contains(.mismatchedPair))
    }

    func testNonFiniteQualityAndAnswersDoNotCrash() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 3,
            edit: SyntheticEdit(exposure: 1.1)
        )
        let answers = [
            CalibrationAnswer(
                dimension: .tone,
                choseA: true,
                strengthDelta: .nan
            )
        ]
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs, answers: answers)
        )

        XCTAssertTrue(
            StyleSafetyRanges.standard.contains(result.profile)
        )
        XCTAssertEqual(result.diagnostics.answeredCount, 0)
    }

    func testCancellationPropagatesWithoutPartialProfile() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 48,
            edit: SyntheticEdit(exposure: 1.1)
        )
        let engine = makeEngine()
        let task = Task {
            try await engine.learn(samples: pairs, answers: [])
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("cancelled learning returned a profile")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func testProtocolEntryPointMatchesDetailedResult() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit(exposure: 1.06)
        )
        let engine = makeEngine()
        let viaProtocol = try await engine.learn(samples: pairs, answers: [])
        let detailed = try await engine.learn(
            StyleLearningRequest(samples: pairs)
        )

        XCTAssertEqual(viaProtocol, detailed.profile)
    }

    func testProfileJSONRoundTripsWithSchemaThree() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 5,
            edit: SyntheticEdit(
                exposure: 1.08,
                redGain: 1.03,
                saturation: 1.08
            )
        )
        let result = try await makeEngine().learn(
            StyleLearningRequest(samples: pairs)
        )
        let data = try StyleProfileCoding.makeEncoder().encode(result.profile)
        let decoded = try StyleProfileCoding.makeDecoder().decode(
            StyleProfile.self,
            from: data
        )

        XCTAssertEqual(result.profile, decoded)
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertEqual(decoded.algorithmVersion, "st-3.0.0")
        XCTAssertFalse(decoded.tags.isEmpty)
        XCTAssertTrue(decoded.tags.allSatisfy { $0.hasPrefix("style.tag.") })
    }

    func testNoHighStrengthGeometryIsAppliedWithoutEvidence() async throws {
        let pairs = try SyntheticPairFactory.pairs(
            count: 8,
            edit: SyntheticEdit(exposure: 1.25, blurRadius: 2)
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
}
