import StyleToneUI
import XCTest

final class A6LocalizationTests: XCTestCase {
    func testAppProvidesSimplifiedChineseLocalization() {
        XCTAssertTrue(Bundle.main.localizations.contains("zh-Hans"))

        let pairing = L10n.resolve(L10n.pairingTitle, fallback: "Pairing")
        XCTAssertNotEqual(pairing, "Pairing")
        XCTAssertTrue(pairing.contains("配对"), "pairing.title should be Chinese, got \(pairing)")

        let settings = L10n.resolve(L10n.settingsTitle, fallback: "Settings")
        XCTAssertNotEqual(settings, "Settings")
        XCTAssertTrue(settings.contains("设置"), "settings.title should be Chinese, got \(settings)")
    }
}
