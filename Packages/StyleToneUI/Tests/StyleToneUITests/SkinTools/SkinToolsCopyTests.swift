import Foundation
import StyleToneCore
import XCTest
@testable import StyleToneUI

final class SkinToolsCopyTests: XCTestCase {
    func testEveryCopyKeyUsesTheEditorPrefixAndIsValid() {
        XCTAssertFalse(SkinToolsCopy.allKeys.isEmpty)
        for key in SkinToolsCopy.allKeys {
            XCTAssertEqual(key.prefix, LocalizationPrefix.editor, "Unexpected prefix for \(key.rawValue)")
            XCTAssertTrue(key.isValid, "Invalid localization key: \(key.rawValue)")
        }
    }

    func testEveryCopyKeyHasANonEmptyFallback() {
        for key in SkinToolsCopy.allKeys {
            let fallback = SkinToolsCopy.fallback(for: key)
            XCTAssertNotNil(fallback, "Missing fallback for \(key.rawValue)")
            XCTAssertFalse(fallback?.isEmpty ?? true, "Empty fallback for \(key.rawValue)")
        }
    }

    func testFrozenSmoothingCopyIsReused() {
        XCTAssertEqual(SkinToolsCopy.smoothing, L10n.editorSmoothing)
        XCTAssertEqual(SkinToolsCopy.sectionTitle, L10n.editorSectionSkin)
        XCTAssertEqual(SkinToolsCopy.sectionNote, L10n.editorSectionSkinNote)
    }

    func testEveryFailureKindAndNoticeHasCopy() {
        for kind in SkinToolsFailure.Kind.allCases {
            let key = SkinToolsCopy.errorKey(for: kind)
            XCTAssertTrue(key.isValid)
            XCTAssertFalse(SkinToolsCopy.text(key).isEmpty)
        }
        for notice in SkinToolsNotice.allCases {
            let key = SkinToolsCopy.noticeKey(for: notice)
            XCTAssertTrue(key.isValid)
            XCTAssertFalse(SkinToolsCopy.text(key).isEmpty)
        }
        for reason in SkinToolsUnavailableReason.allCases {
            let key = SkinToolsCopy.unavailableKey(for: reason)
            XCTAssertTrue(key.isValid)
            XCTAssertFalse(SkinToolsCopy.text(key).isEmpty)
        }
    }

    func testNoticeAndFailureCopyIsSpecific() {
        XCTAssertNotEqual(
            SkinToolsCopy.fallback(for: SkinToolsCopy.errorRetouch),
            SkinToolsCopy.fallback(for: SkinToolsCopy.errorBlemish)
        )
        XCTAssertNotEqual(
            SkinToolsCopy.fallback(for: SkinToolsCopy.errorBlemish),
            SkinToolsCopy.fallback(for: SkinToolsCopy.errorUndo)
        )
        XCTAssertEqual(
            SkinToolsCopy.fallback(for: SkinToolsCopy.noticeCancelled),
            "Rendering cancelled. Your last result is unchanged."
        )
    }

    func testFormattingUsesPositionalArguments() {
        let count = SkinToolsCopy.format(SkinToolsCopy.blemishCount, 3)
        XCTAssertEqual(count, "3 marks")

        let zoom = SkinToolsCopy.format(SkinToolsCopy.zoomValue, 2)
        XCTAssertEqual(zoom, "2×")

        let value = SkinToolsCopy.format(SkinToolsCopy.canvasValue, 4, 3)
        XCTAssertEqual(value, "4 marks, 3× zoom")
    }

    func testCopyHasNoHardcodedCJKIdeographs() {
        for key in SkinToolsCopy.allKeys {
            let text = SkinToolsCopy.text(key)
            XCTAssertFalse(
                containsCJK(text),
                "Hardcoded CJK text is not allowed: \(key.rawValue)"
            )
        }
    }

    func testAccessibilityIdentifiersAreEditorScopedUniqueAndValid() {
        let identifiers = SkinToolsAccessibilityID.all
        XCTAssertFalse(identifiers.isEmpty)

        for identifier in identifiers {
            XCTAssertEqual(
                identifier.screen,
                .editor,
                "Unexpected screen for \(identifier.rawValue)"
            )
            XCTAssertTrue(
                identifier.isValid,
                "Invalid accessibility identifier: \(identifier.rawValue)"
            )
        }

        let rawValues = identifiers.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count)

        let frozen = Set(AccessibilityID.all.map(\.rawValue))
        let shared = Set(rawValues).intersection(frozen)
        XCTAssertEqual(shared, Set([SkinToolsAccessibilityID.smoothingSlider.rawValue]))
    }

    func testAccessibilityIdentifiersReuseTheFrozenSmoothingID() {
        XCTAssertEqual(
            SkinToolsAccessibilityID.smoothingSlider,
            AccessibilityID.editorSmoothingSlider
        )
        XCTAssertEqual(
            SkinToolsAccessibilityID.smoothingSlider.rawValue,
            "editor.smoothingSlider"
        )
        XCTAssertEqual(
            SkinToolsAccessibilityID.evennessSlider.rawValue,
            "editor.evennessSlider"
        )
        XCTAssertEqual(
            SkinToolsAccessibilityID.blemishCanvas.rawValue,
            "editor.blemishCanvas"
        )
        XCTAssertEqual(
            SkinToolsAccessibilityID.blemishUndoButton.rawValue,
            "editor.blemishUndoButton"
        )
        XCTAssertEqual(
            SkinToolsAccessibilityID.unavailable.rawValue,
            "editor.skinToolsUnavailable"
        )
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}
