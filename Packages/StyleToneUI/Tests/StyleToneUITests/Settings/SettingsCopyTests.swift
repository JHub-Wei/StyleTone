import Foundation
import StyleToneUI
import XCTest

/// Copy is the product's privacy and subscription contract in prose. These
/// tests keep every fallback key legal, free of placeholders and accurate.
final class SettingsCopyTests: XCTestCase {
    func testEveryKeyIsValidUniqueAndSettingsScoped() {
        var seen = Set<String>()
        for copy in SettingsCopy.all {
            XCTAssertTrue(copy.key.isValid, "invalid localization key: \(copy.key.rawValue)")
            XCTAssertTrue(copy.isSettingsKey, "unexpected prefix: \(copy.key.rawValue)")
            XCTAssertTrue(copy.key.rawValue.hasPrefix("settings.")
                || copy.key.rawValue.hasPrefix("error.settings."),
                "settings copy must use settings. or error.settings.: \(copy.key.rawValue)")
            XCTAssertTrue(seen.insert(copy.key.rawValue).inserted, "duplicate key: \(copy.key.rawValue)")
            XCTAssertFalse(copy.fallback.isEmpty, "empty fallback: \(copy.key.rawValue)")
        }
        XCTAssertGreaterThanOrEqual(SettingsCopy.all.count, 100)
    }

    func testNoPlaceholdersOrChineseLiterals() {
        let forbidden = ["TODO", "FIXME", "TBD", "lorem", "\u{5360}\u{4F4D}", "\u{4E2D}\u{6587}"]
        for copy in SettingsCopy.all {
            for token in forbidden {
                XCTAssertFalse(
                    copy.fallback.localizedCaseInsensitiveContains(token),
                    "\(copy.key.rawValue) contains placeholder '\(token)'"
                )
            }
            XCTAssertFalse(
                containsCJK(copy.fallback),
                "\(copy.key.rawValue) contains a CJK literal; copy belongs in the catalog"
            )
        }
    }

    func testPrivacyCopyStatesLocalProcessingAndNoUpload() {
        let body = SettingsCopy.privacyBody.fallback.lowercased()
        XCTAssertTrue(body.contains("no account"))
        XCTAssertTrue(body.contains("no upload"))
        XCTAssertTrue(body.contains("locally"))

        let collected = SettingsCopy.privacyCollectBody.fallback.lowercased()
        XCTAssertTrue(collected.contains("off by default"))
        XCTAssertTrue(collected.contains("never records photos"))
        XCTAssertTrue(collected.contains("file names"))
        XCTAssertTrue(collected.contains("account information"))

        let leaves = SettingsCopy.privacyLeavesNothing.fallback.lowercased()
        XCTAssertTrue(leaves.contains("does not collect or upload"))
    }

    func testSubscriptionCopyExplainsThatDeletionDoesNotCancel() {
        let body = SettingsCopy.subscriptionBody.fallback.lowercased()
        XCTAssertTrue(body.contains("apple id"))
        XCTAssertTrue(body.contains("does not cancel"))
        XCTAssertTrue(body.contains("app store account settings"))

        let keep = SettingsCopy.deleteKeepSubscription.fallback.lowercased()
        XCTAssertTrue(keep.contains("does not cancel"))

        let success = SettingsCopy.deleteSuccessBody.fallback.lowercased()
        XCTAssertTrue(success.contains("not cancelled"))
    }

    func testDeletionCopyIsExplicitAboutUndoAndRetainedData() {
        XCTAssertTrue(SettingsCopy.deleteSheetIntro.fallback.lowercased().contains("cannot be undone"))
        XCTAssertTrue(SettingsCopy.deleteFinalMessage.fallback.lowercased().contains("cannot be undone"))
        XCTAssertTrue(SettingsCopy.deleteKeepPhotos.fallback.lowercased().contains("photo library"))
        XCTAssertTrue(SettingsCopy.deleteKeepPurchase.fallback.lowercased().contains("purchase"))
        XCTAssertTrue(SettingsCopy.deleteRemoveDiagnostics.fallback.lowercased().contains("diagnostics"))
    }

    func testDiagnosticsCopyStatesOffMeansNothingIsCollected() {
        let off = SettingsCopy.diagnosticsOffNote.fallback.lowercased()
        XCTAssertTrue(off.contains("nothing is collected"))

        let on = SettingsCopy.diagnosticsOnNote.fallback.lowercased()
        XCTAssertTrue(on.contains("deletes the local log"))

        let never = SettingsCopy.diagnosticsNeverBody.fallback.lowercased()
        XCTAssertTrue(never.contains("photos"))
        XCTAssertTrue(never.contains("file names"))
        XCTAssertTrue(never.contains("location"))
        XCTAssertTrue(never.contains("account"))
    }

    func testSupportAndLicenseCopyDoNotPromiseAnAccountFlow() {
        let noAccount = SettingsCopy.privacyNoAccountNote.fallback.lowercased()
        XCTAssertTrue(noAccount.contains("no account"))
        XCTAssertTrue(noAccount.contains("no sign-in"))

        XCTAssertTrue(
            SettingsCopy.licensesThirdPartyNone.fallback.lowercased().contains("no third-party")
        )
    }

    func testNoCallToActionInvitesAnAccount() {
        let callsToAction = ["sign in", "log in", "sign up", "create account", "continue with apple"]
        for copy in SettingsCopy.all {
            let lowercased = copy.fallback.lowercased()
            for call in callsToAction {
                XCTAssertFalse(
                    lowercased.contains(call),
                    "\(copy.key.rawValue) contains account CTA '\(call)'"
                )
            }
        }
    }

    func testNoAbsoluteSecurityClaims() {
        let forbidden = ["100%", "guaranteed", "fully secure", "unhackable", "never fails", "absolutely safe"]
        for copy in SettingsCopy.all {
            let lowercased = copy.fallback.lowercased()
            for token in forbidden {
                XCTAssertFalse(
                    lowercased.contains(token),
                    "\(copy.key.rawValue) contains overclaim '\(token)'"
                )
            }
        }
    }

    func testEntriesFormattingUsesTheStoredCount() {
        XCTAssertEqual(
            SettingsCopy.entriesText(count: 3),
            "3 entries stored on this iPhone."
        )
        XCTAssertEqual(
            SettingsCopy.entriesText(count: -1),
            "0 entries stored on this iPhone."
        )
    }

    func testEveryScreenSectionHasCopy() {
        XCTAssertFalse(SettingsCopy.sectionPrivacy.fallback.isEmpty)
        XCTAssertFalse(SettingsCopy.sectionDiagnostics.fallback.isEmpty)
        XCTAssertFalse(SettingsCopy.sectionSubscription.fallback.isEmpty)
        XCTAssertFalse(SettingsCopy.sectionAbout.fallback.isEmpty)
        XCTAssertFalse(SettingsCopy.sectionSupport.fallback.isEmpty)
    }

    // MARK: - Helpers

    private func containsCJK(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x3000...0x303F).contains(value)
                || (0x3400...0x4DBF).contains(value)
                || (0x4E00...0x9FFF).contains(value)
                || (0xF900...0xFAFF).contains(value)
                || (0xFF00...0xFFEF).contains(value)
            {
                return true
            }
        }
        return false
    }
}
