import Foundation
import XCTest

/// Static privacy guard for the export slice.
///
/// The flow is allowed to use PhotoKit for add-only saves, but it must never
/// read the library, open a network path, encode image bytes itself or log
/// paths. These checks run on macOS where the iOS photo library is unavailable.
final class ExportPrivacyAuditTests: XCTestCase {
    func testExportSourcesHaveNoNetworkingReadOrLoggingPaths() throws {
        let files = try swiftFiles(in: sourceDirectory())
        XCTAssertGreaterThanOrEqual(files.count, 10, "unexpectedly few export sources")

        let forbidden = [
            "URLSession",
            "URLRequest",
            "CFNetwork",
            "http://",
            "https://",
            "PHAsset.fetch",
            "fetchAssets",
            "PHImageManager",
            "readWrite",
            "import Vision",
            "import CoreImage",
            "import Metal",
            "CIImage",
            "os_log",
            "os.Logger",
            "Logger(subsystem",
            "print(",
            "lastPathComponent",
            "absoluteString",
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

    func testPhotoKitUseIsAddOnlyAndCreationOnly() throws {
        let source = try sourceDirectory()
        let contents = try String(
            contentsOf: source.appendingPathComponent("ExportPhotoLibrary.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(contents.contains("PHAssetCreationRequest"))
        XCTAssertTrue(contents.contains(".addOnly"))
        XCTAssertTrue(contents.contains("NSPhotoLibraryAddUsageDescription"))
        XCTAssertFalse(contents.contains("readWrite"))
        XCTAssertFalse(contents.contains("fetchAssets"))
        XCTAssertFalse(contents.contains("PHImageManager"))
        XCTAssertFalse(contents.contains("PHAsset.fetch"))
    }

    func testUIWritesNoImageBytesItself() throws {
        let files = try swiftFiles(in: sourceDirectory())
        let forbidden = [
            "Data(contentsOf:",
            ".write(to:",
            "CGImageDestination",
            "ImageWriter",
            "jpegData",
            "pngData",
            "base64",
        ]

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(file.lastPathComponent) must not encode pixels ('\(token)')"
                )
            }
        }
    }

    func testTemporaryFilesAreCleanedOnEveryTerminalPath() throws {
        let source = try sourceDirectory()
        let viewModel = try String(
            contentsOf: source.appendingPathComponent("ExportViewModel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(viewModel.contains("cleanupStagedFile()"))
        XCTAssertTrue(viewModel.contains("removeStaleFiles(now: now)"))

        let fileStore = try String(
            contentsOf: source.appendingPathComponent("ExportTemporaryFiles.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(fileStore.contains("FileImageExporter.defaultDirectoryName"))
        XCTAssertTrue(fileStore.contains("prepareDirectoryForExport"))
        XCTAssertTrue(fileStore.contains(".protectionKey"))
        XCTAssertTrue(fileStore.contains("FileProtectionType.complete"))

        let files = try swiftFiles(in: source)
        let cleanupCallSites = files.reduce(0) { count, file in
            let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            return count + contents.components(separatedBy: "cleanupStagedFile()").count - 1
        }
        XCTAssertGreaterThanOrEqual(cleanupCallSites, 6)
    }

    func testInfoPlistFragmentDeclaresAddOnlyUsage() throws {
        let packageRoot = try packageRoot()
        let fragment = packageRoot
            .appendingPathComponent("Export", isDirectory: true)
            .appendingPathComponent("Integration", isDirectory: true)
            .appendingPathComponent("Info.plist.fragment")

        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: fragment.path),
            "Info.plist fragment missing"
        )
        let contents = try String(contentsOf: fragment, encoding: .utf8)
        XCTAssertTrue(contents.contains("NSPhotoLibraryAddUsageDescription"))
        XCTAssertFalse(contents.contains("<key>NSPhotoLibraryUsageDescription</key>"))
    }

    func testPrivacyManifestDeclaresFileTimestampReason() throws {
        let fragment = try packageRoot()
            .appendingPathComponent("Export", isDirectory: true)
            .appendingPathComponent("Integration", isDirectory: true)
            .appendingPathComponent("PrivacyInfo.xcprivacy.fragment")

        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: fragment.path),
            "privacy manifest fragment missing"
        )
        let contents = try String(contentsOf: fragment, encoding: .utf8)
        XCTAssertTrue(contents.contains("NSPrivacyAccessedAPICategoryFileTimestamp"))
        XCTAssertTrue(contents.contains("C617.1"))
    }

    // MARK: - Helpers

    private func sourceDirectory() throws -> URL {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        // Export -> StyleToneUITests -> Tests -> StyleToneUI
        let packageRoot = testDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = packageRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("StyleToneUI", isDirectory: true)
            .appendingPathComponent("Export", isDirectory: true)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: directory.path),
            "export source directory not found"
        )
        return directory
    }

    private func packageRoot() throws -> URL {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = testDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.path),
            "package root not found"
        )
        return root
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
