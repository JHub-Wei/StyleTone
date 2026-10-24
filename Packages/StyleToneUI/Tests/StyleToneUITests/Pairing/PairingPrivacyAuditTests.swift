import Foundation
import XCTest

/// Static privacy guard for the pairing module.
///
/// The screen must never grow a network path, a shared-container copy, a photo
/// authorization request or a pixel write. Scanning the sources keeps the
/// contract checkable on macOS, where the iOS picker cannot run.
final class PairingPrivacyAuditTests: XCTestCase {
    func testSourcesHaveNoNetworkingSharedContainerOrAuthorizationRequests() throws {
        let directory = try sourceDirectory()
        let files = try swiftFiles(in: directory)
        XCTAssertGreaterThanOrEqual(files.count, 15, "unexpectedly few pairing sources")

        let forbidden = [
            "URLSession",
            "URLRequest",
            "http://",
            "https://",
            "containerURL(forSecurityApplicationGroupIdentifier",
            "applicationGroups",
            "requestAuthorization",
            "PHPhotoLibrary",
            "import Vision",
            "import CoreImage",
            "import Metal",
            "CIImage",
            "os_log",
            "Logger(",
            "print(",
            "jpegData",
            "pngData",
            "ImageWriter",
            "uploadTask",
            "NSPhotoLibraryUsageDescription",
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

    func testSessionMetadataFilesNeverReferencePixels() throws {
        let directory = try sourceDirectory()
        let names = [
            "PairingSessionSnapshot.swift",
            "PairingSessionStore.swift",
        ]
        let forbidden = ["ImageAsset", "CGImage", "CIImage", "jpegData", "pngData", "base64"]
        for name in names {
            let contents = try String(
                contentsOf: directory.appendingPathComponent(name),
                encoding: .utf8
            )
            for token in forbidden {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(name) must stay metadata-only but contains '\(token)'"
                )
            }
        }
    }

    func testPickerUsesPHPickerWithoutAuthorization() throws {
        let directory = try sourceDirectory()
        let contents = try String(
            contentsOf: directory.appendingPathComponent("PairingPHPicker.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(contents.contains("PHPickerViewController"))
        XCTAssertTrue(contents.contains("PHPickerConfiguration"))
        XCTAssertFalse(contents.contains("requestAuthorization"))
        XCTAssertFalse(contents.contains("PHPhotoLibrary"))
        XCTAssertTrue(contents.contains("canImport(PhotosUI)"))
    }

    func testNoImageBytesAreWrittenToDisk() throws {
        let directory = try sourceDirectory()
        let writes = try swiftFiles(in: directory).filter { file in
            let contents = try? String(contentsOf: file, encoding: .utf8)
            return contents?.contains("Data(contentsOf:") == true
        }
        // Reading is allowed only in the metadata store; nothing else reads or
        // writes pixels behind the UI's back.
        for file in writes {
            XCTAssertEqual(
                file.lastPathComponent,
                "PairingSessionStore.swift",
                "unexpected disk read in \(file.lastPathComponent)"
            )
        }
    }

    // MARK: - Helpers

    private func sourceDirectory() throws -> URL {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        // Pairing -> StyleToneUITests -> Tests -> StyleToneUI
        let packageRoot = testDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = packageRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("StyleToneUI", isDirectory: true)
            .appendingPathComponent("Pairing", isDirectory: true)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: directory.path),
            "pairing source directory not found"
        )
        return directory
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
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
}
