import XCTest
import StyleToneUI

final class LocalizationKeyTests: XCTestCase {
    func testAllCatalogKeysAreValidAndUnique() {
        for key in L10n.allKeys {
            XCTAssertTrue(key.isValid, "Invalid key: \(key.rawValue)")
            XCTAssertNotNil(key.prefix, "Unknown prefix: \(key.rawValue)")
        }
        let values = L10n.allKeys.map(\.rawValue)
        XCTAssertEqual(Set(values).count, values.count)
    }

    func testContractPrefixesAreSupported() {
        let required: Set<LocalizationPrefix> = [
            .onboarding,
            .pairing,
            .calibration,
            .editor,
            .paywall,
            .settings,
            .error,
        ]
        for prefix in required {
            XCTAssertTrue(LocalizationPrefix.allCases.contains(prefix))
            XCTAssertTrue(LocalizationKey("\(prefix.rawValue).title").isValid)
        }
    }

    func testShellAndCommonPrefixesAreSupported() {
        XCTAssertTrue(LocalizationKey("shell.tab.editor").isValid)
        XCTAssertTrue(LocalizationKey("common.closeButton").isValid)
    }

    func testNestedKeysAreValid() {
        XCTAssertTrue(L10n.calibrationStyleCardTitle.isValid)
        XCTAssertTrue(L10n.editorSectionFaceNote.isValid)
        XCTAssertTrue(L10n.exportPreviewTitle.isValid)
    }

    func testMalformedKeysAreRejected() {
        let malformed = [
            "",
            "editor",
            "unknown.title",
            "editor.",
            "editor..title",
            "editor.Two Words",
            "editor.title.with space",
            "Editor.title",
        ]
        for rawValue in malformed {
            XCTAssertFalse(LocalizationKey(rawValue).isValid, "Should reject \(rawValue)")
        }
    }

    func testPrefixLookup() {
        XCTAssertEqual(LocalizationPrefix.of("editor.faceSlim"), .editor)
        XCTAssertEqual(LocalizationPrefix.of("settings.privacyNote"), .settings)
        XCTAssertNil(LocalizationPrefix.of("unknown.key"))
        XCTAssertNil(LocalizationPrefix.of("editor"))
    }

    func testResolveUsesFallbackWithoutStringCatalog() {
        XCTAssertEqual(
            L10n.resolve(L10n.editorTitle, fallback: "Editor"),
            "Editor"
        )
        XCTAssertEqual(
            L10n.resolve(L10n.paywallSubscribeButton, fallback: "Subscribe"),
            "Subscribe"
        )
    }

    func testStringLiteralConformance() {
        let key: LocalizationKey = "editor.faceSlim"
        XCTAssertEqual(key.rawValue, "editor.faceSlim")
        XCTAssertTrue(key.isValid)
    }
}
