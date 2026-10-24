import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

/// End-to-end view-model tests: picker → import → quality → persistence.
@MainActor
final class PairingViewModelTests: XCTestCase {
    private let date = PairingTestFactory.referenceDate

    // MARK: - Start and empty state

    func testStartWithoutStoredSessionShowsEmptyState() async {
        let viewModel = await PairingTestFactory.startedViewModel()

        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertTrue(viewModel.showsEmptyState)
        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertNil(viewModel.notice)
        XCTAssertEqual(viewModel.progress.label, "0/3")
        XCTAssertFalse(viewModel.canContinue)
        XCTAssertTrue(viewModel.canAddPair)
        XCTAssertTrue(viewModel.isPickerAvailable)
    }

    // MARK: - Picker flow

    func testAddPairAsksForOriginalThenEdited() async throws {
        let viewModel = await PairingTestFactory.startedViewModel()
        viewModel.addPair()

        XCTAssertEqual(viewModel.rows.count, 1)
        let request = try XCTUnwrap(viewModel.pendingPick)
        XCTAssertEqual(request.mode, .pair)
        XCTAssertEqual(request.mode.selectionLimit, 2)
        XCTAssertEqual(request.mode.slots, [.original, .edited])
        XCTAssertEqual(viewModel.rows[0].id, request.pairID)
        XCTAssertEqual(viewModel.rows[0].pair.assessment, .waitingForImages)
    }

    func testCancelKeepsPlaceholderAndNextAddReusesIt() async throws {
        let viewModel = await PairingTestFactory.startedViewModel()
        viewModel.addPair()
        let pairID = try XCTUnwrap(viewModel.pendingPick?.pairID)
        viewModel.cancelPick()

        XCTAssertNil(viewModel.pendingPick)
        XCTAssertEqual(viewModel.rows.count, 1)
        XCTAssertTrue(viewModel.rows[0].pair.isComplete == false)

        viewModel.addPair()
        XCTAssertEqual(viewModel.rows.count, 1)
        XCTAssertEqual(viewModel.pendingPick?.pairID, pairID)
    }

    func testImportTwoPhotosGradesAndPersists() async throws {
        let analyzer = RecordingQualityAnalyzer(quality: PairingTestFactory.quality(.good))
        let store = InMemoryPairingSessionStore()
        let viewModel = await PairingTestFactory.startedViewModel(
            analyzer: analyzer,
            store: store
        )

        let addedID = await PairingTestFactory.addPair(to: viewModel)
        let pairID = try XCTUnwrap(addedID)
        await viewModel.flushPersistence()

        XCTAssertEqual(viewModel.rows.count, 1)
        let pair = try XCTUnwrap(viewModel.rows.first?.pair)
        XCTAssertEqual(pair.id, pairID)
        XCTAssertEqual(pair.quality, PairingTestFactory.quality(.good))
        XCTAssertTrue(pair.isComplete)
        XCTAssertEqual(viewModel.progress.label, "1/3")
        XCTAssertEqual(viewModel.progress.good, 1)
        XCTAssertFalse(viewModel.canContinue)
        XCTAssertNil(viewModel.pendingPick)
        XCTAssertNil(viewModel.importingPairID)

        let calls = await analyzer.callCount
        XCTAssertEqual(calls, 1)

        let storedSnapshot = await store.currentSnapshot()
        let snapshot = try XCTUnwrap(storedSnapshot)
        XCTAssertEqual(snapshot.pairs.count, 1)
        XCTAssertEqual(snapshot.pairs[0].quality?.grade, .good)
        XCTAssertEqual(viewModel.saveState, .saved(date))
    }

    func testImportOnePhotoLeavesTheSecondSlotOpen() async throws {
        let analyzer = RecordingQualityAnalyzer(quality: PairingTestFactory.quality(.good))
        let viewModel = await PairingTestFactory.startedViewModel(analyzer: analyzer)
        viewModel.addPair()
        let request = try XCTUnwrap(viewModel.pendingPick)

        await viewModel.importPickedPhotos([
            PairingPickedPhoto(data: Data([0x01]), sourceIdentifier: "original-1")
        ])

        let pair = try XCTUnwrap(viewModel.rows.first?.pair)
        XCTAssertEqual(pair.id, request.pairID)
        XCTAssertEqual(pair.original?.sourceIdentifier, "original-1")
        XCTAssertNil(pair.edited)
        XCTAssertNil(pair.quality)
        XCTAssertEqual(viewModel.progress.label, "0/3")
        XCTAssertNil(viewModel.pendingPick)

        let calls = await analyzer.callCount
        XCTAssertEqual(calls, 0)
    }

