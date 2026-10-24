import Foundation
import XCTest

/// Guards the WP-05 privacy contract: no networking, no logging of image data
/// and no face-identity APIs inside the Vision module.
final class PrivacySourceAuditTests: XCTestCase {
    func testSourcesDoNotContainNetworkingOrIdentityAPIs() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let packageRoot = testDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceDirectory = packageRoot
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("StyleToneVision", isDirectory: true)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: sourceDirectory.path),
            "source directory not found"
        )

        let forbidden = [
            "URLSession",
            "import Network",
            "http://",
            "https://",
            "os_log",
            "Logger(",
            "VNClassifyImageRequest",
            "faceTemplate"
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
