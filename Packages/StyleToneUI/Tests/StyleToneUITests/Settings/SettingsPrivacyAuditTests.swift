import Foundation
import XCTest

/// Static privacy and architecture guards for the settings feature.
///
/// The package tests run on macOS, so the iOS screen cannot be exercised by a
/// simulator here. Scanning the sources keeps the contract checkable: no
/// network, no account SDK, no photo API, no free-form diagnostics, and no
/// deletion path that bypasses WP-08.
final class SettingsPrivacyAuditTests: XCTestCase {
    func testSourcesHaveNoNetworkingAccountOrPhotoAPIs() throws {
        let files = try swiftFiles(in: sourceDirectory())
        XCTAssertGreaterThanOrEqual(files.count, 14, "unexpectedly few settings sources")

        let forbidden = [
            "URLSession",
            "URLRequest",
            "uploadTask",
            "http://",
            "https://",
            "WebKit",
            "CloudKit",
            "CKContainer",
            "AuthenticationServices",
            "ASAuthorization",
            "SignInWithApple",
            "Firebase",
            "Amplitude",
            "Sentry",
            "PHPhotoLibrary",
            "requestAuthorization",
            "import Photos",
            "import PhotosUI",
            "import StoreKit",
            "import Vision",
            "import CoreImage",
            "import Metal",
            "ImageAsset",
            "CGImage",
            "CIImage",
            "UIImage",
            "jpegData",
            "pngData",
            "containerURL(forSecurityApplicationGroupIdentifier",
            "applicationGroups",
            "print(",
            "NSLog",
            "os_log",
            "Logger(",
        ]

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(file.lastPathComponent) contains forbidden token '\(token)'"
                )
            }
        }
    }

    func testOnlyFoundationSwiftUICoreAndPlatformKitAreImported() throws {
        let files = try swiftFiles(in: sourceDirectory())
        let allowed = Set([
            "Foundation",
            "SwiftUI",
            "Observation",
            "StyleToneCore",
            "UIKit",
            "AppKit",
        ])

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for line in contents.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                let module = String(trimmed.dropFirst("import ".count))
                XCTAssertTrue(
                    allowed.contains(module),
                    "\(file.lastPathComponent) imports unexpected module '\(module)'"
                )
            }
        }
    }

    func testDiagnosticsEventsCarryNoFreeFormText() throws {
        let file = sourceDirectory().appendingPathComponent("SettingsDiagnosticsModels.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(contents.contains("public let message"))
        XCTAssertFalse(contents.contains("public let detail"))
        XCTAssertFalse(contents.contains("public let payload"))
        XCTAssertFalse(contents.contains("public let userText"))
        XCTAssertTrue(contents.contains("public let code: String?"))
        XCTAssertTrue(contents.contains("normalizedCode"))
    }

    func testDiagnosticsWritesAreGatedByTheOptIn() throws {
        let file = sourceDirectory().appendingPathComponent("SettingsDiagnosticsService.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(contents.contains("guard enabled else { return }"))
        XCTAssertTrue(contents.contains("try await preferences.setDiagnosticsOptIn(false)"))
        XCTAssertTrue(contents.contains("try await store.clear()"))
    }

    func testDeletionUsesTheWP08ContractAndVerifiesTheResult() throws {
        let file = sourceDirectory().appendingPathComponent("SettingsLocalDataDeletion.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(contents.contains("try await profileStore.deleteAll()"))
        XCTAssertTrue(contents.contains("profileStore.loadActive()"))
        XCTAssertTrue(contents.contains("failures[.profilesAndEdits] = profileFailure"))
        XCTAssertTrue(contents.contains(".profileResidue"))
        XCTAssertTrue(contents.contains("requiresOnboarding"))
        XCTAssertTrue(contents.contains("diagnostics.deleteDiagnosticData()"))
        XCTAssertTrue(contents.contains("preferences.clearLocalPreferences()"))
    }

    func testNoHardcodedChineseInSettingsSources() throws {
        let files = try swiftFiles(in: sourceDirectory())
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                containsCJK(contents),
                "\(file.lastPathComponent) contains Chinese text; use a localization key"
            )
        }
    }

    func testEveryInteractiveIdentifierIsWiredIntoAView() throws {
        let files = try swiftFiles(in: sourceDirectory())
        var combined = ""
        for file in files {
            combined += try String(contentsOf: file, encoding: .utf8)
        }

        let wired = [
            "screen",
            "privacyButton",
            "privacyScreen",
            "privacyPolicyLink",
            "privacyNote",
            "diagnosticsSection",
            "diagnosticsToggle",
            "diagnosticsStatus",
            "diagnosticsData",
            "diagnosticsNeverData",
            "diagnosticsCode",
            "diagnosticsCodeHint",
            "diagnosticsCopyButton",
            "diagnosticsClearButton",
            "diagnosticsEntries",
            "subscriptionNote",
            "deleteDataButton",
            "deleteDataHint",
            "deleteSheet",
            "deleteCancelButton",
            "deleteContinueButton",
            "deleteBackButton",
            "deleteFinalButton",
            "deleteProgress",
            "deleteSuccess",
            "deleteStartOverButton",
            "deleteRetryButton",
            "deleteFailure",
            "licensesButton",
            "licensesScreen",
            "versionRow",
            "buildRow",
            "systemRow",
            "supportSection",
            "supportEmailLink",
            "supportCopyButton",
            "supportResponse",
            "supportPrivacyLink",
            "noAccountNote",
            "notice",
        ]

        for identifier in wired {
            XCTAssertTrue(
                combined.contains("SettingsAccessibilityID.\(identifier).rawValue"),
                "\(identifier) is not applied to a view"
            )
        }
    }

    func testNoAccountEntryExists() throws {
        let files = try swiftFiles(in: sourceDirectory())
        var combined = ""
        for file in files {
            combined += try String(contentsOf: file, encoding: .utf8)
        }

        let forbidden = [
            "Sign in",
            "Sign In",
            "Log in",
            "Log In",
            "Create account",
            "Sign up",
            "Continue with Apple",
            "LoginView",
            "SignInView",
            "AccountView",
            "AccountScreen",
        ]
        for token in forbidden {
            XCTAssertFalse(
                combined.contains(token),
                "settings must not contain an account entry ('\(token)')"
            )
        }
    }

    // MARK: - Helpers

    private func sourceDirectory() -> URL {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        // Settings -> StyleToneUITests -> Tests -> StyleToneUI
        let packageRoot = testDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("StyleToneUI", isDirectory: true)
            .appendingPathComponent("Settings", isDirectory: true)
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw SettingsAuditError.missingSources(directory.lastPathComponent)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

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

private enum SettingsAuditError: Error {
    case missingSources(String)
}
