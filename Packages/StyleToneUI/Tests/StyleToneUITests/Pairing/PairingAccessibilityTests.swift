import StyleToneCore
import StyleToneUI
import XCTest

/// The `screen.element` convention and the per-pair identifier layout.
final class PairingAccessibilityTests: XCTestCase {
    func testScreenUsesTheFrozenRouteIdentifier() {
        XCTAssertEqual(PairingAccessibilityID.screen.rawValue, "pairing.root")
        XCTAssertEqual(
            PairingAccessibilityID.screen.rawValue,
            AppRoute.pairing.accessibilityID.rawValue
        )
        XCTAssertEqual(PairingAccessibilityID.screen.screen, .pairing)
    }

    func testContractIdentifiersAreReusedNotDuplicated() {
        XCTAssertEqual(
            PairingAccessibilityID.addPairButton.rawValue,
            "pairing.addPairButton"
        )
        XCTAssertEqual(
            PairingAccessibilityID.continueButton.rawValue,
            "pairing.continueButton"
        )
        XCTAssertTrue(AccessibilityID.all.contains(PairingAccessibilityID.addPairButton))
        XCTAssertTrue(AccessibilityID.all.contains(PairingAccessibilityID.continueButton))
    }

    func testScreenIdentifiersAreValidUniqueAndOnThePairingScreen() {
        for identifier in PairingAccessibilityID.all {
            XCTAssertTrue(identifier.isValid, "invalid identifier: \(identifier.rawValue)")
            XCTAssertEqual(identifier.screen, .pairing)
        }
        let values = PairingAccessibilityID.all.map(\.rawValue)
        XCTAssertEqual(Set(values).count, values.count)
    }

    func testPerPairIdentifiersAreValidAndUnique() {
        for number in 1...PairingSessionState.maximumPairs {
            let identifiers = PairingAccessibilityID.identifiers(forPair: number)
            XCTAssertEqual(identifiers.count, 16)
            for identifier in identifiers {
                XCTAssertTrue(
                    identifier.isValid,
                    "invalid identifier: \(identifier.rawValue)"
                )
                XCTAssertEqual(identifier.screen, .pairing)
            }
            let values = identifiers.map(\.rawValue)
            XCTAssertEqual(Set(values).count, values.count, "pair \(number) collides")
        }
    }

    func testPerPairIdentifiersAreStableAndNestThePairSegment() {
        XCTAssertEqual(PairingAccessibilityID.pair(1).rawValue, "pairing.pair1")
        XCTAssertEqual(
            PairingAccessibilityID.photo(.original, pair: 2).rawValue,
            "pairing.pair2.original.photo"
        )
        XCTAssertEqual(
            PairingAccessibilityID.pickButton(.edited, pair: 3).rawValue,
            "pairing.pair3.edited.pickButton"
        )
        XCTAssertEqual(
            PairingAccessibilityID.removeButton(.original, pair: 4).rawValue,
            "pairing.pair4.original.removeButton"
        )
        XCTAssertEqual(
            PairingAccessibilityID.deleteButton(pair: 5).rawValue,
            "pairing.pair5.deleteButton"
        )
        XCTAssertEqual(
            PairingAccessibilityID.retryButton(pair: 6).rawValue,
            "pairing.pair6.retryButton"
        )
    }

    func testIdentifiersDoNotCollideAcrossPairs() {
        let values = (1...PairingSessionState.maximumPairs)
            .flatMap { PairingAccessibilityID.identifiers(forPair: $0) }
            .map(\.rawValue)
        XCTAssertEqual(Set(values).count, values.count)
        XCTAssertEqual(values.count, PairingSessionState.maximumPairs * 16)
    }

    func testTargetIdentifiersUseWordSegments() {
        // Numeric segments are invalid in the frozen convention, so the target
        // buttons use words even though they display digits.
        XCTAssertEqual(
            PairingAccessibilityID.target(.three).rawValue,
            "pairing.target.three"
        )
        XCTAssertEqual(
            PairingAccessibilityID.target(.five).rawValue,
            "pairing.target.five"
        )
        XCTAssertEqual(
            PairingAccessibilityID.target(.eight).rawValue,
            "pairing.target.eight"
        )
        for target in PairingTarget.allCases {
            XCTAssertTrue(PairingAccessibilityID.target(target).isValid)
        }
    }

    func testEmptyStatePhotoIdentifiers() {
        XCTAssertEqual(
            PairingAccessibilityID.emptyPhoto(.original).rawValue,
            "pairing.emptyState.original"
        )
        XCTAssertEqual(
            PairingAccessibilityID.emptyPhoto(.edited).rawValue,
            "pairing.emptyState.edited"
        )
        XCTAssertTrue(PairingAccessibilityID.emptyPhoto(.original).isValid)
        XCTAssertTrue(PairingAccessibilityID.emptyPhoto(.edited).isValid)
    }
}
