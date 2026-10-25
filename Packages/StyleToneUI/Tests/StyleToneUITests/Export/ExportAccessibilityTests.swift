import StyleToneUI
import XCTest

/// The frozen `screen.element` convention for the export sheet.
final class ExportAccessibilityTests: XCTestCase {
    func testScreenUsesTheExportRouteIdentifier() {
        XCTAssertEqual(ExportAccessibilityID.screen.rawValue, "export.root")
        XCTAssertEqual(
            ExportAccessibilityID.screen.rawValue,
            AppRoute.export.accessibilityID.rawValue
        )
        XCTAssertEqual(ExportAccessibilityID.screen.screen, .export)
    }

    func testContractActionsAreReusedNotDuplicated() {
        XCTAssertEqual(
            ExportAccessibilityID.saveButton.rawValue,
            "export.exportButton"
        )
        XCTAssertEqual(
            ExportAccessibilityID.closeButton.rawValue,
            "export.closeButton"
        )
        XCTAssertTrue(AccessibilityID.all.contains(ExportAccessibilityID.saveButton))
        XCTAssertTrue(AccessibilityID.all.contains(ExportAccessibilityID.closeButton))
    }

    func testAllIdentifiersAreValidUniqueAndOnTheExportScreen() {
        for identifier in ExportAccessibilityID.all {
            XCTAssertTrue(identifier.isValid, "invalid identifier: \(identifier.rawValue)")
            XCTAssertEqual(identifier.screen, .export)
        }
        let values = ExportAccessibilityID.all.map(\.rawValue)
        XCTAssertEqual(Set(values).count, values.count)
    }

    func testEachRecoveryHasItsOwnAddressableButton() {
        var identifiers: [String] = []
        for recovery in ExportFailure.Recovery.allCases {
            let identifier = ExportAccessibilityID.failureButton(recovery)
            XCTAssertTrue(identifier.isValid, "invalid id for \(recovery.rawValue)")
            XCTAssertEqual(identifier.screen, .export)
            identifiers.append(identifier.rawValue)
        }
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertEqual(
            ExportAccessibilityID.failureButton(.openSettings).rawValue,
            "export.failure.settingsButton"
        )
        XCTAssertEqual(
            ExportAccessibilityID.permissionSettingsButton.rawValue,
            "export.permissionNotice.settingsButton"
        )
    }

    func testResultAndProgressIdentifiersAreNested() {
        XCTAssertEqual(
            ExportAccessibilityID.progressValue.rawValue,
            "export.progress.value"
        )
        XCTAssertEqual(
            ExportAccessibilityID.resultDoneButton.rawValue,
            "export.result.doneButton"
        )
        XCTAssertEqual(
            ExportAccessibilityID.resultDetail.rawValue,
            "export.result.detail"
        )
        XCTAssertEqual(
            ExportAccessibilityID.infoDismissButton.rawValue,
            "export.infoNotice.dismissButton"
        )
    }
}
