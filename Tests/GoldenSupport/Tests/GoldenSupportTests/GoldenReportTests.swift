import XCTest
@testable import GoldenSupport
import StyleToneCore
import TestShared

final class GoldenReportTests: XCTestCase {
    private let environment = GoldenReportEnvironment(
        isCI: true,
        provider: "github-actions",
        runID: "1234567890",
        runnerOS: "macOS",
        osVersion: "Version 15.0"
    )

    func testSummaryCountsAndAppend() {
        var report = GoldenReport(suite: "wp04", environment: environment)
        XCTAssertEqual(report.summary.total, 0)
        XCTAssertTrue(report.isSuccessful)

        report.append(.fixture(name: "fixture-1", passed: true))
        report.append(.fixture(name: "fixture-2", passed: false, message: "pixels changed"))
        report.append(GoldenReportEntry(kind: .custom, name: "skipped", status: .skipped))

        XCTAssertEqual(report.summary.total, 3)
        XCTAssertEqual(report.summary.passed, 1)
        XCTAssertEqual(report.summary.failed, 1)
        XCTAssertEqual(report.summary.skipped, 1)
        XCTAssertFalse(report.isSuccessful)
    }

    func testComparisonEntryCarriesMetricsAndFailures() throws {
        let expected = try PixelBuffer(width: 4, height: 4, fill: .black)
        var actual = expected
        actual[0, 0] = RGBA8(color: .white)
        let comparison = try ImageComparator.compare(
            expected: expected,
            actual: actual,
            thresholds: .identity
        )
        let entry = GoldenReportEntry.comparison(name: "noop", report: comparison)
        XCTAssertEqual(entry.kind, .imageComparison)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.metrics["maxDeltaE00"] ?? 0, 100, accuracy: 0.5)
        XCTAssertFalse(entry.thresholdFailures.isEmpty)
    }

    func testPerformanceEntry() throws {
        let measurement = try PerformanceMeasurement(name: "export", durationsSeconds: [1, 2, 3])
        let budget = PerformanceBudget(id: "export", targetSeconds: 2, allowanceFraction: 0)
        let entry = GoldenReportEntry.performance(
            name: "export",
            measurement: measurement,
            verdict: budget.verdict(for: measurement)
        )
        XCTAssertEqual(entry.kind, .performance)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(entry.metrics["p95Seconds"] ?? 0, 3, accuracy: 1e-9)
    }

    func testJSONRoundTripRecomputesSummary() throws {
        var report = GoldenReport(
            suite: "roundtrip",
            generatedAt: "2026-01-01T00:00:00Z",
            environment: environment
        )
        report.append(.fixture(name: "a", passed: true))
        report.append(.fixture(name: "b", passed: false))
        report.summary = GoldenReportSummary(total: 99, passed: 99, failed: 0, skipped: 0)

        let data = try report.jsonData()
        let decoded = try JSONDecoder().decode(GoldenReport.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.suite, "roundtrip")
        XCTAssertEqual(decoded.entries, report.entries)
        XCTAssertEqual(decoded.summary.total, 2, "summary must be recomputed from entries")
        XCTAssertEqual(decoded.summary.failed, 1)
    }

    func testMarkdownContainsChecksAndFailures() {
        var report = GoldenReport(
            suite: "markdown",
            generatedAt: "2026-01-01T00:00:00Z",
            environment: environment
        )
        report.append(.fixture(name: "fixture-a", passed: true))
        report.append(
            GoldenReportEntry(
                kind: .imageComparison,
                name: "case|pipe",
                status: .failed,
                message: "mismatch",
                thresholdFailures: ["ssim 0.5 < 0.95"]
            )
        )

        let markdown = report.markdown()
        XCTAssertTrue(markdown.contains("# GoldenSupport report — markdown"))
        XCTAssertTrue(markdown.contains("github-actions"))
        XCTAssertTrue(markdown.contains("case\\|pipe"), "pipes must be escaped")
        XCTAssertTrue(markdown.contains("ssim 0.5 < 0.95"))
        XCTAssertTrue(markdown.contains("| 2 | 1 | 1 | 0 |"))
    }

    func testWriteCreatesJSONAndMarkdown() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            var report = GoldenReport(
                suite: "artifacts",
                generatedAt: "2026-01-01T00:00:00Z",
                environment: environment
            )
            report.append(.fixture(name: "fixture", passed: true))

            let artifacts = try report.write(to: directory)
            XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.jsonURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.markdownURL.path))

            let decoded = try JSONDecoder().decode(
                GoldenReport.self,
                from: Data(contentsOf: artifacts.jsonURL)
            )
            XCTAssertEqual(decoded.entries.count, 1)
            XCTAssertEqual(decoded.summary.passed, 1)
        }
    }

    func testEnvironmentCurrentReadsCIEnvironment() {
        let current = GoldenReportEnvironment.current()
        XCTAssertEqual(current.isCI, TestEnvironment.detectCI())
    }
}
