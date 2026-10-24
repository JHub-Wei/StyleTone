import XCTest
import StyleToneCore
import TestShared
@testable import StyleToneUI

final class CalibrationFlowTests: XCTestCase {
    func testLimitsMatchTheProductBudget() {
        XCTAssertEqual(CalibrationLimits.minimumPairCount, 3)
        XCTAssertEqual(CalibrationLimits.plannedComparisonCount, 8)
        XCTAssertEqual(CalibrationLimits.minimumComparisonCount, 6)
        XCTAssertEqual(CalibrationLimits.pairStageTargetSeconds, 240)
        XCTAssertEqual(CalibrationPairTier.allCases.map(\.pairCount), [3, 5, 8])
    }

    func testTierRecommendationTracksAvailablePairs() throws {
        let four = CalibrationFlow(samples: try CalibrationTestSupport.pairs(4))
        XCTAssertEqual(four.recommendedTier, .three)
        XCTAssertEqual(four.nextTier, .five)
        XCTAssertEqual(four.availableTiers, [.three])

        let five = CalibrationFlow(samples: try CalibrationTestSupport.pairs(5))
        XCTAssertEqual(five.recommendedTier, .five)
        XCTAssertEqual(five.nextTier, .eight)

        let eight = CalibrationFlow(samples: try CalibrationTestSupport.pairs(8))
        XCTAssertEqual(eight.recommendedTier, .eight)
        XCTAssertNil(eight.nextTier)
    }

    func testRejectedPairsAreKeptButExcludedFromLearning() throws {
        var flow = CalibrationFlow(
            samples: try CalibrationTestSupport.pairs(3, rejectedAt: [2])
        )
        XCTAssertEqual(flow.samples.count, 3)
        XCTAssertEqual(flow.eligiblePairCount, 2)
        XCTAssertEqual(flow.rejectedPairCount, 1)
        XCTAssertFalse(flow.canStartComparisons)
        XCTAssertFalse(flow.startComparisons())
        XCTAssertEqual(flow.phase, .pairs)
    }

    func testExplicitThreeFiveEightSelection() throws {
        let samples = try CalibrationTestSupport.pairs(8)

        for tier in CalibrationPairTier.allCases {
            var flow = CalibrationFlow(samples: samples)
            XCTAssertTrue(flow.startComparisons(using: tier))
            XCTAssertEqual(flow.selectedPairCount, tier.pairCount)
            XCTAssertEqual(flow.trainingSamples.count, tier.pairCount)
            XCTAssertEqual(flow.phase, .comparisons)
        }
    }

    func testABAnswerDirectionFollowsTheVisibleOption() throws {
        var flow = CalibrationFlow(samples: try CalibrationTestSupport.pairs(3))
        XCTAssertTrue(flow.startComparisons())

        // Card 0 is not side-swapped: A is the low/negative direction.
        XCTAssertEqual(flow.currentComparison?.index, 0)
        XCTAssertTrue(flow.answerCurrent(choseA: true))
        XCTAssertEqual(flow.answers.last?.strengthDelta ?? 0, -0.35, accuracy: 0.0001)

        // Card 1 is side-swapped: A is the high/positive direction.
        XCTAssertEqual(flow.currentComparison?.index, 1)
        XCTAssertTrue(flow.answerCurrent(choseA: true))
        XCTAssertEqual(flow.answers.last?.strengthDelta ?? 0, 0.35, accuracy: 0.0001)
    }

    func testSixInteractionsCanFinishAndCarrySixAnswers() throws {
        var flow = CalibrationFlow(samples: try CalibrationTestSupport.pairs(3))
        XCTAssertTrue(flow.startComparisons())

        for _ in 0..<6 {
            XCTAssertTrue(flow.answerCurrent(choseA: false))
        }

        XCTAssertEqual(flow.phase, .comparisons)
        XCTAssertTrue(flow.canFinishComparisons)
        XCTAssertTrue(flow.finishComparisons())
        XCTAssertEqual(flow.phase, .learning)

        let request = try XCTUnwrap(flow.learningRequest)
        XCTAssertEqual(request.samples.count, 3)
        XCTAssertEqual(request.answers.count, 6)
    }

    func testEighthCardAutomaticallyAdvancesToLearning() throws {
        var flow = CalibrationFlow(samples: try CalibrationTestSupport.pairs(5))
        XCTAssertTrue(flow.startComparisons(using: .five))

        for _ in 0..<8 {
            XCTAssertTrue(flow.answerCurrent(choseA: true))
        }

        XCTAssertEqual(flow.phase, .learning)
        XCTAssertEqual(flow.answeredComparisonCount, 8)
        XCTAssertEqual(flow.interactionCount, 8)
        XCTAssertTrue(flow.isABComplete)
    }

    func testSkippedCardsKeepSixCardExit() throws {
        var flow = CalibrationFlow(samples: try CalibrationTestSupport.pairs(3))
        XCTAssertTrue(flow.startComparisons())

        for _ in 0..<6 {
            XCTAssertTrue(flow.skipCurrentComparison())
        }

        XCTAssertEqual(flow.interactionCount, 6)
        XCTAssertEqual(flow.answeredComparisonCount, 0)
        XCTAssertEqual(flow.skippedComparisonCount, 6)
        XCTAssertTrue(flow.canFinishComparisons)
        XCTAssertTrue(flow.finishComparisons())
        XCTAssertEqual(flow.learningRequest?.answers.count, 0)
    }