    func testImportIsAtomicWhenTheSecondPhotoFails() async throws {
        let importer = SequencedImageImporter(successfulImports: 1)
        let viewModel = await PairingTestFactory.startedViewModel(importer: importer)
        let addedID = await PairingTestFactory.addPair(to: viewModel)
        let pairID = try XCTUnwrap(addedID)

        let pair = try XCTUnwrap(viewModel.rows.first?.pair)
        XCTAssertEqual(pair.id, pairID)
        XCTAssertNil(pair.original, "a failed batch must not attach a partial pair")
        XCTAssertNil(pair.edited)
        XCTAssertEqual(viewModel.notice?.action, .reopenPicker(.pair, pairID: pairID))
    }

    func testReplacementKeepsTheOtherPhotoAndReassesses() async throws {
        let analyzer = RecordingQualityAnalyzer(quality: PairingTestFactory.quality(.good))
        let viewModel = await PairingTestFactory.startedViewModel(analyzer: analyzer)
        let addedID = await PairingTestFactory.addPair(
            to: viewModel,
            originalIdentifier: "original-1",
            editedIdentifier: "edited-1"
        )
        let pairID = try XCTUnwrap(addedID)
        let before = try XCTUnwrap(viewModel.rows.first?.pair)

        await PairingTestFactory.replace(
            .original,
            in: viewModel,
            pairID: pairID,
            identifier: "original-2"
        )

        let after = try XCTUnwrap(viewModel.rows.first?.pair)
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.edited, before.edited)
        XCTAssertEqual(after.original?.sourceIdentifier, "original-2")
        XCTAssertEqual(after.quality?.grade, .good)

