import XCTest
@testable import StyleToneUI

final class EditorHistoryTests: XCTestCase {
    func testCapacityIsAtLeastTwenty() {
        XCTAssertEqual(EditorHistory().capacity, 30)
        XCTAssertEqual(EditorHistory(capacity: 1).capacity, 20)
        XCTAssertEqual(EditorHistory(capacity: 1_000).capacity, 100)
    }

    func testTwentyFiveUndoStepsAndRedo() {
        var history = EditorHistory()
        var state = EditorEditState.initial

        for index in 1...25 {
            var next = state
            next.setStrength(1.0 + Double(index) / 100)
            history.record(state)
            state = next
        }

        XCTAssertEqual(history.undoCount, 25)
        XCTAssertTrue(history.canUndo)

        for _ in 0..<20 {
            guard let previous = history.undo(current: state) else {
                return XCTFail("expected 20 undo steps")
            }
            state = previous
        }

        XCTAssertEqual(history.undoCount, 5)
        XCTAssertEqual(history.redoCount, 20)
        XCTAssertEqual(state.strength, 1.05, accuracy: 0.0001)

        for _ in 0..<5 {
            guard let previous = history.undo(current: state) else {
                return XCTFail("expected the remaining five undo steps")
            }
            state = previous
        }
        XCTAssertEqual(state.strength, 1.0, accuracy: 0.0001)

        for _ in 0..<25 {
            guard let next = history.redo(current: state) else {
                return XCTFail("expected 25 redo steps")
            }
            state = next
        }

        XCTAssertEqual(state.strength, 1.25, accuracy: 0.0001)
        XCTAssertFalse(history.canRedo)
    }

    func testNewEditClearsRedoBranch() {
        var history = EditorHistory()
        let first = EditorEditState.initial
        var second = first
        second.setStrength(1.1)

        history.record(first)
        XCTAssertTrue(history.canUndo)

        guard let restored = history.undo(current: second) else {
            return XCTFail("undo should return the initial state")
        }
        XCTAssertEqual(restored, first)
        XCTAssertTrue(history.canRedo)

        history.record(first)
        XCTAssertFalse(history.canRedo)
    }

    func testCapacityDropsOldestEntries() {
        var history = EditorHistory(capacity: 20)
        var state = EditorEditState.initial

        for index in 1...30 {
            var next = state
            next.setStrength(1.0 + Double(index) / 100)
            history.record(state)
            state = next
        }

        XCTAssertEqual(history.undoCount, 20)
        for _ in 0..<20 {
            state = history.undo(current: state) ?? state
        }
        XCTAssertFalse(history.canUndo)
        XCTAssertEqual(state.strength, 1.10, accuracy: 0.0001)
    }

    func testClearRemovesBothStacks() {
        var history = EditorHistory()
        var state = EditorEditState.initial
        var next = state
        next.setStrength(1.2)
        history.record(state)
        state = next
        _ = history.undo(current: state)

        history.clear()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }
}
