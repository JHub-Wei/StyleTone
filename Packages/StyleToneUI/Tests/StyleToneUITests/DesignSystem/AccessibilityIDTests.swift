import XCTest
import StyleToneUI

final class AccessibilityIDTests: XCTestCase {
    func testContractExamplesMatchExactly() {
        XCTAssertEqual(
            AccessibilityID(.onboarding, "startButton").rawValue,
            "onboarding.startButton"
        )
        XCTAssertEqual(
            AccessibilityID(.pairing, "addPairButton").rawValue,
            "pairing.addPairButton"
        )
        XCTAssertEqual(
            AccessibilityID(.editor, "faceSlimSlider").rawValue,
            "editor.faceSlimSlider"
        )
        XCTAssertEqual(
            AccessibilityID(.paywall, "subscribeButton").rawValue,
            "paywall.subscribeButton"
        )
    }

    func testPredefinedIdentifiersAreValid() {
        for identifier in AccessibilityID.all {
            XCTAssertTrue(identifier.isValid, "Invalid predefined identifier: \(identifier.rawValue)")
        }
    }

    func testPredefinedIdentifiersAreUnique() {
        let values = AccessibilityID.all.map(\.rawValue)
        XCTAssertEqual(Set(values).count, values.count)
    }

    func testScreenAndElementAreParsed() {
        let identifier = AccessibilityID(rawValue: "editor.faceSlimSlider")
        XCTAssertEqual(identifier.screen, .editor)
        XCTAssertTrue(identifier.isValid)
    }

    func testNestedElementSegmentsAreAllowed() {
        XCTAssertTrue(AccessibilityID(.shell, "tab.editor").isValid)
        XCTAssertTrue(AccessibilityID(.designSystem, "toast.dismissButton").isValid)
    }

    func testMalformedIdentifiersAreRejected() {
        let malformed = [
            "",
            "editor",
            "Editor.faceSlider",
            "unknown.slider",
            "editor.",
            "editor..slider",
            "editor.FaceSlider",
            "editor.face slider",
            "editor.slider-1",
        ]
        for rawValue in malformed {
            XCTAssertFalse(
                AccessibilityID(rawValue: rawValue).isValid,
                "Should reject \(rawValue)"
            )
        }
    }

    func testEveryScreenCanBuildAnIdentifier() {
        for screen in AccessibilityScreen.allCases {
            let identifier = AccessibilityID(screen, "root")
            XCTAssertTrue(identifier.isValid)
            XCTAssertEqual(identifier.screen, screen)
        }
    }

    func testRawRepresentableRoundTrip() {
        let identifier = AccessibilityID(rawValue: "settings.deleteDataButton")
        XCTAssertEqual(identifier.rawValue, "settings.deleteDataButton")
        XCTAssertEqual(identifier.description, identifier.rawValue)
    }
}
