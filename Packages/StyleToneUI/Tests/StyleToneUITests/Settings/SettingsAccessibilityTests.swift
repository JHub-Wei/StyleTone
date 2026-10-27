import StyleToneUI
import XCTest

/// The settings screen follows the frozen `screen.element` convention.
final class SettingsAccessibilityTests: XCTestCase {
    func testRootMatchesTheFrozenRouteIdentifier() {
        XCTAssertEqual(SettingsAccessibilityID.screen.rawValue, "settings.root")
        XCTAssertEqual(
            SettingsAccessibilityID.screen.rawValue,
            AppRoute.settings.accessibilityID.rawValue
        )
        XCTAssertEqual(SettingsAccessibilityID.screen.screen, .settings)
    }

    func testFrozenDeleteIdentifierIsReused() {
        XCTAssertEqual(
            SettingsAccessibilityID.deleteDataButton.rawValue,
            "settings.deleteDataButton"
        )
        XCTAssertEqual(
            SettingsAccessibilityID.deleteDataButton,
            AccessibilityID.settingsDeleteDataButton
        )
    }

    func testEveryIdentifierIsValidUniqueAndSettingsScoped() {
        for identifier in SettingsAccessibilityID.all {
            XCTAssertTrue(identifier.isValid, "invalid identifier: \(identifier.rawValue)")
            XCTAssertEqual(identifier.screen, .settings)
        }

        let values = SettingsAccessibilityID.all.map(\.rawValue)
        XCTAssertEqual(Set(values).count, values.count, "duplicate settings identifier")
    }

    func testExpectedInteractiveIdentifiersArePresent() {
        let expected = [
            "settings.root",
            "settings.privacyButton",
            "settings.diagnosticsToggle",
            "settings.diagnostics.copyButton",
            "settings.diagnostics.clearButton",
            "settings.deleteDataButton",
            "settings.deleteData.continueButton",
            "settings.deleteData.backButton",
            "settings.deleteData.finalButton",
            "settings.deleteData.retryButton",
            "settings.licensesButton",
            "settings.support.emailLink",
            "settings.support.copyButton",
        ]
        let values = Set(SettingsAccessibilityID.all.map(\.rawValue))
        for identifier in expected {
            XCTAssertTrue(values.contains(identifier), "missing identifier: \(identifier)")
        }
    }

    func testPrivacyAndLicensesScreensHaveTheirOwnRoots() {
        XCTAssertEqual(SettingsAccessibilityID.privacyScreen.rawValue, "settings.privacy.root")
        XCTAssertEqual(SettingsAccessibilityID.licensesScreen.rawValue, "settings.licenses.root")
        XCTAssertTrue(SettingsAccessibilityID.privacyScreen.isValid)
        XCTAssertTrue(SettingsAccessibilityID.licensesScreen.isValid)
    }

    func testDeletionFlowIdentifiersStayOnTheSettingsScreen() {
        let deletion = [
            SettingsAccessibilityID.deleteDataButton,
            SettingsAccessibilityID.deleteSheet,
            SettingsAccessibilityID.deleteCancelButton,
            SettingsAccessibilityID.deleteContinueButton,
            SettingsAccessibilityID.deleteBackButton,
            SettingsAccessibilityID.deleteFinalButton,
            SettingsAccessibilityID.deleteProgress,
            SettingsAccessibilityID.deleteSuccess,
            SettingsAccessibilityID.deleteStartOverButton,
            SettingsAccessibilityID.deleteRetryButton,
            SettingsAccessibilityID.deleteFailure,
        ]
        for identifier in deletion {
            XCTAssertEqual(identifier.screen, .settings)
            XCTAssertTrue(identifier.isValid)
        }
    }

    func testDiagnosticsIdentifiersAreNestedUnderDiagnostics() {
        let identifiers = [
            SettingsAccessibilityID.diagnosticsToggle,
            SettingsAccessibilityID.diagnosticsStatus,
            SettingsAccessibilityID.diagnosticsData,
            SettingsAccessibilityID.diagnosticsNeverData,
            SettingsAccessibilityID.diagnosticsCode,
            SettingsAccessibilityID.diagnosticsCodeHint,
            SettingsAccessibilityID.diagnosticsCopyButton,
            SettingsAccessibilityID.diagnosticsClearButton,
            SettingsAccessibilityID.diagnosticsEntries,
        ]
        for identifier in identifiers {
            XCTAssertTrue(identifier.rawValue.hasPrefix("settings.diagnostics"))
            XCTAssertTrue(identifier.isValid)
        }
    }
}
