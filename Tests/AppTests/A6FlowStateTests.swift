import XCTest
@testable import StyleTone

/// Pure transition tests for the A6 self-use flow.
///
/// No services, images or file system are involved; these tests only exercise
/// the stage machine that decides what the root view renders.
final class A6FlowStateTests: XCTestCase {
    func testLaunchWithoutProfileShowsWelcome() {
        var flow = A6FlowState()
        XCTAssertTrue(flow.reduce(.launch(hasProfile: false)))
        XCTAssertEqual(flow.stage, .welcome)
    }

    func testLaunchWithProfileGoesStraightToEditor() {
        var flow = A6FlowState()
        XCTAssertTrue(flow.reduce(.launch(hasProfile: true)))
        XCTAssertEqual(flow.stage, .editor)
    }

    func testFirstRunJourneyPairingToCalibrationToEditor() {
        var flow = A6FlowState()
        XCTAssertTrue(flow.reduce(.launch(hasProfile: false)))
        XCTAssertTrue(flow.reduce(.beginPairing))
        XCTAssertEqual(flow.stage, .pairing)

        XCTAssertTrue(flow.reduce(.finishPairing))
        XCTAssertEqual(flow.stage, .calibration)

        XCTAssertTrue(flow.reduce(.completeCalibration))
        XCTAssertEqual(flow.stage, .editor)
    }

    func testSkipPairingUsesNaturalDefault() {
        var flow = A6FlowState(stage: .pairing)
        XCTAssertTrue(flow.reduce(.skipPairing))
        XCTAssertEqual(flow.stage, .editor)
    }

    func testWelcomeNaturalDefaultGoesToEditor() {
        var flow = A6FlowState(stage: .welcome)
        XCTAssertTrue(flow.reduce(.useNaturalDefault))
        XCTAssertEqual(flow.stage, .editor)
    }

    func testEditorCanRecalibrate() {
        var flow = A6FlowState(stage: .editor)
        XCTAssertTrue(flow.reduce(.beginPairing))
        XCTAssertEqual(flow.stage, .pairing)
    }

    func testCancelCalibrationWithoutProfileReturnsToWelcome() {
        var flow = A6FlowState(stage: .calibration)
        XCTAssertTrue(flow.reduce(.cancelCalibration(hasProfile: false)))
        XCTAssertEqual(flow.stage, .welcome)
    }

    func testCancelCalibrationWithProfileReturnsToEditor() {
        var flow = A6FlowState(stage: .calibration)
        XCTAssertTrue(flow.reduce(.cancelCalibration(hasProfile: true)))
        XCTAssertEqual(flow.stage, .editor)
    }

    func testAllDataDeletedAlwaysReturnsToWelcome() {
        var flow = A6FlowState(stage: .editor)
        XCTAssertTrue(flow.reduce(.allDataDeleted))
        XCTAssertEqual(flow.stage, .welcome)
    }

    func testOutOfOrderEventsAreRejectedWithoutChangingStage() {
        var flow = A6FlowState(stage: .welcome)

        XCTAssertFalse(flow.reduce(.finishPairing))
        XCTAssertEqual(flow.stage, .welcome)

        XCTAssertFalse(flow.reduce(.completeCalibration))
        XCTAssertEqual(flow.stage, .welcome)

        XCTAssertFalse(flow.reduce(.launch(hasProfile: true)))
        XCTAssertEqual(flow.stage, .welcome)
    }
}
