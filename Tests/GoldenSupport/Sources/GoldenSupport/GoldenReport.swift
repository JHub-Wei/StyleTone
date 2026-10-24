import Foundation

/// Categories reported in the CI report.
public enum GoldenReportEntryKind: String, Codable, Sendable, CaseIterable {
    case imageComparison
    case performance
    case fixtureSelfCheck
    case custom
}

/// Outcome of one reported check.
public enum GoldenReportStatus: String, Codable, Sendable, CaseIterable {
    case passed
    case failed
    case skipped
}

/// Environment metadata copied into the report so an artifact can be traced
/// back to the job that produced it. No user data is collected.
public struct GoldenReportEnvironment: Codable, Sendable, Equatable {
    public var isCI: Bool
    public var provider: String?
    public var runID: String?
    public var runnerOS: String?
    public var osVersion: String?

    public init(
        isCI: Bool = false,
        provider: String? = nil,
        runID: String? = nil,
        runnerOS: String? = nil,
        osVersion: String? = nil
    ) {
        self.isCI = isCI
        self.provider = provider
        self.runID = runID
        self.runnerOS = runnerOS
        self.osVersion = osVersion
    }

    /// Reads the standard CI environment variables (`CI`, `GITHUB_ACTIONS`,
    /// `GITHUB_RUN_ID`, `RUNNER_OS`). Test-only: no network, no user data.
    public static func current() -> GoldenReportEnvironment {
        let environment = ProcessInfo.processInfo.environment
        let isCI = environment["CI"].map { $0 == "true" || $0 == "1" } ?? false
        let provider = environment["GITHUB_ACTIONS"] == "true" ? "github-actions" : nil
        return GoldenReportEnvironment(
            isCI: isCI,
            provider: provider,
            runID: environment["GITHUB_RUN_ID"],
            runnerOS: environment["RUNNER_OS"],
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}

/// One check result in the CI report.
public struct GoldenReportEntry: Codable, Sendable, Equatable {
    public var kind: GoldenReportEntryKind
    public var name: String
    public var status: GoldenReportStatus
    public var message: String?
    /// Numeric metrics such as `ssim`, `meanDeltaE00`, `p95Seconds`.
    public var metrics: [String: Double]
    /// Threshold violations for image comparisons and performance verdicts.
    public var thresholdFailures: [String]

    public init(
        kind: GoldenReportEntryKind,
        name: String,
        status: GoldenReportStatus,
        message: String? = nil,
        metrics: [String: Double] = [:],
        thresholdFailures: [String] = []
    ) {
        self.kind = kind
        self.name = name
        self.status = status
        self.message = message
        self.metrics = metrics
        self.thresholdFailures = thresholdFailures
    }

    /// Builds an entry from an image comparison report.
    public static func comparison(name: String, report: ImageDifferenceReport) -> GoldenReportEntry {
        GoldenReportEntry(
            kind: .imageComparison,
            name: name,
            status: report.passes ? .passed : .failed,
            message: report.summary,
            metrics: [
                "differingPixelRatio": report.differingPixelRatio,
                "meanChannelDelta": report.meanChannelDelta,
                "meanDeltaE00": report.meanDeltaE00,
                "p95DeltaE00": report.p95DeltaE00,
                "maxDeltaE00": report.maxDeltaE00,
                "ssim": report.ssim
            ],
            thresholdFailures: report.failures
        )
    }

    /// Builds an entry from a performance measurement and its verdict.
    public static func performance(
        name: String,
        measurement: PerformanceMeasurement,
        verdict: PerformanceVerdict
    ) -> GoldenReportEntry {
        GoldenReportEntry(
            kind: .performance,
            name: name,
            status: verdict.passed ? .passed : .failed,
            message: verdict.message,
            metrics: [
                "iterations": Double(measurement.iterations),
                "meanSeconds": measurement.meanSeconds,
                "p50Seconds": measurement.p50Seconds,
                "p95Seconds": measurement.p95Seconds,
                "maxSeconds": measurement.maxSeconds,
                "limitSeconds": verdict.limitSeconds
            ],
            thresholdFailures: verdict.passed ? [] : [verdict.message]
        )
    }

    /// Builds a fixture self-check entry.
    public static func fixture(
        name: String,
        passed: Bool,
        message: String? = nil
    ) -> GoldenReportEntry {
        GoldenReportEntry(
            kind: .fixtureSelfCheck,
            name: name,
            status: passed ? .passed : .failed,
            message: message
        )
    }
}

/// Aggregate counts for the report.
public struct GoldenReportSummary: Codable, Sendable, Equatable {
    public var total: Int
    public var passed: Int
    public var failed: Int
    public var skipped: Int

    public init(total: Int, passed: Int, failed: Int, skipped: Int) {
        self.total = total
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
    }

    public var isSuccessful: Bool { failed == 0 }
}

/// Machine-readable report written by the harness for CI artifacts.
///
/// The JSON document is stable, sorted-key encoded and versioned with
/// `schemaVersion = 1`. See `Tests/GoldenSupport/README.md` for the schema.
public struct GoldenReport: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let toolName = "GoldenSupport"
    public static let toolVersion = "1.0.0"

    public var schemaVersion: Int
    public var tool: String
    public var toolVersion: String
    public var suite: String
    public var generatedAt: String
    public var environment: GoldenReportEnvironment
    public var entries: [GoldenReportEntry]
    public var summary: GoldenReportSummary

    public init(
        suite: String,
        generatedAt: String = GoldenReport.timestamp(),
        environment: GoldenReportEnvironment = GoldenReportEnvironment.current(),
        entries: [GoldenReportEntry] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.tool = Self.toolName
        self.toolVersion = Self.toolVersion
        self.suite = suite
        self.generatedAt = generatedAt
        self.environment = environment
        self.entries = entries
        self.summary = Self.summarize(entries)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.tool = try container.decode(String.self, forKey: .tool)
        self.toolVersion = try container.decode(String.self, forKey: .toolVersion)
        self.suite = try container.decode(String.self, forKey: .suite)
        self.generatedAt = try container.decode(String.self, forKey: .generatedAt)
        self.environment = try container.decode(GoldenReportEnvironment.self, forKey: .environment)
        self.entries = try container.decode([GoldenReportEntry].self, forKey: .entries)
        self.summary = Self.summarize(entries)
    }

    public mutating func append(_ entry: GoldenReportEntry) {
        entries.append(entry)
        summary = Self.summarize(entries)
    }

    public var isSuccessful: Bool { summary.isSuccessful }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    public func markdown() -> String {
        var lines: [String] = []
        lines.append("# GoldenSupport report — \(suite)")
        lines.append("")
        lines.append("- tool: \(tool) \(toolVersion)")
        lines.append("- generatedAt: \(generatedAt)")
        lines.append("- schemaVersion: \(schemaVersion)")
        if let provider = environment.provider {
            lines.append("- CI: \(provider) run \(environment.runID ?? "unknown")")
        } else {
            lines.append("- CI: \(environment.isCI ? "yes" : "no")")
        }
        if let runnerOS = environment.runnerOS {
            lines.append("- runner: \(runnerOS)")
        }
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append("| total | passed | failed | skipped |")
        lines.append("|---|---|---|---|")
        lines.append("| \(summary.total) | \(summary.passed) | \(summary.failed) | \(summary.skipped) |")
        lines.append("")
        lines.append("## Checks")
        lines.append("")
        lines.append("| status | kind | name | details |")
        lines.append("|---|---|---|---|")
        for entry in entries {
            lines.append(
                "| \(entry.status.rawValue) | \(entry.kind.rawValue) | "
                    + "\(Self.escape(entry.name)) | \(Self.escape(entry.message ?? "")) |"
            )
        }
        let failures = entries.flatMap { entry in
            entry.thresholdFailures.map { "\(entry.name): \($0)" }
        }
        if !failures.isEmpty {
            lines.append("")
            lines.append("## Threshold failures")
            lines.append("")
            for failure in failures {
                lines.append("- \(failure)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Writes `golden-report.json` and `golden-report.md` into `directory`.
    public func write(
        to directory: URL,
        baseName: String = "golden-report"
    ) throws -> GoldenReportArtifacts {
        let prefix = try GoldenImageStore.validatedName(baseName)
        try GoldenImageStore.ensureDirectory(directory)
        let jsonURL = directory.appendingPathComponent("\(prefix).json")
        let markdownURL = directory.appendingPathComponent("\(prefix).md")
        do {
            try jsonData().write(to: jsonURL, options: .atomic)
            try Data(markdown().utf8).write(to: markdownURL, options: .atomic)
        } catch {
            throw GoldenSupportError.fileOperationFailed(reason: "report could not be written")
        }
        return GoldenReportArtifacts(jsonURL: jsonURL, markdownURL: markdownURL)
    }

    /// Injectable ISO-8601 timestamp so tests stay deterministic.
    public static func timestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func summarize(_ entries: [GoldenReportEntry]) -> GoldenReportSummary {
        GoldenReportSummary(
            total: entries.count,
            passed: entries.filter { $0.status == .passed }.count,
            failed: entries.filter { $0.status == .failed }.count,
            skipped: entries.filter { $0.status == .skipped }.count
        )
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tool
        case toolVersion
        case suite
        case generatedAt
        case environment
        case entries
        case summary
    }
}

/// Paths written by ``GoldenReport/write(to:baseName:)``.
public struct GoldenReportArtifacts: Sendable, Codable, Equatable {
    public let jsonURL: URL
    public let markdownURL: URL

    public init(jsonURL: URL, markdownURL: URL) {
        self.jsonURL = jsonURL
        self.markdownURL = markdownURL
    }
}
