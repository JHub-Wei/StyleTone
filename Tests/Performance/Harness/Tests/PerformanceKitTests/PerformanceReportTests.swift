import XCTest
@testable import PerformanceKit

final class PerformanceReportTests: XCTestCase {
    private let environment = PerformanceEnvironment(
        id: "test.environment",
        kind: .ci,
        deviceModel: "test",
        osVersion: "1.0",
        architecture: "arm64",
        buildConfiguration: .debug,
        physicalMemoryMegabytes: 16_384
    )

    private func verdict(
        _ status: PerformanceGateStatus,
        scenarioID: String = "preview.firstFrame"
    ) -> PerformanceVerdict {
        PerformanceVerdict(
            status: status,
            scenarioID: scenarioID,
            unit: .seconds,
            measuredValue: 0.5,
            baselineValue: 0.4,
            limitValue: 0.44,
            contractTarget: 1.5,
            sampleCount: 5,
            environmentID: "test.environment",
            deviationFraction: 0.25,
            message: "unit"
        )
    }

    func testExitCodeAndBlockingList() {
        let passing = PerformanceReport(
            generatedAt: "2026-10-27T12:00:00Z",
            environment: environment,
            commit: "abcdef0",
            toolchain: "Swift test",
            observations: [],
            verdicts: [verdict(.passed), verdict(.baselineMissing)]
        )
        XCTAssertTrue(passing.passes)
        XCTAssertEqual(passing.exitCode, 0)

        let failing = PerformanceReport(
            generatedAt: "2026-10-27T12:00:00Z",
            environment: environment,
            commit: "abcdef0",
            toolchain: "Swift test",
            observations: [],
            verdicts: [verdict(.passed), verdict(.regression)]
        )
        XCTAssertFalse(failing.passes)
        XCTAssertEqual(failing.exitCode, 1)
        XCTAssertEqual(failing.blockingVerdicts.count, 1)
    }

    func testMarkdownContainsBlockingDetails() {
        let report = PerformanceReport(
            generatedAt: "2026-10-27T12:00:00Z",
            environment: environment,
            commit: "abcdef0",
            toolchain: "Swift test",
            observations: [],
            verdicts: [verdict(.regression)]
        )
        let markdown = report.markdown()
        XCTAssertTrue(markdown.contains("StyleTone performance report"))
        XCTAssertTrue(markdown.contains("preview.firstFrame"))
        XCTAssertTrue(markdown.contains("## Blocking"))
        XCTAssertTrue(markdown.contains("Exit code: `1`"))
    }

    func testJSONRoundTripAndStableSchema() throws {
        let verdict = verdict(.passed)
        let report = PerformanceReport(
            generatedAt: "2026-10-27T12:00:00Z",
            environment: environment,
            commit: "abcdef0",
            toolchain: "Swift test",
            observations: [],
            verdicts: [verdict]
        )
        let data = try report.jsonData()
        let decoded = try JSONDecoder().decode(PerformanceReport.self, from: data)
        XCTAssertEqual(decoded, report)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"verdicts\""))
        XCTAssertTrue(text.contains("\"status\""))
        XCTAssertTrue(text.contains("passed"))
    }
}