    func testLearningFailureKeepsPairsAnswersAndTier() throws {
        var flow = CalibrationFlow(samples: try CalibrationTestSupport.pairs(5))
        XCTAssertTrue(flow.startComparisons(using: .five))
        for _ in 0..<6 {
            XCTAssertTrue(flow.answerCurrent(choseA: true))
        }
        XCTAssertTrue(flow.finishComparisons())
        XCTAssertTrue(flow.failLearning(CalibrationFailure(kind: .learning)))

        XCTAssertEqual(flow.phase, .failed)
        XCTAssertEqual(flow.samples.count, 5)
        XCTAssertEqual(flow.trainingSamples.count, 5)
        XCTAssertEqual(flow.selectedPairCount, 5)
        XCTAssertEqual(flow.answers.count, 6)

        XCTAssertTrue(flow.cancelLearning())
        XCTAssertEqual(flow.phase, .comparisons)
        XCTAssertEqual(flow.answers.count, 6)
        XCTAssertEqual(flow.samples.count, 5)
    }

    func testNaturalDefaultSkipsLearningAndRecalibrationKeepsPairs() throws {
        var flow = CalibrationFlow(samples: try CalibrationTestSupport.pairs(3))
        XCTAssertTrue(flow.startComparisons())
        XCTAssertTrue(flow.beginNaturalDefault())
        XCTAssertEqual(flow.phase, .learning)

        let profile = CalibrationFlow.naturalDefaultProfile(now: FixedDateProvider.reference)
        XCTAssertTrue(flow.completeLearning(profile))
        XCTAssertEqual(flow.phase, .result)
        XCTAssertTrue(flow.isNaturalDefaultResult)
        XCTAssertEqual(flow.profile?.pairCount, 0)

        XCTAssertTrue(flow.recalibrate())
        XCTAssertEqual(flow.phase, .pairs)
        XCTAssertEqual(flow.samples.count, 3)
        XCTAssertNil(flow.profile)
        XCTAssertEqual(flow.answers.count, 0)
    }

    func testDraftRoundTripRestoresABProgress() throws {
        let samples = try CalibrationTestSupport.pairs(5)
        var original = CalibrationFlow(samples: samples)
        XCTAssertTrue(original.startComparisons(using: .five))
        XCTAssertTrue(original.answerCurrent(choseA: true))
        XCTAssertTrue(original.answerCurrent(choseA: false))
        XCTAssertTrue(original.skipCurrentComparison())

        let draft = original.makeDraft()
        var restored = CalibrationFlow(samples: samples)
        XCTAssertEqual(restored.restore(from: draft), .restored)
        XCTAssertEqual(restored.phase, .comparisons)
        XCTAssertEqual(restored.selectedPairCount, 5)
        XCTAssertEqual(restored.interactionCount, 3)
        XCTAssertEqual(restored.answers.count, 2)
        XCTAssertEqual(restored.skippedComparisonCount, 1)
        XCTAssertEqual(restored.currentComparison?.index, 3)
    }

    func testDraftWithMissingPairDoesNotDropAvailableSamples() throws {
        let samples = try CalibrationTestSupport.pairs(5)
        var original = CalibrationFlow(samples: samples)
        XCTAssertTrue(original.startComparisons(using: .five))
        XCTAssertTrue(original.answerCurrent(choseA: true))
        let draft = original.makeDraft()

        var restored = CalibrationFlow(samples: Array(samples.prefix(4)))
        let outcome = restored.restore(from: draft)
        XCTAssertEqual(outcome, .missingPairs(required: 5, available: 4))
        XCTAssertEqual(restored.phase, .pairs)
        XCTAssertEqual(restored.samples.count, 4)
        XCTAssertEqual(restored.answers.count, 0)
    }

    func testCompletedResultRestoresWithoutPairImages() throws {
        let profile = MockStyleProfileFactory.standard()
        let draft = CalibrationDraft(
            phase: .result,
            selectedPairCount: 5,
            profile: profile
        )

        var flow = CalibrationFlow(samples: [])
        XCTAssertEqual(flow.restore(from: draft), .restored)
        XCTAssertEqual(flow.phase, .result)
        XCTAssertEqual(flow.profile, profile)
    }

    func testAddSamplesDeduplicatesAndOnlyWorksWhileChoosingPairs() throws {
        let samples = try CalibrationTestSupport.pairs(3)
        var flow = CalibrationFlow(samples: Array(samples.prefix(2)))
        XCTAssertEqual(flow.addSamples([samples[1], samples[2]]), 1)
        XCTAssertEqual(flow.samples.count, 3)
        XCTAssertEqual(flow.eligiblePairCount, 3)

        XCTAssertTrue(flow.startComparisons())
        XCTAssertEqual(flow.addSamples([samples[0]]), 0)
        XCTAssertEqual(flow.samples.count, 3)
    }

    func testDraftPhaseAfterLearningRestoresToComparisonsForRetry() throws {
        let samples = try CalibrationTestSupport.pairs(3)
        let draft = CalibrationDraft(
            phase: .learning,
            selectedPairCount: 3,
            trainingPairIDs: samples.map(\.id),
            answers: [CalibrationAnswer(dimension: .tone, choseA: true, strengthDelta: -0.35)],
            comparisonIndex: 1,
            updatedAt: FixedDateProvider.reference
        )

        var flow = CalibrationFlow(samples: samples)
        XCTAssertEqual(flow.restore(from: draft), .restored)
        XCTAssertEqual(flow.phase, .comparisons)
        XCTAssertEqual(flow.interactionCount, 1)
        XCTAssertEqual(flow.answers.count, 1)
    }
}
