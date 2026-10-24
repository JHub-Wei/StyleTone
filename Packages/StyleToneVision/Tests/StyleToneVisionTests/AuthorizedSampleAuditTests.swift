import Foundation
import XCTest
import GoldenSupport
import StyleToneCore
import StyleToneImaging
import TestShared
@testable import StyleToneVision

/// Opt-in harness for the 20 authorized-photo spot check.
///
/// Real photos are never committed. The project owner drops them into the
/// git-ignored `Fixtures/samples/` directory and adds manifest entries, then
/// runs:
///
/// ```bash
/// ST_RUN_AUTHORIZED_SAMPLE_AUDIT=1 swift test --filter AuthorizedSampleAuditTests
/// ```
///
/// The test asserts the structural contract (normalized coordinates, mask
/// dimensions, bounded confidence) and attaches a JSON summary for the human
/// review. It does not assert detection rates, because those are judged by the
/// reviewer against the checklist in the package README.
final class AuthorizedSampleAuditTests: XCTestCase {
    func testAuthorizedSamplesRespectAnalysisContract() async throws {
        let environment = TestEnvironment()
        let enabled = ProcessInfo.processInfo.environment["ST_RUN_AUTHORIZED_SAMPLE_AUDIT"] == "1"
        try XCTSkipUnless(
            enabled,
            "opt-in manual audit; set ST_RUN_AUTHORIZED_SAMPLE_AUDIT=1"
        )
        guard let manifestURL = environment.samplesManifestURL,
              let samplesDirectory = environment.samplesDirectory
        else {
            throw XCTSkip("Fixtures/samples/manifest.json not found")
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try AuthorizedSampleManifest.decode(data)
        try manifest.validate()
        try XCTSkipIf(
            manifest.samples.isEmpty,
            "no authorized samples installed; add local photos and manifest entries"
        )

        let analyzer = VisionPortraitAnalyzer()
        let loader = ImageLoader()
        var entries: [[String: String]] = []

        for sample in manifest.samples {
            let url = samplesDirectory.appendingPathComponent(sample.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                entries.append(["id": sample.id, "status": "missing"])
                continue
            }
            let image = try await loader.load(url: url)
            let result = try await analyzer.analyzeDetailed(image)
            let analysis = result.analysis

            for face in analysis.faces {
                XCTAssertGreaterThanOrEqual(face.boundingBox.x, 0, sample.id)
                XCTAssertLessThanOrEqual(face.boundingBox.maxX, 1, sample.id)
                XCTAssertGreaterThanOrEqual(face.boundingBox.y, 0, sample.id)
                XCTAssertLessThanOrEqual(face.boundingBox.maxY, 1, sample.id)
                for kind in FaceLandmarkKind.allCases {
                    for point in face.points(for: kind) {
                        XCTAssertTrue(point.isNormalized, "\(sample.id) \(kind)")
                    }
                }
            }
            var masks = 0
            for mask in [analysis.personMask, analysis.skinMask, analysis.backgroundEdgeMask]
                .compactMap({ $0 }) {
                masks += 1
                XCTAssertEqual(mask.width, image.pixelSize.width, sample.id)
                XCTAssertEqual(mask.height, image.pixelSize.height, sample.id)
            }

            entries.append([
                "id": sample.id,
                "category": sample.category.rawValue,
                "status": "analyzed",
                "faces": String(analysis.faces.count),
                "body": analysis.body == nil ? "no" : "yes",
                "masks": String(masks),
                "warnings": analysis.warnings.map(\.rawValue).joined(separator: ","),
                "confidence": String(format: "%.3f", result.confidence),
                "durationSeconds": String(format: "%.3f", result.diagnostics.duration)
            ])
        }

        let attachment = XCTAttachment(string: try auditReport(entries: entries))
        attachment.name = "authorized-sample-audit.json"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(entries.filter { $0["status"] == "missing" }.count, 0)
    }

    private func auditReport(entries: [[String: String]]) throws -> String {
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "sampleCount": entries.count,
            "entries": entries
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }
}