        let calls = await analyzer.callCount
        XCTAssertEqual(calls, 2, "a replacement must be checked again")
    }

    func testFailedReplacementKeepsTheExistingPhoto() async throws {
        let importer = SequencedImageImporter(successfulImports: 2)
        let viewModel = await PairingTestFactory.startedViewModel(importer: importer)
        let addedID = await PairingTestFactory.addPair(
            to: viewModel,
            originalIdentifier: "original-1",
            editedIdentifier: "edited-1"
        )
        let pairID = try XCTUnwrap(addedID)
        let before = try XCTUnwrap(viewModel.rows.first?.pair)

        await PairingTestFactory.replace(
            .original,
            in: viewModel,
            pairID: pairID,
            identifier: "original-2"
        )

        let after = try XCTUnwrap(viewModel.rows.first?.pair)
        XCTAssertEqual(after.original, before.original)
        XCTAssertEqual(after.edited, before.edited)
        XCTAssertEqual(after.quality?.grade, .good)
        XCTAssertEqual(viewModel.notice?.action, .reopenPicker(.slot(.original), pairID: pairID))
    }

    // MARK: - Deletion and undo

    func testDeletePairAndUndoRestoresIt() async throws {
        let viewModel = await PairingTestFactory.startedViewModel()
        let addedID = await PairingTestFactory.addPair(to: viewModel)
        let firstID = try XCTUnwrap(addedID)
        _ = await PairingTestFactory.addPair(to: viewModel)
        XCTAssertEqual(viewModel.rows.count, 2)

        viewModel.deletePair(firstID)
        XCTAssertEqual(viewModel.rows.count, 1)
        XCTAssertEqual(viewModel.undo?.isPairDeletion, true)

        viewModel.undoDelete()
        XCTAssertEqual(viewModel.rows.count, 2)
        XCTAssertEqual(viewModel.rows[0].id, firstID)
        XCTAssertNil(viewModel.undo)
        await viewModel.flushPersistence()
    }

    func testRemovePhotoAndUndoRestoresGrade() async throws {
        let analyzer = RecordingQualityAnalyzer(quality: PairingTestFactory.quality(.good))
        let viewModel = await PairingTestFactory.startedViewModel(analyzer: analyzer)
        let addedID = await PairingTestFactory.addPair(to: viewModel)
        let pairID = try XCTUnwrap(addedID)

        viewModel.removePhoto(.original, in: pairID)
        XCTAssertNil(viewModel.rows[0].pair.original)
        XCTAssertNil(viewModel.rows[0].pair.quality)
        XCTAssertEqual(viewModel.undo?.deletedSlot, .original)

        viewModel.undoDelete()
        XCTAssertEqual(viewModel.rows[0].pair.original != nil, true)
        XCTAssertEqual(viewModel.rows[0].pair.quality?.grade, .good)

        let calls = await analyzer.callCount
        XCTAssertEqual(calls, 1, "undo restores the previous grade without re-analysis")
    }

    // MARK: - Learning hand-off

    func testFinishExcludesRejectedPairs() async throws {
        let analyzer = ScriptedQualityAnalyzer(grades: [.good, .warning, .rejected])
        let store = InMemoryPairingSessionStore()
        let viewModel = await PairingTestFactory.startedViewModel(
            analyzer: analyzer,
            store: store
        )
        for _ in 0..<3 {
            _ = await PairingTestFactory.addPair(to: viewModel)
        }

        let samples = try XCTUnwrap(viewModel.finish())
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(Set(samples.map(\.quality.grade)), [.good, .warning])
        XCTAssertFalse(samples.contains { $0.quality.grade == .rejected })

        let summary = viewModel.summary
        XCTAssertEqual(summary.stage, .completed)
        XCTAssertEqual(summary.rejectedCount, 1)
        XCTAssertEqual(summary.learnableCount, 2)
        XCTAssertEqual(viewModel.session.stage, .completed)

        await viewModel.flushPersistence()
        let storedSnapshot = await store.currentSnapshot()
        XCTAssertEqual(storedSnapshot?.stage, .completed)
    }

    func testFinishNeedsThreeUsablePairs() async {
        let analyzer = ScriptedQualityAnalyzer(grades: [.good, .good])
        let viewModel = await PairingTestFactory.startedViewModel(analyzer: analyzer)
        for _ in 0..<2 {
            _ = await PairingTestFactory.addPair(to: viewModel)
        }

        XCTAssertFalse(viewModel.canContinue)
        XCTAssertNil(viewModel.finish())
        XCTAssertEqual(viewModel.session.stage, .editing)
        XCTAssertEqual(viewModel.notice?.title, PairingCopy.continueHint)
    }

    func testSkipReportsSkippedStage() async {
        let viewModel = await PairingTestFactory.startedViewModel()
        _ = await PairingTestFactory.addPair(to: viewModel)

        viewModel.skip()
        XCTAssertEqual(viewModel.session.stage, .skipped)
        XCTAssertEqual(viewModel.summary.stage, .skipped)
    }

    // MARK: - Progress and targets

    func testTargetSelectionUpdatesProgressAndSaves() async throws {
        let store = InMemoryPairingSessionStore()
        let viewModel = await PairingTestFactory.startedViewModel(store: store)
        _ = await PairingTestFactory.addPair(to: viewModel)
        XCTAssertEqual(viewModel.progress.label, "1/3")

        viewModel.selectTarget(.five)
        XCTAssertEqual(viewModel.progress.label, "1/5")

        viewModel.selectTarget(.eight)
        XCTAssertEqual(viewModel.progress.label, "1/8")
        XCTAssertEqual(viewModel.session.target, .eight)

        await viewModel.flushPersistence()
        let storedSnapshot = await store.currentSnapshot()
        XCTAssertEqual(storedSnapshot?.targetCount, 8)
    }

    // MARK: - Availability and errors

    func testUnavailablePickerBlocksAdding() async {
        let viewModel = await PairingTestFactory.startedViewModel(
            availability: .unavailable(.photoLibraryRestricted)
        )

        XCTAssertFalse(viewModel.isPickerAvailable)
        XCTAssertFalse(viewModel.canAddPair)
        viewModel.addPair()
        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertEqual(viewModel.notice?.action, .refreshPickerAvailability)
    }

    func testUnavailableAnalyzerKeepsPairUngradedAndBlocksContinue() async throws {
        let viewModel = await PairingTestFactory.startedViewModel(
            analyzer: FailingQualityAnalyzer(error: .invalidState)
        )
        let addedID = await PairingTestFactory.addPair(to: viewModel)
        let pairID = try XCTUnwrap(addedID)

        let pair = try XCTUnwrap(viewModel.rows.first?.pair)
        XCTAssertEqual(pair.id, pairID)
        XCTAssertNil(pair.quality)
        XCTAssertEqual(pair.assessment.failure?.code, .analyzerUnavailable)
        XCTAssertEqual(pair.assessment.failure?.isRetryable, true)
        XCTAssertFalse(viewModel.canContinue)
        XCTAssertTrue(viewModel.session.learnableSamples.isEmpty)
    }

    func testIdenticalIdentifiersAreRejectedWithoutAnalyzer() async throws {
        let analyzer = RecordingQualityAnalyzer(quality: PairingTestFactory.quality(.good))
        let viewModel = await PairingTestFactory.startedViewModel(analyzer: analyzer)

        _ = await PairingTestFactory.addPair(
            to: viewModel,
            originalIdentifier: "same-photo",
            editedIdentifier: "same-photo"
        )

        let pair = try XCTUnwrap(viewModel.rows.first?.pair)
        XCTAssertEqual(pair.quality?.grade, .rejected)
        XCTAssertEqual(pair.quality?.reasons, [PairingQualityReasonKeys.samePhoto])
        XCTAssertTrue(viewModel.session.learnableSamples.isEmpty)

        let calls = await analyzer.callCount
        XCTAssertEqual(calls, 0, "identical picks never reach the analyzer")
    }

    func testSaveFailureIsSurfacedWithoutLosingPairs() async {
        let viewModel = await PairingTestFactory.startedViewModel(store: FailingSaveStore())
        _ = await PairingTestFactory.addPair(to: viewModel)
        await viewModel.flushPersistence()

        XCTAssertEqual(viewModel.saveState, .failed)
        XCTAssertEqual(viewModel.notice?.action, .retrySave)
        XCTAssertEqual(viewModel.rows.count, 1)
        XCTAssertEqual(viewModel.rows[0].pair.quality?.grade, .good)
    }

    func testCorruptSessionOffersFreshStart() async {
        let store = CorruptedSessionStore()
        let viewModel = await PairingTestFactory.startedViewModel(store: store)

        XCTAssertEqual(viewModel.notice?.title, PairingCopy.sessionCorruptedTitle)
        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertTrue(viewModel.hasLoaded)

        await viewModel.perform(.startFreshSession)
        let clearCount = await store.clearCount
        XCTAssertEqual(clearCount, 1)
        XCTAssertNil(viewModel.notice)
        XCTAssertTrue(viewModel.rows.isEmpty)
    }

    // MARK: - Restore

    func testRestoredSessionNeedsReselectionBeforeItCounts() async throws {
        let snapshot = PairingTestFactory.session(grades: [.good], target: .three).snapshot()
        let store = InMemoryPairingSessionStore(snapshot: snapshot)
        let viewModel = await PairingTestFactory.startedViewModel(store: store)

        XCTAssertEqual(viewModel.rows.count, 1)
        let restored = try XCTUnwrap(viewModel.rows.first?.pair)
        XCTAssertTrue(restored.needsReselectOriginal)
        XCTAssertTrue(restored.needsReselectEdited)
        XCTAssertNil(restored.original)
        XCTAssertEqual(restored.quality?.grade, .good, "the old grade stays visible as guidance")
        XCTAssertEqual(viewModel.progress.eligible, 0)
        XCTAssertEqual(viewModel.notice?.title, PairingCopy.restoredNotice)

        await PairingTestFactory.replace(
            .original,
            in: viewModel,
            pairID: restored.id,
            identifier: "original-new"
        )
        XCTAssertEqual(viewModel.progress.eligible, 0)

        await PairingTestFactory.replace(
            .edited,
            in: viewModel,
            pairID: restored.id,
            identifier: "edited-new"
        )
        let regraded = try XCTUnwrap(viewModel.rows.first?.pair)
        XCTAssertEqual(regraded.quality?.grade, .good)
        XCTAssertEqual(viewModel.progress.label, "1/3")
    }

    // MARK: - Time budget

    func testTwelvePairsMeetTheSixMinuteBudget() async throws {
        let clock = AdjustableTestClock()
        let store = InMemoryPairingSessionStore()
        let viewModel = await PairingTestFactory.startedViewModel(
            store: store,
            clock: clock,
            target: .eight
        )

        for _ in 0..<12 {
            clock.advance(by: 25)
            let pairID = await PairingTestFactory.addPair(to: viewModel)
            XCTAssertNotNil(pairID)
        }

        XCTAssertEqual(viewModel.rows.count, 12)
        XCTAssertEqual(viewModel.progress.eligible, 12)
        XCTAssertEqual(viewModel.progress.label, "8/8")

        let summary = viewModel.summary
        XCTAssertEqual(summary.elapsed, 300, accuracy: 0.001)
        XCTAssertTrue(summary.metTimeBudget)
        XCTAssertEqual(summary.budgetSeconds, 360, accuracy: 0.001)

        let samples = try XCTUnwrap(viewModel.finish())
        XCTAssertEqual(samples.count, 12)

        await viewModel.flushPersistence()
        let storedSnapshot = await store.currentSnapshot()
        XCTAssertEqual(storedSnapshot?.pairs.count, 12)
        XCTAssertEqual(storedSnapshot?.stage, .completed)
    }

    func testTwelvePairsOverBudgetAreReported() async {
        let clock = AdjustableTestClock()
        let viewModel = await PairingTestFactory.startedViewModel(
            clock: clock,
            target: .eight
        )

        for _ in 0..<12 {
            clock.advance(by: 40)
            _ = await PairingTestFactory.addPair(to: viewModel)
        }

        XCTAssertEqual(viewModel.rows.count, 12)
        let summary = viewModel.summary
        XCTAssertEqual(summary.elapsed, 480, accuracy: 0.001)
        XCTAssertFalse(summary.metTimeBudget)
    }
}
