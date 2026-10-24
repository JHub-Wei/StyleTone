import Foundation
import StyleToneCore
import StyleToneUI
import XCTest

/// Pure state-machine tests: no SwiftUI, no rendering, no real photos.
final class PairingSessionStateTests: XCTestCase {
    private let date = PairingTestFactory.referenceDate

    // MARK: - Pairs

    func testAddPairCapsAtTwelve() {
        var session = PairingSessionState(target: .three, startedAt: date)
        for _ in 0..<PairingSessionState.maximumPairs {
            XCTAssertNotNil(session.addPair(now: date))
        }
        XCTAssertEqual(session.pairs.count, PairingSessionState.maximumPairs)
        XCTAssertTrue(session.isFull)
        XCTAssertNil(session.addPair(now: date))
        XCTAssertEqual(session.pairs.count, PairingSessionState.maximumPairs)
    }

    func testAttachKeepsTheOtherSlotAndClearsQuality() {
        var session = PairingTestFactory.session(grades: [.good], target: .three)
        let pairID = session.pairs[0].id
        let editedBefore = session.pairs[0].edited
        let revisionBefore = session.pairs[0].contentRevision

        let replacement = PairingTestFactory.photo(seed: 9, at: date)
        XCTAssertNotNil(replacement)
        guard let replacement else { return }

        XCTAssertTrue(session.attach(replacement, to: .original, pairID: pairID, now: date))
        let pair = session.pairs[0]
        XCTAssertEqual(pair.original, replacement)
        XCTAssertEqual(pair.edited, editedBefore)
        XCTAssertNil(pair.quality)
        XCTAssertTrue(pair.assessment.isWaitingForImages)
        XCTAssertEqual(pair.contentRevision, revisionBefore + 1)
    }

    func testRemovePhotoKeepsPairAndUndoRestoresGrade() {
        var session = PairingTestFactory.session(grades: [.good], target: .three)
        let pairID = session.pairs[0].id
        let photo = session.pairs[0].original

        XCTAssertTrue(session.removePhoto(.original, from: pairID, now: date))
        XCTAssertEqual(session.pairs.count, 1)
        XCTAssertNil(session.pairs[0].original)
        XCTAssertNil(session.pairs[0].quality)
        XCTAssertNotNil(session.lastDeletion)

        XCTAssertTrue(session.undoLastDeletion(now: date))
        XCTAssertEqual(session.pairs[0].original, photo)
        XCTAssertEqual(session.pairs[0].quality?.grade, .good)
        XCTAssertNil(session.lastDeletion)
    }

    func testDeletePairAndUndoRestoresOrder() {
        var session = PairingTestFactory.session(grades: [.good, .good, .good], target: .three)
        let ids = session.pairs.map(\.id)

        XCTAssertTrue(session.deletePair(ids[1], now: date))
        XCTAssertEqual(session.pairs.map(\.id), [ids[0], ids[2]])
        XCTAssertEqual(session.lastDeletion?.isPairDeletion, true)

        XCTAssertTrue(session.undoLastDeletion(now: date))
        XCTAssertEqual(session.pairs.map(\.id), ids)
    }

    func testUndoWithoutDeletionReturnsFalse() {
        var session = PairingTestFactory.session(grades: [.good], target: .three)
        XCTAssertFalse(session.undoLastDeletion(now: date))
    }

    func testDeletingResetsCompletedStageToEditing() {
        var session = PairingTestFactory.session(grades: [.good, .good, .good], target: .three)
        XCTAssertTrue(session.complete(at: date))
        XCTAssertEqual(session.stage, .completed)

        XCTAssertTrue(session.deletePair(session.pairs[0].id, now: date))
        XCTAssertEqual(session.stage, .editing)
    }

    // MARK: - Quality and learning

    func testRedPairIsNeverLearnable() {
        var session = PairingTestFactory.session(
            grades: [.rejected, .rejected, .rejected],
            target: .three
        )
        XCTAssertEqual(session.learnableCount, 0)
        XCTAssertEqual(session.progress.rejected, 3)
        XCTAssertTrue(session.learnableSamples.isEmpty)
        XCTAssertFalse(session.canContinue)
        XCTAssertFalse(session.complete(at: date))
    }

    func testWarningPairsAreLearnableButRejectedAreNot() {
        let session = PairingTestFactory.session(
            grades: [.good, .warning, .rejected],
            target: .three
        )
        XCTAssertEqual(session.learnableCount, 2)
        XCTAssertEqual(session.learnableSamples.count, 2)
        XCTAssertEqual(session.progress.good, 1)
        XCTAssertEqual(session.progress.warning, 1)
        XCTAssertEqual(session.progress.rejected, 1)
        XCTAssertEqual(session.progress.eligible, 2)
        XCTAssertFalse(session.canContinue)
    }

    func testThreeUsablePairsEnableCompletion() {
        var session = PairingTestFactory.session(
            grades: [.good, .warning, .good],
            target: .five
        )
        XCTAssertTrue(session.canContinue)
        XCTAssertTrue(session.complete(at: date))
        XCTAssertEqual(session.stage, .completed)
        XCTAssertEqual(session.learnableSamples.count, 3)
    }

    func testRejectedPairDoesNotCountTowardsMinimum() {
        let session = PairingTestFactory.session(
            grades: [.good, .good, .rejected],
            target: .three
        )
        XCTAssertFalse(session.canContinue)
        XCTAssertEqual(session.remainingToMinimum, 1)
    }

    // MARK: - Progress

    func testProgressLabelsForThreeFiveEight() {
        var session = PairingTestFactory.session(grades: [.good], target: .three)
        XCTAssertEqual(session.progress.label, "1/3")

        session.setTarget(.five, now: date)
        XCTAssertEqual(session.progress.label, "1/5")

        session.setTarget(.eight, now: date)
        XCTAssertEqual(session.progress.label, "1/8")
    }

