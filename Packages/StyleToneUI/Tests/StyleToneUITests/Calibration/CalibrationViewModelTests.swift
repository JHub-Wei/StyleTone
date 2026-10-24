import XCTest
import StyleToneCore
import TestShared
@testable import StyleToneUI

final class CalibrationViewModelTests: XCTestCase {
    @MainActor
    func testSixAnswersLearnAndSaveAProfile() async throws {
        let learner = RecordingStyleLearner(profile: MockStyleProfileFactory.trial())
        let profileStore = MockStyleProfileStore()
        let progressStore = CalibrationInMemoryProgressStore()
        let model = makeModel(
            samples: try CalibrationTestSupport.pairs(3),
            learner: learner,
            profileStore: profileStore,
            progressStore: progressStore
        )

        XCTAssertTrue(model.beginComparisons(using: .three))
        for _ in 0..<6 {
            model.answerCurrent(choseA: true)
        }
        XCTAssertEqual(model.flow.phase, .comparisons)
        model.finishComparisons()
        await model.waitForLearningToFinish()

        let sampleCounts = await learner.sampleCounts
        let answerCounts = await learner.answerCounts
        let saveCount = await profileStore.saveCount
        let savedProfile = await profileStore.storedProfile

        XCTAssertEqual(model.flow.phase, .result)
        XCTAssertNotNil(model.flow.profile)
        XCTAssertEqual(model.flow.answers.count, 6)
        XCTAssertEqual(sampleCounts, [3])
        XCTAssertEqual(answerCounts, [6])
        XCTAssertEqual(saveCount, 1)
        XCTAssertNotNil(savedProfile)
    }

    @MainActor
    func testEighthAnswerAutomaticallyLearns() async throws {
        let learner = RecordingStyleLearner(profile: MockStyleProfileFactory.stable())
        let model = makeModel(
            samples: try CalibrationTestSupport.pairs(8),
            learner: learner,
            profileStore: MockStyleProfileStore(),
            progressStore: CalibrationInMemoryProgressStore()
        )

        XCTAssertTrue(model.beginComparisons(using: .eight))
        for _ in 0..<8 {
            model.answerCurrent(choseA: false)
        }
        await model.waitForLearningToFinish()

        let sampleCounts = await learner.sampleCounts
        XCTAssertEqual(model.flow.phase, .result)
        XCTAssertEqual(model.flow.answeredComparisonCount, 8)
        XCTAssertEqual(sampleCounts, [8])
    }

    @MainActor
    func testSkipToNaturalDefaultDoesNotCallTheLearner() async throws {
        let learner = RecordingStyleLearner(profile: MockStyleProfileFactory.standard())
        let profileStore = MockStyleProfileStore()
        let model = makeModel(
            samples: try CalibrationTestSupport.pairs(3),
            learner: learner,
            profileStore: profileStore,
            progressStore: CalibrationInMemoryProgressStore()
        )

        XCTAssertTrue(model.beginComparisons(using: .three))
        model.answerCurrent(choseA: true)
        model.skipToNaturalDefault()
        await model.waitForLearningToFinish()

        let sampleCounts = await learner.sampleCounts
        let storedProfile = await profileStore.storedProfile
        let saved = try XCTUnwrap(storedProfile)

        XCTAssertEqual(model.flow.phase, .result)
        XCTAssertTrue(model.flow.isNaturalDefaultResult)
        XCTAssertEqual(model.flow.samples.count, 3)
        XCTAssertEqual(sampleCounts, [])
        XCTAssertTrue(saved.tags.contains(CalibrationFlow.naturalDefaultTag))
        XCTAssertEqual(saved.pairCount, 0)
    }

    @MainActor
    func testLearningFailureKeepsPairsAndAnswersForRetry() async throws {
        let model = makeModel(
            samples: try CalibrationTestSupport.pairs(5),
            learner: MockStyleLearner(error: .invalidState),
            profileStore: MockStyleProfileStore(),
            progressStore: CalibrationInMemoryProgressStore()
        )

        XCTAssertTrue(model.beginComparisons(using: .five))
        for _ in 0..<6 {
            model.answerCurrent(choseA: true)
        }
        model.finishComparisons()
        await model.waitForLearningToFinish()

        XCTAssertEqual(model.flow.phase, .failed)
        XCTAssertEqual(model.flow.failure?.kind, .learning)
        XCTAssertEqual(model.flow.samples.count, 5)
        XCTAssertEqual(model.flow.trainingSamples.count, 5)
        XCTAssertEqual(model.flow.answers.count, 6)

        model.returnToComparisons()
        XCTAssertEqual(model.flow.phase, .comparisons)
        XCTAssertEqual(model.flow.samples.count, 5)
        XCTAssertEqual(model.flow.answers.count, 6)
    }

