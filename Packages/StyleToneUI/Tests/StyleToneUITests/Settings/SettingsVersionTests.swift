import Foundation
import StyleToneUI
import XCTest

final class SettingsVersionTests: XCTestCase {
    func testDisplayStrings() {
        let version = SettingsTestFactory.version
        XCTAssertEqual(version.displayVersion, "1.2.3 (45)")
        XCTAssertEqual(version.systemDescription, "iOS 17.4")
        XCTAssertEqual(version.platformToken, "iOS17")
    }

    func testSanitizerKeepsOnlyBoundedAscii() {
        let sanitized = SettingsVersionInfo.sanitizedToken("1.2 beta/../..", maxLength: 24)
        XCTAssertFalse(sanitized.contains(" "))
        XCTAssertFalse(sanitized.contains("/"))
        XCTAssertTrue(sanitized.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (48...57).contains(value)
                || (65...90).contains(value)
                || (97...122).contains(value)
                || value == 46
                || value == 45
        })
        XCTAssertLessThanOrEqual(sanitized.count, 24)
        XCTAssertEqual(SettingsVersionInfo.sanitizedToken("", maxLength: 8), "0")
        XCTAssertEqual(String(SettingsVersionInfo.sanitizedToken(String(repeating: "a", count: 50))).count, 20)
    }

    func testStaticProviderReturnsTheInjectedValue() {
        let version = SettingsVersionInfo(
            marketingVersion: "9.9.9",
            buildNumber: "999",
            platform: "iOS",
            osVersion: "18.0"
        )
        let provider = StaticSettingsVersionProvider(version)
        XCTAssertEqual(provider.currentVersion(), version)
    }

    func testBundleProviderFallsBackAndKeepsPlatformCurrent() {
        let bundle = Bundle(for: Self.self)
        let provider = BundleSettingsVersionProvider(bundle: bundle)
        let version = provider.currentVersion()
        XCTAssertFalse(version.marketingVersion.isEmpty)
        XCTAssertFalse(version.buildNumber.isEmpty)
        XCTAssertEqual(version.platform, SettingsVersionInfo.currentPlatform)
        XCTAssertFalse(version.osVersion.isEmpty)
    }
}

final class SettingsSupportTests: XCTestCase {
    func testPlaceholderEmailAndMailtoURL() throws {
        let support = SettingsSupportInfo.placeholder
        XCTAssertTrue(support.hasValidEmail)
        XCTAssertFalse(support.hasPrivacyPolicy)

        let url = try XCTUnwrap(support.mailtoURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, support.email)
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:"))
        XCTAssertFalse(url.absoluteString.contains("http"))
    }

    func testInvalidEmailsDoNotProduceALink() {
        let invalid = [
            "",
            "support",
            "support@",
            "@styletone.app",
            "support@styletone",
            "support@styletone..app",
            "sup port@styletone.app",
            "support @styletone.app",
        ]
        for email in invalid {
            let support = SettingsSupportInfo(email: email)
            XCTAssertFalse(support.hasValidEmail, "should reject \(email)")
            XCTAssertNil(support.mailtoURL, "should not link \(email)")
        }
    }

    func testPlusAddressingAndConfiguredPolicyAreSupported() throws {
        let policyURL = URL(fileURLWithPath: "/privacy")
        let support = SettingsSupportInfo(
            email: "support+ios@styletone.app",
            privacyPolicyURL: policyURL
        )
        XCTAssertTrue(support.hasValidEmail)
        XCTAssertEqual(support.privacyPolicyURL, policyURL)
        XCTAssertTrue(support.hasPrivacyPolicy)
        XCTAssertNotNil(support.mailtoURL)
    }
}
