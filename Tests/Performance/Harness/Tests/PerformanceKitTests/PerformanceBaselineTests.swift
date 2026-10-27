import XCTest
@testable import PerformanceKit

final class PerformanceBaselineTests: XCTestCase {
    private func entry(
        scenarioID: String = "preview.firstFrame",
        environmentID: String = "ci.macos.arm64",
        value: Double = 0.42
    ) -> PerformanceBaselineEntry {
        // preview.firstFrame regresses on p50; the helper mirrors that so the
        // round-trip and duplicate tests exercise a valid document.
        PerformanceBaselineEntry(
            scenarioID: scenarioID,
            environmentID: environmentID,
            value: value,
            unit: .seconds,
            statistic: .p50,
            sampleCount: 5,
            recordedAt: "2026-10-27T12:00:00Z",
            commit: "abcdef0",
            source: "unit test"
        )
    }

    func testRoundTripKeepsEntries() throws {
        let file = PerformanceBaselineFile(
            generatedAt: "2026-10-27T12:00:00Z",
            referenceDevice: "iPhone 13",
            entries: [entry()]
        )
        let data = try file.encoded()
        let decoded = try PerformanceBaselineFile.decode(data)
        XCTAssertEqual(decoded, file)
        XCTAssertEqual(decoded.entry(scenarioID: "preview.firstFrame", environmentID: "ci.macos.arm64")?.value, 0.42)
    }

    func testUpsertingReplacesTheSameScenarioAndEnvironment() throws {
        let file = PerformanceBaselineFile(
            generatedAt: "2026-10-27T12:00:00Z",
            referenceDevice: "iPhone 13",
            entries: [entry()]
        )
        let updated = file.upserting(entry(value: 0.38))
        XCTAssertEqual(updated.entries.count, 1)
        XCTAssertEqual(updated.entries[0].value, 0.38)
        XCTAssertEqual(updated.generatedAt, "2026-10-27T12:00:00Z")
    }

    func testDuplicateEntriesAreRejected() throws {
        let file = PerformanceBaselineFile(
            generatedAt: "2026-10-27T12:00:00Z",
            referenceDevice: "iPhone 13",
            entries: [entry(), entry()]
        )
        XCTAssertThrowsError(try file.validate()) { error in
            guard case PerformanceKitError.duplicateBaseline = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testUnknownScenarioIsRejected() throws {
        let file = PerformanceBaselineFile(
            generatedAt: "2026-10-27T12:00:00Z",
            referenceDevice: "iPhone 13",
            entries: [entry(scenarioID: "unknown.scenario")]
        )
        XCTAssertThrowsError(try file.validate())
    }

    func testUnitMismatchIsRejected() throws {
        let mismatched = PerformanceBaselineEntry(
            scenarioID: "preview.firstFrame",
            environmentID: "ci.macos.arm64",
            value: 42,
            unit: .framesPerSecond,
            sampleCount: 5,
            recordedAt: "2026-10-27T12:00:00Z",
            commit: "abcdef0",
            source: "unit test"
        )
        let file = PerformanceBaselineFile(
            generatedAt: "2026-10-27T12:00:00Z",
            referenceDevice: "iPhone 13",
            entries: [mismatched]
        )
        XCTAssertThrowsError(try file.validate())
    }

    func testUnsupportedSchemaIsRejected() throws {
        let file = PerformanceBaselineFile(
            schemaVersion: 99,
            generatedAt: "2026-10-27T12:00:00Z",
            referenceDevice: "iPhone 13",
            entries: [entry()]
        )
        XCTAssertThrowsError(try file.validate()) { error in
            guard case let PerformanceKitError.unsupportedSchemaVersion(version) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(version, 99)
        }
    }

    func testMalformedJSONIsRejected() {
        XCTAssertThrowsError(
            try PerformanceBaselineFile.decode(Data("not-json".utf8))
        )
    }

    func testNegativeValueIsRejected() throws {
        let file = PerformanceBaselineFile(
            generatedAt: "2026-10-27T12:00:00Z",
            referenceDevice: "iPhone 13",
            entries: [entry(value: -1)]
        )
        XCTAssertThrowsError(try file.validate())
    }
}