    @MainActor
    func testProfileSaveFailureRetainsTrainingSet() async throws {
        let model = makeModel(
            samples: try CalibrationTestSupport.pairs(3),
            learner: RecordingStyleLearner(profile: MockStyleProfileFactory.trial()),
            profileStore: MockStyleProfileStore(saveError: .persistenceFailed),
            progressStore: CalibrationInMemoryProgressStore()
        )

        XCTAssertTrue(model.beginComparisons(using: .three))
        for _ in 0..<6 {
            model.answerCurrent(choseA: true)
        }
        model.finishComparisons()
        await model.waitForLearningToFinish()

        XCTAssertEqual(model.flow.phase, .failed)
        XCTAssertEqual(model.flow.failure?.kind, .savingProfile)
        XCTAssertEqual(model.flow.samples.count, 3)
        XCTAssertEqual(model.flow.trainingSamples.count, 3)
        XCTAssertEqual(model.flow.answers.count, 6)
    }

    @MainActor
    func testCancelWorkPreservesABProgress() async throws {
        let model = makeModel(
            samples: try CalibrationTestSupport.pairs(3),
            learner: RecordingStyleLearner(profile: MockStyleProfileFactory.trial()),
            profileStore: MockStyleProfileStore(),
            progressStore: CalibrationInMemoryProgressStore()
        )

        XCTAssertTrue(model.beginComparisons(using: .three))
        for _ in 0..<6 {
            model.answerCurrent(choseA: true)
        }
        model.finishComparisons()
        model.cancelWork()
        await Task.yield()

        XCTAssertEqual(model.flow.phase, .comparisons)
        XCTAssertEqual(model.flow.answers.count, 6)
        XCTAssertEqual(model.flow.samples.count, 3)
        XCTAssertEqual(model.notice, .cancelledLearning)
    }

    @MainActor
    func testPauseAndRestoreKeepsABPosition() async throws {
        let samples = try CalibrationTestSupport.pairs(5)
        let progressStore = CalibrationInMemoryProgressStore()
        let learner = RecordingStyleLearner(profile: MockStyleProfileFactory.standard())

        let first = makeModel(
            samples: samples,
            learner: learner,
            profileStore: MockStyleProfileStore(),
            progressStore: progressStore
        )
        XCTAssertTrue(first.beginComparisons(using: .five))
        first.answerCurrent(choseA: true)
        first.answerCurrent(choseA: false)
        first.skipCurrentComparison()
        await first.pause()

        let second = makeModel(
            samples: samples,
            learner: learner,
            profileStore: MockStyleProfileStore(),
            progressStore: progressStore
        )
        await second.restoreIfNeeded()

        XCTAssertEqual(second.flow.phase, .comparisons)
        XCTAssertEqual(second.flow.selectedPairCount, 5)
        XCTAssertEqual(second.flow.interactionCount, 3)
        XCTAssertEqual(second.flow.answers.count, 2)
        XCTAssertEqual(second.flow.samples.count, 5)
        XCTAssertEqual(second.notice, .restored)
    }

    @MainActor
    func testRestoreWithMissingPairsFallsBackToPairSelection() async throws {
        let samples = try CalibrationTestSupport.pairs(5)
        let progressStore = CalibrationInMemoryProgressStore()
        let learner = RecordingStyleLearner(profile: MockStyleProfileFactory.standard())

        let first = makeModel(
            samples: samples,
            learner: learner,
            profileStore: MockStyleProfileStore(),
            progressStore: progressStore
        )
        XCTAssertTrue(first.beginComparisons(using: .five))
        first.answerCurrent(choseA: true)
        await first.pause()

        let second = makeModel(
            samples: Array(samples.prefix(4)),
            learner: learner,
            profileStore: MockStyleProfileStore(),
            progressStore: progressStore
        )
        await second.restoreIfNeeded()

        XCTAssertEqual(second.flow.phase, .pairs)
        XCTAssertEqual(second.flow.samples.count, 4)
        XCTAssertEqual(second.notice, .missingPairs)
    }

    @MainActor
    func testRestoreWithoutADraftIsANoOp() async throws {
        let model = makeModel(
            samples: try CalibrationTestSupport.pairs(3),
            learner: RecordingStyleLearner(profile: MockStyleProfileFactory.trial()),
            profileStore: MockStyleProfileStore(),
            progressStore: CalibrationInMemoryProgressStore()
        )

        await model.restoreIfNeeded()
        XCTAssertTrue(model.isRestored)
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.flow.phase, .pairs)
        XCTAssertEqual(model.flow.samples.count, 3)
    }

    @MainActor
    func testCalibrationViewConstructsWithStandaloneDependencies() throws {
        let model = makeModel(
            samples: try CalibrationTestSupport.pairs(3),
            learner: CalibrationMockStyleLearning(),
            profileStore: CalibrationPreviewStyleProfileStore(),
            progressStore: CalibrationInMemoryProgressStore()
        )
        _ = CalibrationView(model: model)
    }

    @MainActor
    private func makeModel(
        samples: [PairSample],
        learner: any StyleLearning,
        profileStore: any StyleProfileStore,
        progressStore: any CalibrationProgressStoring
    ) -> CalibrationViewModel {
        CalibrationViewModel(
            samples: samples,
            learner: learner,
            profileStore: profileStore,
            progressStore: progressStore,
            dateProvider: FixedDateProvider()
        )
    }
}
