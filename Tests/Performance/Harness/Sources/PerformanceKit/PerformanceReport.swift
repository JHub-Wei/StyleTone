import Foundation

/// Aggregated outcome of one performance run.
///
/// The report is the CI/device artifact: JSON for machines, Markdown for the
/// pull request. `exitCode` is `1` when any verdict blocks.
public struct PerformanceReport: Codable, Sendable, Equatable {
    public let generatedAt: String
    public let environment: PerformanceEnvironment
    public let commit: String
    public let toolchain: String
    public let observations: [PerformanceObservation]
    public let verdicts: [PerformanceVerdict]

    public init(
        generatedAt: String,
        environment: PerformanceEnvironment,
        commit: String,
        toolchain: String,
        observations: [PerformanceObservation],
        verdicts: [PerformanceVerdict]
    ) {
        self.generatedAt = generatedAt
        self.environment = environment
        self.commit = commit
        self.toolchain = toolchain
        self.observations = observations
        self.verdicts = verdicts
    }

    /// Verdicts that fail a gated run.
    public var blockingVerdicts: [PerformanceVerdict] {
        verdicts.filter(\.isBlocking)
    }

    /// Verdicts recorded without blocking (missing baseline, informational).
    public var informationalVerdicts: [PerformanceVerdict] {
        verdicts.filter { !$0.isBlocking }
    }

    /// Process exit code for a CI wrapper.
    public var exitCode: Int32 {
        blockingVerdicts.isEmpty ? 0 : 1
    }

    /// `true` when every verdict passed the regression and contract checks.
    public var passes: Bool {
        blockingVerdicts.isEmpty
    }

    /// Machine-readable JSON artifact.
    public func jsonData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(self)
        } catch {
            throw PerformanceKitError.reportEncodingFailed(error.localizedDescription)
        }
    }

    /// Markdown artifact for a pull request or build summary.
    public func markdown() -> String {
        var lines: [String] = []
        lines.append("# StyleTone performance report")
        lines.append("")
        lines.append("- Environment: `\(environment.summary)`")
        lines.append("- Reference device: iPhone 13 class")
        lines.append("- Commit: `\(commit)`")
        lines.append("- Toolchain: \(toolchain)")
        lines.append("- Generated: \(generatedAt)")
        lines.append("- Gate: contract budgets use p95; regression >10 % blocks; "
            + "noise floors are documented per scenario.")
        lines.append("")

        if verdicts.isEmpty {
            lines.append("_No performance verdicts recorded._")
        } else {
            lines.append("| Scenario | Value | Stat | Baseline | Limit | Samples | Status |")
            lines.append("|---|---:|---|---:|---:|---:|---|")
            for verdict in verdicts {
                lines.append(
                    "| `\(verdict.scenarioID)` "
                        + "| \(format(verdict.measuredValue, unit: verdict.unit)) "
                        + "| \(verdict.statistic.rawValue) "
                        + "| \(format(verdict.baselineValue, unit: verdict.unit)) "
                        + "| \(format(verdict.limitValue, unit: verdict.unit)) "
                        + "| \(verdict.sampleCount) "
                        + "| \(verdict.status.isBlocking ? "**\(verdict.status.label)**" : verdict.status.label) |"
                )
            }
        }

        if !blockingVerdicts.isEmpty {
            lines.append("")
            lines.append("## Blocking")
            for verdict in blockingVerdicts {
                lines.append("- `\(verdict.scenarioID)`: \(verdict.message)")
            }
        }

        if !informationalVerdicts.isEmpty {
            lines.append("")
            lines.append("## Informational")
            for verdict in informationalVerdicts {
                lines.append("- `\(verdict.scenarioID)`: \(verdict.message)")
            }
        }

        lines.append("")
        lines.append("Exit code: `\(exitCode)`")
        return lines.joined(separator: "\n")
    }

    private func format(_ value: Double?, unit: PerformanceUnit) -> String {
        guard let value else { return "—" }
        if unit == .seconds || unit == .framesPerSecond {
            return String(format: "%.4f %@", value, unit.symbol)
        }
        return String(format: "%.1f %@", value, unit.symbol)
    }
}
