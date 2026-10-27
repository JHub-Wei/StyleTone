import Foundation
import PerformanceKit
import XCTest

/// Loads the committed baseline document.
enum PerformanceBaselineStore {
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PerformanceTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Performance
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
    }

    static var defaultURL: URL {
        repositoryRoot
            .appendingPathComponent("Tests", isDirectory: true)
            .appendingPathComponent("Performance", isDirectory: true)
            .appendingPathComponent("Baselines", isDirectory: true)
            .appendingPathComponent("performance-baselines.json")
    }

    static func baselineURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["ST_PERF_BASELINE_PATH"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return defaultURL
    }

    static func load() throws -> PerformanceBaselineFile {
        let url = baselineURL()
        let data = try Data(contentsOf: url)
        return try PerformanceBaselineFile.decode(data)
    }
}

/// Collects observations for one test, evaluates the gate and attaches a
/// report to the test result.
final class PerformanceSession: @unchecked Sendable {
    let environment: PerformanceEnvironment
    let source: String
    let baselines: PerformanceBaselineFile
    let gate: PerformanceGate

    private(set) var observations: [PerformanceObservation] = []
    private(set) var verdicts: [PerformanceVerdict] = []

    init(source: String) throws {
        self.source = source
        self.environment = PerformanceTestEnvironment.detect()
        self.baselines = try PerformanceBaselineStore.load()
        self.gate = PerformanceGate(
            configuration: PerformanceGateConfiguration(
                maxRegressionFraction: 0.10,
                enforceContractBudget: PerformanceTestProfile.enforcesContractBudget,
                requireBaseline: PerformanceTestProfile.requiresBaseline
            )
        )
    }

    /// Records one measurement and appends its verdict.
    @discardableResult
    func record(
        _ measurement: PerformanceMeasurement,
        scenario: PerformanceScenario,
        notes: String? = nil
    ) -> PerformanceVerdict {
        let baseline = baselines.entry(
            scenarioID: scenario.id,
            environmentID: environment.id
        )
        let verdict = gate.evaluate(
            measurement: measurement,
            scenario: scenario,
            baseline: baseline,
            environment: environment
        )
        observations.append(
            PerformanceObservation(
                measurement: measurement,
                environment: environment,
                capturedAt: Self.timestamp(),
                source: source,
                notes: notes
            )
        )
        verdicts.append(verdict)
        print("PERF \(measurement.summary)")
        print("PERF_VERDICT \(verdict.status.rawValue) \(verdict.message)")
        return verdict
    }

    /// Records a measurement without evaluating the gate.
    ///
    /// Used for one-shot diagnostics (for example the very first cold decode)
    /// that intentionally have too few samples to gate.
    func recordInformational(
        _ measurement: PerformanceMeasurement,
        scenario: PerformanceScenario,
        notes: String? = nil
    ) {
        observations.append(
            PerformanceObservation(
                measurement: measurement,
                environment: environment,
                capturedAt: Self.timestamp(),
                source: source,
                notes: notes
            )
        )
        verdicts.append(
            PerformanceVerdict(
                status: .informational,
                scenarioID: scenario.id,
                unit: scenario.unit,
                measuredValue: measurement.p95,
                contractTarget: scenario.contractTarget,
                sampleCount: measurement.sampleCount,
                message: "informational only: \(measurement.summary)"
            )
        )
        print("PERF_INFO \(measurement.summary)")
    }

    /// Builds the report, attaches it to the XCTest result and blocks on any
    /// regression or contract failure.
    func finish(file: StaticString = #filePath, line: UInt = #line) {
        let report = PerformanceReport(
            generatedAt: Self.timestamp(),
            environment: environment,
            commit: Self.commit,
            toolchain: Self.toolchain,
            observations: observations,
            verdicts: verdicts
        )

        let attachment = XCTAttachment(string: report.markdown())
        attachment.name = "performance-\(Self.sanitized(source))"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Performance report") { activity in
            activity.add(attachment)
        }

        if let directory = ProcessInfo.processInfo.environment["ST_PERF_REPORT_DIR"],
           !directory.isEmpty {
            write(report, to: URL(fileURLWithPath: directory), file: file, line: line)
        }

        if !report.blockingVerdicts.isEmpty {
            print(report.markdown())
        }
        XCTAssertTrue(
            report.blockingVerdicts.isEmpty,
            report.markdown(),
            file: file,
            line: line
        )
    }

    /// Writes JSON and Markdown artifacts for CI collection.
    func write(
        _ report: PerformanceReport,
        to directory: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let base = "performance-\(Self.sanitized(source))"
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try report.jsonData().write(
                to: directory.appendingPathComponent("\(base).json"),
                options: .atomic
            )
            try report.markdown().write(
                to: directory.appendingPathComponent("\(base).md"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            XCTFail(
                "could not write performance report: \(error.localizedDescription)",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Metadata

    private static var commit: String {
        let environment = ProcessInfo.processInfo.environment
        return environment["ST_PERF_COMMIT"]
            ?? environment["GITHUB_SHA"]
            ?? "local"
    }

    private static var toolchain: String {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["ST_PERF_TOOLCHAIN"], !value.isEmpty {
            return value
        }
        return "swift test (\(PerformanceTestEnvironment.buildConfiguration.rawValue))"
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    private static func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars)
    }
}
