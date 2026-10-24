import XCTest
import StyleToneUI

/// Pure logic from the components that can be verified without rendering.
final class ComponentBehaviorTests: XCTestCase {
    func testSliderNormalizedValueClampsToRange() {
        XCTAssertEqual(
            SliderRow.normalizedValue(0.5, in: 0...1),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SliderRow.normalizedValue(-3, in: 0...1),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SliderRow.normalizedValue(3, in: 0...1),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SliderRow.normalizedValue(100, in: 1...5),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SliderRow.normalizedValue(0, in: 0...0),
            0,
            accuracy: 0.0001
        )
    }

    func testToastDurationDefaultsAndClamping() {
        XCTAssertEqual(ToastMessage(text: "Saved").duration, 4)
        XCTAssertEqual(ToastMessage(text: "Saved", duration: -10).duration, 0)
        XCTAssertTrue(ToastMessage(text: "Saved", duration: 0).isPersistent)
        XCTAssertFalse(ToastMessage(text: "Saved").isPersistent)
    }

    func testToastKindsCoverAllStates() {
        XCTAssertEqual(ToastMessage.Kind.allCases.count, 4)
        XCTAssertEqual(ToastMessage.Kind.info.rawValue, "info")
        XCTAssertEqual(ToastMessage.Kind.error.rawValue, "error")
    }

    func testToastDismissIdentifierFollowsConvention() {
        let dismissID = "\(AccessibilityID.designSystemToast.rawValue).dismissButton"
        XCTAssertTrue(AccessibilityID(rawValue: dismissID).isValid)
        XCTAssertEqual(AccessibilityID(rawValue: dismissID).screen, .designSystem)
    }
}
