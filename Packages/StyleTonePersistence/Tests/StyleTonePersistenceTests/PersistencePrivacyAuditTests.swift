import Foundation
import XCTest

/// Guards the WP-08 privacy boundary: the persistence module is local-only and
/// never handles pixels, photo-library identifiers, accounts or network APIs.
final class PersistencePrivacyAuditTests: XCTestCase {
    func testSourcesContainNoNetworkAccountOrPhotoAPIs() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let packageRoot = testDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceDirectory = packageRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("StyleTonePersistence", isDirectory: true)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: sourceDirectory.path),
            "source directory not found"
        )

        let forbidden = [
            "URLSession",
            "import Network",
            "import CloudKit",
            "CKContainer",
            "import StoreKit",
            "AuthenticationServices",
            "ASAuthorization",
            "http://",
            "https://",
            "NSLog",
            "print(",
            "CGImage",
            "CIImage",
            "ImageAsset",
            "PHPhotoLibrary",
            "UIImage",
            "DispatchQueue.main",
            "MainActor.run"
        ]
        let files = try swiftFiles(in: sourceDirectory)
        XCTAssertFalse(files.isEmpty)
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

    func testModelsStoreOnlyOpaqueMetadata() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let packageRoot = testDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelDirectory = packageRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("StyleTonePersistence", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: modelDirectory.path),
            "model directory not found"
        )

        let forbidden = [
            "imageData",
            "photoData",
            "pixelData",
            "CGImage",
            "UIImage",
            "ImageAsset",
            "PHAsset",
            "localIdentifier"
        ]
        let files = try swiftFiles(in: modelDirectory)
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(file.lastPathComponent) contains forbidden payload token '\(token)'"
                )
            }
        }
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
