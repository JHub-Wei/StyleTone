import Foundation
import XCTest

/// Static audit of the unified error surface.
///
/// It complements the runtime mapping tests: it keeps the module free of
/// platform APIs, print logging, localized error descriptions and hardcoded
/// Chinese, all of which could leak user data or bypass the copy catalog.
final class ErrorPrivacyAuditTests: XCTestCase {
    private var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // EdgeCases
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent(
                "Packages/StyleToneUI/Sources/StyleToneUI/ErrorStates",
                isDirectory: true
            )
    }

    func testErrorSurfaceSourceAvoidsPIIAndPlatformAPIs() throws {
        let directory = sourceDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("ErrorStates sources are not available at \(directory.path)")
        }

        let files = try FileManager.default
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no ErrorStates sources found")

        let forbidden = [
            "print(",
            "debugPrint(",
            "NSLog(",
            "os_log",
            "localizedDescription",
            "FileManager",
            "UIDevice",
            "ProcessInfo",
            "import UIKit",
            "import Photos",
            "import StoreKit",
            "import AppKit",
            "http://",
            "https://",
            "String(describing:",
            "dump(",
            "Task.detached",
        ]

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for snippet in forbidden {
                XCTAssertFalse(
                    source.contains(snippet),
                    "\(file.lastPathComponent) contains forbidden \(snippet)"
                )
            }
            XCTAssertFalse(
                containsCJK(source),
                "\(file.lastPathComponent) contains hardcoded Chinese"
            )
        }
    }

    func testPresenterNeverLogsCopyWithUserText() throws {
        let directory = sourceDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("ErrorStates sources are not available")
        }

        let presenterURL = directory.appendingPathComponent("ErrorPresenter.swift")
        let source = try String(contentsOf: presenterURL, encoding: .utf8)

        XCTAssertFalse(source.contains("\"message\":"))
        XCTAssertFalse(source.contains("\"text\":"))
        XCTAssertFalse(source.contains("state.message.text"))
        XCTAssertFalse(source.contains("state.title.text"))
        XCTAssertTrue(source.contains("\"code\":"))
        XCTAssertTrue(source.contains("\"source\":"))
    }

    func testEverySourceFileUsesTheSharedCopyCatalog() throws {
        let directory = sourceDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("ErrorStates sources are not available")
        }

        let viewsURL = directory.appendingPathComponent("ErrorStateViews.swift")
        let source = try String(contentsOf: viewsURL, encoding: .utf8)
        XCTAssertTrue(source.contains("state.title.text"))
        XCTAssertTrue(source.contains("state.message.text"))
        XCTAssertTrue(source.contains("state.diagnosticText"))
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x2E80...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0xFF00...0xFFEF).contains(scalar.value)
        }
    }
}
