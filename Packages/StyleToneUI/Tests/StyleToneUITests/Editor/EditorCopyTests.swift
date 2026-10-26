import StyleToneCore
import XCTest
@testable import StyleToneUI

final class EditorCopyTests: XCTestCase {
    func testEveryKeyUsesEditorPrefixAndHasFallback() {
        for key in EditorCopy.allKeys {
            XCTAssertTrue(key.isValid, "Invalid key: \(key.rawValue)")
            XCTAssertEqual(key.prefix, .editor, "Wrong prefix: \(key.rawValue)")
            XCTAssertNotEqual(
                EditorCopy.text(key),
                key.rawValue,
                "Missing fallback for \(key.rawValue)"
            )
        }
    }

    func testKeysAreUnique() {
        let values = EditorCopy.allKeys.map(\.rawValue)
        XCTAssertEqual(Set(values).count, values.count)
    }

    func testAccessibilityIdentifiersAreValidAndUnique() {
        let values = EditorAccessibility.all.map(\.rawValue)
        XCTAssertEqual(Set(values).count, values.count)

        for identifier in EditorAccessibility.all {
            XCTAssertTrue(identifier.isValid, "Invalid identifier: \(identifier.rawValue)")
            XCTAssertEqual(identifier.screen, .editor)
        }
    }

    func testNewIdentifiersDoNotCollideWithFrozenOnes() {
        let frozen = Set(AccessibilityID.all.map(\.rawValue))
        for identifier in EditorAccessibility.newIdentifiers {
            XCTAssertFalse(
                frozen.contains(identifier.rawValue),
                "Collision with frozen identifier: \(identifier.rawValue)"
            )
        }

        let current = Set(EditorAccessibility.all.map(\.rawValue))
        for identifier in EditorAccessibility.frozenIdentifiers {
            XCTAssertTrue(current.contains(identifier.rawValue))
        }
    }

    func testEveryAreaHasAtMostFiveSliders() {
        for area in EditorToolArea.allCases {
            XCTAssertLessThanOrEqual(EditorAdjustment.all(in: area).count, 5)
        }
        XCTAssertEqual(EditorAdjustment.all(in: .face).count, 2)
        XCTAssertEqual(EditorAdjustment.all(in: .body).count, 4)
        XCTAssertEqual(EditorAdjustment.all(in: .skin).count, 3)
        XCTAssertEqual(EditorAdjustment.all(in: .tone).count, 5)
    }

    func testAdjustmentRangesAndClamping() {
        var adjustments = ManualAdjustments()

        EditorAdjustment.faceSlim.set(2.0, in: &adjustments)
        XCTAssertEqual(adjustments.faceSlim, 1.0)

        EditorAdjustment.faceSlim.set(-1.0, in: &adjustments)
        XCTAssertEqual(adjustments.faceSlim, 0.0)

        EditorAdjustment.exposure.set(-2.0, in: &adjustments)
        XCTAssertEqual(adjustments.exposure, -1.0)

        EditorAdjustment.legLength.set(2.0, in: &adjustments)
        XCTAssertEqual(adjustments.legLength, 1.15)

        XCTAssertEqual(EditorAdjustment.legLength.defaultValue, 1.0)
        XCTAssertEqual(EditorAdjustment.faceSlim.defaultValue, 0.0)
    }

    func testAdjustmentAccessibilityIDsMatchFrozenContract() {
        XCTAssertEqual(
            EditorAdjustment.faceSlim.accessibilityID.rawValue,
            "editor.faceSlimSlider"
        )
        XCTAssertEqual(
            EditorAdjustment.jaw.accessibilityID.rawValue,
            "editor.jawSlider"
        )
        XCTAssertEqual(
            EditorAdjustment.smoothing.accessibilityID.rawValue,
            "editor.smoothingSlider"
        )
        XCTAssertEqual(
            EditorAdjustment.arm.accessibilityID.rawValue,
            "editor.armSlider"
        )
    }

    func testEditStateClampsStrengthAndBlemishPoints() {
        let state = EditorEditState(strength: 5)
        XCTAssertEqual(state.strength, 1.5)

        var mutable = EditorEditState()
        XCTAssertTrue(
            mutable.addBlemishPoint(NormalizedPoint(x: 0.4, y: 0.4), radius: 0.5)
        )
        XCTAssertEqual(mutable.blemishPoints[0].radius, 0.08)
        XCTAssertFalse(
            mutable.addBlemishPoint(NormalizedPoint(x: 0.401, y: 0.401), radius: 0.02)
        )
    }
}