    func testProgressCapsAtTargetAndCountsPending() {
        var session = PairingTestFactory.session(
            grades: [.good, .good, .good, .good, .good],
            target: .three
        )
        XCTAssertEqual(session.progress.label, "3/3")
        XCTAssertEqual(session.progress.eligible, 5)

        session.setTarget(.eight, now: date)
        XCTAssertEqual(session.progress.label, "5/8")
        XCTAssertEqual(session.progress.pending, 0)
    }

    func testIncompletePairsArePending() {
        var session = PairingSessionState(target: .three, startedAt: date)
        XCTAssertNotNil(session.addPair(now: date))
        XCTAssertEqual(session.progress.pending, 1)
        XCTAssertEqual(session.progress.eligible, 0)
        XCTAssertEqual(session.progress.fraction, 0, accuracy: 0.0001)
    }

    // MARK: - Assessment guards

    func testRevisionGuardDropsStaleAssessment() {
        var session = PairingTestFactory.session(grades: [.good], target: .three)
        let pairID = session.pairs[0].id
        guard let revision = session.beginAssessment(for: pairID, now: date) else {
            return XCTFail("a complete pair must begin assessment")
        }
        // The user replaces a photo while the analyzer runs.
        let replacement = PairingTestFactory.photo(seed: 7, at: date)
        XCTAssertNotNil(replacement)
        guard let replacement else { return }
        session.attach(replacement, to: .edited, pairID: pairID, now: date)

        let staleQuality = PairingTestFactory.quality(.good)
        XCTAssertFalse(
            session.completeAssessment(
                staleQuality,
                for: pairID,
                revision: revision,
                now: date
            )
        )
        XCTAssertNil(session.pairs[0].quality)
        XCTAssertEqual(session.pairs[0].contentRevision, revision + 1)
    }

    func testIdenticalSelectionIsRejectedWithoutAnalyzerInput() {
        var session = PairingSessionState(target: .three, startedAt: date)
        guard let pairID = session.addPair(now: date) else {
            return XCTFail("pair should be created")
        }
        guard let original = PairingTestFactory.photo(seed: 1, at: date),
              let edited = PairingTestFactory.photo(seed: 1, at: date)
        else {
            return XCTFail("fixture photos should exist")
        }
        session.attach(original, to: .original, pairID: pairID, now: date)
        session.attach(edited, to: .edited, pairID: pairID, now: date)

        XCTAssertTrue(session.hasIdenticalSelection(pairID))
        let revision = session.pairs[0].contentRevision
        XCTAssertTrue(
            session.rejectIdenticalSelection(for: pairID, revision: revision, now: date)
        )
        XCTAssertEqual(session.pairs[0].quality?.grade, .rejected)
        XCTAssertEqual(
            session.pairs[0].quality?.reasons,
            [PairingQualityReasonKeys.samePhoto]
        )
        XCTAssertTrue(session.learnableSamples.isEmpty)
    }

    // MARK: - Timeline and summary

    func testTwelvePairSessionMeetsSixMinuteBudget() {
        var session = PairingSessionState(target: .eight, startedAt: date)
        for index in 0..<12 {
            let now = date.addingTimeInterval(Double(index + 1) * 25)
            guard let pairID = session.addPair(now: now),
                  let original = PairingTestFactory.photo(seed: index, at: now),
                  let edited = PairingTestFactory.photo(seed: index, at: now)
            else {
                return XCTFail("pair \(index) should be created")
            }
            session.attach(original, to: .original, pairID: pairID, now: now)
            session.attach(edited, to: .edited, pairID: pairID, now: now)
        }

        let summary = session.summary(at: date.addingTimeInterval(300))
        XCTAssertEqual(summary.totalPairs, 12)
        XCTAssertEqual(summary.elapsed, 300, accuracy: 0.001)
        XCTAssertTrue(summary.metTimeBudget)
        XCTAssertEqual(summary.budgetSeconds, 360, accuracy: 0.001)
        XCTAssertEqual(summary.budgetPairCount, 12)
        XCTAssertTrue(session.meetsTimeBudget(at: date.addingTimeInterval(300)))
        XCTAssertFalse(session.meetsTimeBudget(at: date.addingTimeInterval(361)))
    }

    func testSummaryCountsAndStage() {
        var session = PairingTestFactory.session(
            grades: [.good, .warning, .good, .rejected],
            target: .five
        )
        XCTAssertTrue(session.complete(at: date))
        let summary = session.summary(at: date)
        XCTAssertEqual(summary.stage, .completed)
        XCTAssertEqual(summary.target, 5)
        XCTAssertEqual(summary.goodCount, 2)
        XCTAssertEqual(summary.warningCount, 1)
        XCTAssertEqual(summary.rejectedCount, 1)
        XCTAssertEqual(summary.learnableCount, 3)
    }

    func testSkippingSetsStage() {
        var session = PairingTestFactory.session(grades: [.good], target: .three)
        session.skip(at: date)
        XCTAssertEqual(session.stage, .skipped)
        XCTAssertEqual(session.summary(at: date).stage, .skipped)
        session.resumeEditing(now: date)
        XCTAssertEqual(session.stage, .editing)
    }

    func testTimelineRecordsPairCompletions() {
        let session = PairingTestFactory.session(
            grades: [.good, .warning],
            target: .three
        )
        XCTAssertEqual(session.timeline.completedPairTimestamps.count, 2)
        let average = session.timeline.averageSecondsPerPair(at: date)
        XCTAssertEqual(average ?? -1, 0, accuracy: 0.001)
    }
}
