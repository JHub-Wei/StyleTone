import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

/// Screen-level composition and the end-to-end UI script.
///
/// The package has no XCUITest bundle (that arrives with WP-24), so these tests
/// drive the exact sequence the screen performs and assert the identifiers and
/// state the UI test will query.
@MainActor
final class PairingScreenTests: XCTestCase {
    private let date = PairingTestFactory.referenceDate

    func testScreenBuildsWithPlaceholderDependencies() {
        let viewModel = PairingViewModel(dependencies: .placeholder)
        _ = PairingScreen(
            viewModel: viewModel,
            onFinish: { _, _ in },
            onSkip: { _ in }
        )
        XCTAssertFalse(viewModel.hasLoaded)
        XCTAssertFalse(viewModel.canAddPair)
        XCTAssertTrue(viewModel.rows.isEmpty)
    }

    func testRowsMatchPairNumbersAndIdentifiers() {
        let session = PairingTestFactory.session(
            grades: [.good, .warning, .rejected],
            target: .five
        )
        XCTAssertEqual(session.rows.map(\.number), [1, 2, 3])
        XCTAssertEqual(session.rows.map(\.pair.id), session.pairs.map(\.id))

        for row in session.rows {
            XCTAssertEqual(
                PairingAccessibilityID.pair(row.number).rawValue,
                "pairing.pair\(row.number)"
            )
            XCTAssertEqual(
                PairingAccessibilityID.quality(pair: row.number).rawValue,
                "pairing.pair\(row.number).quality"
            )
        }
    }

    func testAcceptanceConstants() {
        XCTAssertEqual(PairingSessionState.maximumPairs, 12)
        XCTAssertEqual(PairingSessionState.minimumLearnablePairs, 3)
        XCTAssertEqual(PairingSessionState.timeBudgetSeconds, 360)
        XCTAssertEqual(PairingSessionState.timeBudgetPairCount, 12)
        XCTAssertEqual(PairingTarget.allCases.map(\.count), [3, 5, 8])
    }

    func testUIScriptOfThreePairsReplaceDeleteUndoAndFinish() async throws {
        let analyzer = ScriptedQualityAnalyzer(grades: [.good, .good, .warning])
        let store = InMemoryPairingSessionStore()
        let clock = AdjustableTestClock()
        let viewModel = await PairingTestFactory.startedViewModel(
            analyzer: analyzer,
            store: store,
            clock: clock
        )

        // 1. Add three pairs through the picker flow.
        var pairIDs: [UUID] = []
        for _ in 0..<3 {
            clock.advance(by: 20)
            let added = await PairingTestFactory.addPair(to: viewModel)
            pairIDs.append(try XCTUnwrap(added))
        }
        XCTAssertEqual(viewModel.rows.count, 3)
        XCTAssertEqual(viewModel.progress.label, "3/3")
        XCTAssertTrue(viewModel.canContinue)

        // 2. Replace the edited photo of the second pair.
        await PairingTestFactory.replace(
            .edited,
            in: viewModel,
            pairID: pairIDs[1],
            identifier: "edited-replacement"
        )
        let replaced = try XCTUnwrap(viewModel.rows[1].pair)
        XCTAssertEqual(replaced.edited?.sourceIdentifier, "edited-replacement")
        XCTAssertNotNil(replaced.original)

        // 3. Delete the first pair and undo it.
        viewModel.deletePair(pairIDs[0])
        XCTAssertEqual(viewModel.rows.count, 2)
        viewModel.undoDelete()
        XCTAssertEqual(viewModel.rows.map(\.id), pairIDs)

        // 4. Finish; the red-free session hands all three samples over.
        let samples = try XCTUnwrap(viewModel.finish())
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(viewModel.summary.stage, .completed)
        XCTAssertEqual(viewModel.summary.totalPairs, 3)
        XCTAssertEqual(viewModel.summary.elapsed, 60, accuracy: 0.001)

        await viewModel.flushPersistence()
        let storedSnapshot = await store.currentSnapshot()
        XCTAssertEqual(storedSnapshot?.pairs.count, 3)
        XCTAssertEqual(storedSnapshot?.stage, .completed)
    }

    func testFlowWithOneRejectedPairStillLearnsFromThree() async throws {
        let analyzer = ScriptedQualityAnalyzer(grades: [.good, .good, .warning, .rejected])
        let viewModel = await PairingTestFactory.startedViewModel(
            analyzer: analyzer,
            target: .three
        )

        for _ in 0..<4 {
            _ = await PairingTestFactory.addPair(to: viewModel)
        }
        XCTAssertTrue(viewModel.canContinue)
        XCTAssertEqual(viewModel.progress.label, "3/3")
        XCTAssertEqual(viewModel.progress.rejected, 1)

        let samples = try XCTUnwrap(viewModel.finish())
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(viewModel.summary.rejectedCount, 1)
        XCTAssertTrue(samples.allSatisfy { $0.quality.grade != .rejected })
    }

    func testProgressOneOfThreeFiveAndEight() async {
        let viewModel = await PairingTestFactory.startedViewModel(target: .three)
        _ = await PairingTestFactory.addPair(to: viewModel)

        XCTAssertEqual(viewModel.progress.label, "1/3")
        viewModel.selectTarget(.five)
        XCTAssertEqual(viewModel.progress.label, "1/5")
        viewModel.selectTarget(.eight)
        XCTAssertEqual(viewModel.progress.label, "1/8")
    }
}
