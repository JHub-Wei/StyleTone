import StyleToneUI
import SwiftUI
import XCTest

/// View-construction and accessibility checks for the shared error surface.
@MainActor
final class ErrorStateViewTests: XCTestCase {
    func testAccessibilityIdentifiersAreValidAndUnique() {
        let identifiers = ErrorStateAccessibility.all
        XCTAssertFalse(identifiers.isEmpty)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)

        for identifier in identifiers {
            XCTAssertTrue(identifier.isValid, "invalid id \(identifier.rawValue)")
            XCTAssertEqual(identifier.screen, .designSystem)
        }

        XCTAssertEqual(
            ErrorStateAccessibility.actionButton(.retry).rawValue,
            "designSystem.error.action.retry"
        )
        XCTAssertEqual(
            ErrorStateAccessibility.actionButton(.openSettings).rawValue,
            "designSystem.error.action.openSettings"
        )
    }

    func testCardBuildsForEveryKindAndAction() {
        for kind in ErrorKind.allCases {
            let state = ErrorState(kind: kind)
            let card = ErrorStateCard(state: state) { _ in }
            _ = card
        }

        var actions: [RecoveryAction] = RecoveryAction.allCases
        actions.append(.dismiss)
        let state = ErrorState(kind: .unknown, recoveryActions: actions)
        _ = ErrorStateCard(state: state) { _ in }
    }

    func testPresentationModifierBuilds() {
        let presenter = ErrorPresenter(
            logger: EdgeCaseRecordingLogger(),
            dateProvider: EdgeCaseDateProvider()
        )
        let view = Color.clear.errorStatePresentation(presenter)
        _ = view
    }

    func testSilentStateHasNoButtons() {
        let state = ErrorState(kind: .cancelled)
        XCTAssertTrue(state.recoveryActions.isEmpty)
        _ = ErrorStateCard(state: state) { _ in }
    }

    func testEveryActionHasASystemImageAndPreferredFlag() {
        for action in RecoveryAction.allCases {
            XCTAssertFalse(action.systemImage.isEmpty, "\(action)")
            XCTAssertFalse(action.title.text.isEmpty, "\(action)")
        }
        XCTAssertFalse(RecoveryAction.dismiss.isPreferred)
        XCTAssertTrue(RecoveryAction.retry.isPreferred)
    }
}
