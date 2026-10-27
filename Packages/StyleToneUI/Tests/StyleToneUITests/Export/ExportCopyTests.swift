import StyleToneCore
import StyleToneUI
import XCTest

/// Localization keys, fallbacks and presentation helpers owned by WP-19.
final class ExportCopyTests: XCTestCase {
    func testCatalogKeysAreValidUniqueAndPrefixed() {
        XCTAssertGreaterThanOrEqual(ExportCopy.all.count, 60)

        for text in ExportCopy.all {
            XCTAssertTrue(
                text.key.isValid,
                "invalid localization key: \(text.key.rawValue)"
            )
            let prefix = text.key.prefix
            XCTAssertTrue(
                prefix == .editor || prefix == .error || prefix == .common,
                "export copy must stay under editor.*/error.*/common.*: \(text.key.rawValue)"
            )
            XCTAssertFalse(text.fallback.isEmpty)
            XCTAssertNotEqual(text.fallback, text.key.rawValue)
        }

        let keys = ExportCopy.all.map(\.key.rawValue)
        XCTAssertEqual(Set(keys).count, keys.count, "duplicate localization key")
    }

    func testResolvedCopyNeverReturnsTheKey() {
        for text in ExportCopy.all {
            XCTAssertFalse(text.text.isEmpty)
            XCTAssertNotEqual(text.text, text.key.rawValue)
        }
    }

    func testFailureCopyCoversEveryKind() {
        for kind in ExportFailure.Kind.allCases {
            let title = ExportCopy.failureTitle(kind)
            let message = ExportCopy.failureMessage(kind)
            XCTAssertTrue(title.key.isValid)
            XCTAssertTrue(message.key.isValid)
            XCTAssertFalse(title.text.isEmpty)
            XCTAssertFalse(message.text.isEmpty)
        }
    }

    func testRecoveryCopyCoversEveryRecovery() {
        for recovery in ExportFailure.Recovery.allCases {
            let text = ExportCopy.recoveryTitle(recovery)
            XCTAssertTrue(text.key.isValid)
            XCTAssertFalse(text.text.isEmpty)
        }
    }

    func testProgressCopyCoversEveryStage() {
        for stage in ExportStage.allCases {
            let text = ExportCopy.progressText(stage)
            XCTAssertTrue(text.key.isValid)
            XCTAssertFalse(text.text.isEmpty)
        }
    }

    func testFormatAndQualityTitles() {
        XCTAssertEqual(ExportCopy.formatTitle(.heic).text, "HEIC")
        XCTAssertEqual(ExportCopy.formatTitle(.jpeg).text, "JPEG")
        XCTAssertEqual(ExportCopy.qualityTitle(.high).text, "High")
        XCTAssertEqual(ExportCopy.qualityTitle(.standard).text, "Standard")
        XCTAssertEqual(ExportCopy.qualityTitle(.maximum).text, "Maximum")
        XCTAssertEqual(
            ExportCopy.qualityTitle(ExportQuality(id: "custom", value: 0.5)).text,
            "High"
        )
    }

    func testQuotaCopySingularPluralUnlimitedAndExhausted() {
        XCTAssertEqual(ExportCopy.quotaText(remaining: 1), "1 free export left")
        XCTAssertEqual(ExportCopy.quotaText(remaining: 3), "3 free exports left")
        XCTAssertEqual(ExportCopy.quotaText(remaining: 0), "0 free exports left")
        XCTAssertEqual(ExportCopy.quotaUnlimited.text, "Unlimited exports")
        XCTAssertEqual(ExportCopy.quotaExhausted.text, "Free exports used")
    }

    func testMetadataFormatting() {
        XCTAssertEqual(
            ExportCopy.pixelSizeText(PixelSize(width: 4_032, height: 3_024)),
            "4032 × 3024"
        )
        XCTAssertEqual(ExportCopy.megapixelsText(12.192768), "12.2 MP")
        XCTAssertEqual(ExportCopy.fileSizeText(bytes: 4_200_000), "4.2 MB")
        XCTAssertEqual(
            ExportCopy.diagnosticText("ST-EXPORT-PERMISSION"),
            "Support code: ST-EXPORT-PERMISSION"
        )
    }

    func testImageCopyMentionsFullResolutionAndAddOnlyBehaviour() {
        let combined = [
            ExportCopy.subtitle.text,
            ExportCopy.libraryAddOnlyNote.text,
            ExportCopy.privacyNote.text,
        ].joined(separator: " ").lowercased()
        XCTAssertTrue(combined.contains("full resolution"))
        XCTAssertTrue(combined.contains("only adds"))
        XCTAssertTrue(combined.contains("never reads"))
        XCTAssertTrue(combined.contains("nothing is uploaded"))
    }
}
