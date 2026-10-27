import Foundation

// MARK: - Baseline

/// Per-metric tolerances used when comparing a run against the committed
/// baseline. They are absolute allowed drifts, not percentages, so a tiny
/// baseline value cannot hide a large absolute change.
public struct PortraitBaselineTolerances: Sendable, Equatable, Codable {
    public var backgroundDeviationDeltaPx: Double
    public var backgroundAngleDeltaDegrees: Double
    public var skinMeanDeltaEDelta: Double
    public var skinP95DeltaEDelta: Double
    public var skinDeltaLDelta: Double
    public var skinSaturationRatioDrop: Double
    public var skinClipIncreaseDelta: Double
    public var skinNonSkinP95Delta: Double
    public var finalDeltaLDelta: Double
    public var finalMeanDeltaEDelta: Double
    public var coverageMeanDeltaEDelta: Double
    public var coverageP95DeltaEDelta: Double
    public var ssimDrop: Double
    public var edgeMedianRetentionDrop: Double
    public var edgeDegradedFractionDelta: Double
    public var edgeGradientRatioDrop: Double
    public var signatureMeanLumaDelta: Double
    public var signatureMaxLumaDelta: Int
    public var signatureMeanChromaDelta: Double

    public init(
        backgroundDeviationDeltaPx: Double = 1.0,
        backgroundAngleDeltaDegrees: Double = 0.75,
        skinMeanDeltaEDelta: Double = 0.75,
        skinP95DeltaEDelta: Double = 1.5,
        skinDeltaLDelta: Double = 0.5,
        skinSaturationRatioDrop: Double = 0.015,
        skinClipIncreaseDelta: Double = 0.002,
        skinNonSkinP95Delta: Double = 0.5,
        finalDeltaLDelta: Double = 0.5,
        finalMeanDeltaEDelta: Double = 0.75,
        coverageMeanDeltaEDelta: Double = 0.75,
        coverageP95DeltaEDelta: Double = 1.5,
        ssimDrop: Double = 0.01,
        edgeMedianRetentionDrop: Double = 0.05,
        edgeDegradedFractionDelta: Double = 0.02,
        edgeGradientRatioDrop: Double = 0.05,
        signatureMeanLumaDelta: Double = 2.0,
        signatureMaxLumaDelta: Int = 12,
        signatureMeanChromaDelta: Double = 2.0
    ) {
        self.backgroundDeviationDeltaPx = backgroundDeviationDeltaPx
        self.backgroundAngleDeltaDegrees = backgroundAngleDeltaDegrees
        self.skinMeanDeltaEDelta = skinMeanDeltaEDelta
        self.skinP95DeltaEDelta = skinP95DeltaEDelta
        self.skinDeltaLDelta = skinDeltaLDelta
        self.skinSaturationRatioDrop = skinSaturationRatioDrop
        self.skinClipIncreaseDelta = skinClipIncreaseDelta
        self.skinNonSkinP95Delta = skinNonSkinP95Delta
        self.finalDeltaLDelta = finalDeltaLDelta
        self.finalMeanDeltaEDelta = finalMeanDeltaEDelta
        self.coverageMeanDeltaEDelta = coverageMeanDeltaEDelta
        self.coverageP95DeltaEDelta = coverageP95DeltaEDelta
        self.ssimDrop = ssimDrop
        self.edgeMedianRetentionDrop = edgeMedianRetentionDrop
        self.edgeDegradedFractionDelta = edgeDegradedFractionDelta
        self.edgeGradientRatioDrop = edgeGradientRatioDrop
        self.signatureMeanLumaDelta = signatureMeanLumaDelta
        self.signatureMaxLumaDelta = signatureMaxLumaDelta
        self.signatureMeanChromaDelta = signatureMeanChromaDelta
    }

    public static let standard = PortraitBaselineTolerances()
}

/// One sample in the committed baseline.
public struct PortraitBaselineEntry: Codable, Sendable, Equatable {
    public var sampleID: String
    public var metrics: PortraitSampleMetrics

    public init(sampleID: String, metrics: PortraitSampleMetrics) {
        self.sampleID = sampleID
        self.metrics = metrics
    }
}

/// The committed metric baseline.
///
/// The baseline deliberately stores metrics and a compact signature rather than
/// full golden PNGs: it is reviewable, small and cannot accidentally become a
/// face dataset. Visual reference outputs live in `Tests/Integration/Goldens`
/// for a representative subset and are compared separately.
public struct PortraitBaseline: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var corpusVersion: String
    public var corpusSHA256: String
    public var recordedAt: String
    public var toolVersion: String
    public var entries: [PortraitBaselineEntry]

    public init(
        schemaVersion: Int = PortraitBaseline.currentSchemaVersion,
        corpusVersion: String,
        corpusSHA256: String,
        recordedAt: String,
        toolVersion: String = "1.0.0",
        entries: [PortraitBaselineEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.corpusVersion = corpusVersion
        self.corpusSHA256 = corpusSHA256
        self.recordedAt = recordedAt
        self.toolVersion = toolVersion
        self.entries = entries
    }

    public static func decode(_ data: Data) throws -> PortraitBaseline {
        do {
            return try JSONDecoder().decode(PortraitBaseline.self, from: data)
        } catch {
            throw GoldenSupportError.invalidManifest(
                reason: "portrait baseline is not valid JSON: \(error.localizedDescription)"
            )
        }
    }

    public func encodedJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        if prettyPrinted {
            formatting.insert(.prettyPrinted)
        }
        encoder.outputFormatting = formatting
        return try encoder.encode(self)
    }

    public func entry(for sampleID: String) -> PortraitBaselineEntry? {
        entries.first { $0.sampleID == sampleID }
    }

    /// Validates the schema and that the baseline matches a corpus exactly.
    public func validate(corpus: PortraitCorpus) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw GoldenSupportError.invalidManifest(
                reason: "unsupported portrait baseline schemaVersion \(schemaVersion)"
            )
        }
        guard corpusVersion == corpus.corpusVersion else {
            throw GoldenSupportError.invalidManifest(
                reason: "baseline corpusVersion '\(corpusVersion)' does not match "
                    + "corpus '\(corpus.corpusVersion)'"
            )
        }
        let expectedIDs = Set(corpus.samples.map(\.id))
        let actualIDs = Set(entries.map(\.sampleID))
        guard expectedIDs == actualIDs else {
            let missing = expectedIDs.subtracting(actualIDs).sorted().prefix(5)
            let extra = actualIDs.subtracting(expectedIDs).sorted().prefix(5)
            throw GoldenSupportError.invalidManifest(
                reason: "baseline sample ids do not match the corpus; "
                    + "missing=\(missing.joined(separator: ",")) "
                    + "extra=\(extra.joined(separator: ","))"
            )
        }
        guard entries.count == corpus.samples.count else {
            throw GoldenSupportError.invalidManifest(
                reason: "baseline has \(entries.count) entries for "
                    + "\(corpus.samples.count) corpus samples"
            )
        }
    }
}

/// Regression checks against a committed baseline.
public enum PortraitBaselineComparator {
    /// Returns human-readable regression messages, one per violated tolerance.
    public static func regressions(
        current: PortraitSampleMetrics,
        baseline: PortraitSampleMetrics,
        tolerances: PortraitBaselineTolerances = .standard
    ) -> [String] {
        var messages: [String] = []

        func increase(
            _ name: String,
            _ currentValue: Double,
            _ baselineValue: Double,
            tolerance: Double
        ) {
            if currentValue > baselineValue + tolerance {
                messages.append(
                    "baseline.\(name) "
                        + String(
                            format: "%.3f -> %.3f (+%.3f > %.3f)",
                            baselineValue,
                            currentValue,
                            currentValue - baselineValue,
                            tolerance
                        )
                )
            }
        }

        func drop(
            _ name: String,
            _ currentValue: Double,
            _ baselineValue: Double,
            tolerance: Double
        ) {
            if currentValue < baselineValue - tolerance {
                messages.append(
                    "baseline.\(name) "
                        + String(
                            format: "%.3f -> %.3f (-%.3f > %.3f)",
                            baselineValue,
                            currentValue,
                            baselineValue - currentValue,
                            tolerance
                        )
                )
            }
        }

        increase(
            "backgroundMaxDeviationPx",
            current.backgroundMaxDeviationPx,
            baseline.backgroundMaxDeviationPx,
            tolerance: tolerances.backgroundDeviationDeltaPx
        )
        increase(
            "backgroundMaxAngleDegrees",
            abs(current.backgroundMaxAngleDegrees),
            abs(baseline.backgroundMaxAngleDegrees),
            tolerance: tolerances.backgroundAngleDeltaDegrees
        )
        increase(
            "skinMeanDeltaE00",
            current.skinMeanDeltaE00,
            baseline.skinMeanDeltaE00,
            tolerance: tolerances.skinMeanDeltaEDelta
        )
        increase(
            "skinP95DeltaE00",
            current.skinP95DeltaE00,
            baseline.skinP95DeltaE00,
            tolerance: tolerances.skinP95DeltaEDelta
        )
        increase(
            "skinAbsDeltaL",
            abs(current.skinMeanDeltaL),
            abs(baseline.skinMeanDeltaL),
            tolerance: tolerances.skinDeltaLDelta
        )
        drop(
            "skinSaturationRatio",
            current.skinSaturationRatio,
            baseline.skinSaturationRatio,
            tolerance: tolerances.skinSaturationRatioDrop
        )
        increase(
            "skinClipIncrease",
            current.skinClipIncrease,
            baseline.skinClipIncrease,
            tolerance: tolerances.skinClipIncreaseDelta
        )
        increase(
            "skinNonSkinP95DeltaE00",
            current.skinNonSkinP95DeltaE00,
            baseline.skinNonSkinP95DeltaE00,
            tolerance: tolerances.skinNonSkinP95Delta
        )
        increase(
            "skinFinalAbsDeltaL",
            abs(current.skinFinalMeanDeltaL),
            abs(baseline.skinFinalMeanDeltaL),
            tolerance: tolerances.finalDeltaLDelta
        )
        increase(
            "skinFinalMeanDeltaE00",
            current.skinFinalMeanDeltaE00,
            baseline.skinFinalMeanDeltaE00,
            tolerance: tolerances.finalMeanDeltaEDelta
        )
        increase(
            "coverageMeanDeltaE00",
            current.coverageMeanDeltaE00,
            baseline.coverageMeanDeltaE00,
            tolerance: tolerances.coverageMeanDeltaEDelta
        )
        increase(
            "coverageP95DeltaE00",
            current.coverageP95DeltaE00,
            baseline.coverageP95DeltaE00,
            tolerance: tolerances.coverageP95DeltaEDelta
        )
        drop(
            "finalSSIM",
            current.finalSSIM,
            baseline.finalSSIM,
            tolerance: tolerances.ssimDrop
        )
        drop(
            "edgeMedianContrastRetention",
            current.edgeMedianContrastRetention,
            baseline.edgeMedianContrastRetention,
            tolerance: tolerances.edgeMedianRetentionDrop
        )
        increase(
            "edgeDegradedFraction",
            current.edgeDegradedFraction,
            baseline.edgeDegradedFraction,
            tolerance: tolerances.edgeDegradedFractionDelta
        )
        drop(
            "edgeGradientEnergyRatio",
            current.edgeGradientEnergyRatio,
            baseline.edgeGradientEnergyRatio,
            tolerance: tolerances.edgeGradientRatioDrop
        )

        let signature = current.signature.compare(to: baseline.signature)
        if signature.meanLumaDelta > tolerances.signatureMeanLumaDelta
            || signature.maxLumaDelta > tolerances.signatureMaxLumaDelta
            || signature.meanChromaDelta > tolerances.signatureMeanChromaDelta
        {
            messages.append(
                String(
                    format: "baseline.signature lumaMean=%.2f lumaMax=%d chromaMean=%.2f",
                    signature.meanLumaDelta,
                    signature.maxLumaDelta,
                    signature.meanChromaDelta
                )
            )
        }
        return messages
    }
}

// MARK: - Sample result and aggregate gates

/// One sample result in the CI report.
public struct PortraitSampleResult: Codable, Sendable, Equatable {
    public var sampleID: String
    public var skinTone: String
    public var bodyType: String
    public var background: String
    public var framing: String
    public var occlusions: [String]
    public var personCount: Int
    public var metrics: PortraitSampleMetrics
    public var failures: [String]
    public var baselineRegressions: [String]
    public var durationSeconds: Double?

    public init(
        sampleID: String,
        skinTone: String,
        bodyType: String,
        background: String,
        framing: String,
        occlusions: [String],
        personCount: Int,
        metrics: PortraitSampleMetrics,
        failures: [String],
        baselineRegressions: [String],
        durationSeconds: Double? = nil
    ) {
        self.sampleID = sampleID
        self.skinTone = skinTone
        self.bodyType = bodyType
        self.background = background
        self.framing = framing
        self.occlusions = occlusions
        self.personCount = personCount
        self.metrics = metrics
        self.failures = failures
        self.baselineRegressions = baselineRegressions
        self.durationSeconds = durationSeconds
    }

    public var isPassing: Bool {
        failures.isEmpty && baselineRegressions.isEmpty
    }

    /// Category label used in failure reports.
    public var categoryLabel: String {
        "\(skinTone)/\(bodyType) \(framing) \(background) \(occlusions.joined(separator: "+"))"
            + " \(personCount)p"
    }
}

/// Aggregate gate thresholds from the WP-25 card.
public struct PortraitAggregateThresholds: Sendable, Equatable, Codable {
    /// Fewer than 5 % of samples with measured lines may show obvious bending.
    public var backgroundDistortionRateMax: Double
    /// The corpus must contain enough samples where lines could be measured.
    public var minimumSamplesWithMeasuredLines: Int
    /// Zero skin-tone incidents are allowed.
    public var skinIncidentSamplesMax: Int
    /// Zero silhouette/edge failures are allowed.
    public var edgeFailureSamplesMax: Int
    /// Maximum spread of final mean skin ΔL across the six Fitzpatrick bands.
    public var fairnessSpreadMaxDeltaL: Double
    /// Dark skin (V/VI) must not be brightened by more than this.
    public var darkSkinMeanDeltaLMax: Double
    /// Baseline regressions allowed (comparison mode only).
    public var baselineRegressionsMax: Int

    public init(
        backgroundDistortionRateMax: Double = 0.05,
        minimumSamplesWithMeasuredLines: Int = 40,
        skinIncidentSamplesMax: Int = 0,
        edgeFailureSamplesMax: Int = 0,
        fairnessSpreadMaxDeltaL: Double = 1.0,
        darkSkinMeanDeltaLMax: Double = 1.0,
        baselineRegressionsMax: Int = 0
    ) {
        self.backgroundDistortionRateMax = backgroundDistortionRateMax
        self.minimumSamplesWithMeasuredLines = minimumSamplesWithMeasuredLines
        self.skinIncidentSamplesMax = skinIncidentSamplesMax
        self.edgeFailureSamplesMax = edgeFailureSamplesMax
        self.fairnessSpreadMaxDeltaL = fairnessSpreadMaxDeltaL
        self.darkSkinMeanDeltaLMax = darkSkinMeanDeltaLMax
        self.baselineRegressionsMax = baselineRegressionsMax
    }

    public static let standard = PortraitAggregateThresholds()
}

/// One aggregate gate outcome.
public struct PortraitGateResult: Codable, Sendable, Equatable {
    public var name: String
    public var passed: Bool
    public var skipped: Bool
    public var value: Double
    public var threshold: Double
    public var message: String

    public init(
        name: String,
        passed: Bool,
        skipped: Bool = false,
        value: Double,
        threshold: Double,
        message: String
    ) {
        self.name = name
        self.passed = passed
        self.skipped = skipped
        self.value = value
        self.threshold = threshold
        self.message = message
    }
}

/// Applies the WP-25 quality gates to a finished run.
public enum PortraitAggregateGate {
    public static func evaluate(
        results: [PortraitSampleResult],
        thresholds: PortraitAggregateThresholds = .standard,
        baselineMode: PortraitBaselineMode = .comparison
    ) -> [PortraitGateResult] {
        var gates: [PortraitGateResult] = []

        let measured = results.filter { $0.metrics.backgroundMeasuredLines > 0 }
        let distorted = measured.filter { $0.metrics.backgroundDistortedLines > 0 }
        let distortionRate = measured.isEmpty ? 0 : Double(distorted.count) / Double(measured.count)
        let backgroundPassed = measured.count >= thresholds.minimumSamplesWithMeasuredLines
            && distortionRate < thresholds.backgroundDistortionRateMax
        gates.append(
            PortraitGateResult(
                name: "quality.background",
                passed: backgroundPassed,
                value: distortionRate,
                threshold: thresholds.backgroundDistortionRateMax,
                message: String(
                    format: "obvious background distortion %.2f%% across %d measured samples "
                        + "(target < %.2f%%)",
                    distortionRate * 100,
                    measured.count,
                    thresholds.backgroundDistortionRateMax * 100
                )
            )
        )

        let skinIncidentResults = results.filter { result in
            result.failures.contains { $0.hasPrefix("skin.") }
        }
        gates.append(
            PortraitGateResult(
                name: "quality.skin",
                passed: skinIncidentResults.count <= thresholds.skinIncidentSamplesMax,
                value: Double(skinIncidentResults.count),
                threshold: Double(thresholds.skinIncidentSamplesMax),
                message: "\(skinIncidentResults.count) samples with skin incidents "
                    + "(target \(thresholds.skinIncidentSamplesMax))"
            )
        )

        let edgeFailures = results.filter { result in
            result.failures.contains { $0.hasPrefix("edge.") }
        }
        gates.append(
            PortraitGateResult(
                name: "quality.edges",
                passed: edgeFailures.count <= thresholds.edgeFailureSamplesMax,
                value: Double(edgeFailures.count),
                threshold: Double(thresholds.edgeFailureSamplesMax),
                message: "\(edgeFailures.count) samples with degraded silhouettes "
                    + "(target \(thresholds.edgeFailureSamplesMax))"
            )
        )

        let toneGroups = Dictionary(grouping: results) { $0.skinTone }
        let toneMeans = toneGroups.mapValues { group -> Double in
            group.map(\.metrics.skinFinalMeanDeltaL).reduce(0, +) / Double(group.count)
        }
        let spread = (toneMeans.values.max() ?? 0) - (toneMeans.values.min() ?? 0)
        let fairnessPassed = toneGroups.count == 6 && spread <= thresholds.fairnessSpreadMaxDeltaL
        gates.append(
            PortraitGateResult(
                name: "quality.fairness",
                passed: fairnessPassed,
                value: spread,
                threshold: thresholds.fairnessSpreadMaxDeltaL,
                message: String(
                    format: "skin-tone fairness spread %.3f ΔL across %d bands "
                        + "(target ≤ %.3f)",
                    spread,
                    toneGroups.count,
                    thresholds.fairnessSpreadMaxDeltaL
                )
            )
        )

        let darkTones = ["V", "VI"]
        let darkResults = results.filter { darkTones.contains($0.skinTone) }
        let darkMean = darkResults.isEmpty
            ? 0
            : darkResults.map(\.metrics.skinFinalMeanDeltaL).reduce(0, +)
                / Double(darkResults.count)
        gates.append(
            PortraitGateResult(
                name: "quality.darkSkinNoWhitening",
                passed: !darkResults.isEmpty && darkMean <= thresholds.darkSkinMeanDeltaLMax,
                value: darkMean,
                threshold: thresholds.darkSkinMeanDeltaLMax,
                message: String(
                    format: "dark-skin mean final ΔL %.3f (target ≤ %.3f)",
                    darkMean,
                    thresholds.darkSkinMeanDeltaLMax
                )
            )
        )

        let regressionCount = results.reduce(0) { $0 + $1.baselineRegressions.count }
        if baselineMode == .bootstrap {
            gates.append(
                PortraitGateResult(
                    name: "quality.baseline",
                    passed: true,
                    skipped: true,
                    value: 0,
                    threshold: 0,
                    message: "bootstrap run: baseline not recorded yet"
                )
            )
        } else {
            gates.append(
                PortraitGateResult(
                    name: "quality.baseline",
                    passed: regressionCount <= thresholds.baselineRegressionsMax,
                    value: Double(regressionCount),
                    threshold: Double(thresholds.baselineRegressionsMax),
                    message: "\(regressionCount) baseline regressions "
                        + "(target ≤ \(thresholds.baselineRegressionsMax))"
                )
            )
        }
        return gates
    }
}

/// Whether the run is recording a new baseline or comparing against one.
public enum PortraitBaselineMode: String, Codable, Sendable, CaseIterable {
    case bootstrap
    case comparison
}

// MARK: - Report

/// Machine-readable and human-readable report for the 100-sample run.
public struct PortraitRegressionReport: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var suite: String
    public var generatedAt: String
    public var corpusVersion: String
    public var corpusSHA256: String
    public var baselineMode: PortraitBaselineMode
    public var coverage: PortraitCorpusCoverage
    public var results: [PortraitSampleResult]
    public var gates: [PortraitGateResult]
    public var summary: PortraitReportSummary

    public init(
        schemaVersion: Int = PortraitRegressionReport.currentSchemaVersion,
        suite: String,
        generatedAt: String = ISO8601DateFormatter().string(from: Date()),
        corpusVersion: String,
        corpusSHA256: String,
        baselineMode: PortraitBaselineMode,
        coverage: PortraitCorpusCoverage,
        results: [PortraitSampleResult],
        gates: [PortraitGateResult]
    ) {
        self.schemaVersion = schemaVersion
        self.suite = suite
        self.generatedAt = generatedAt
        self.corpusVersion = corpusVersion
        self.corpusSHA256 = corpusSHA256
        self.baselineMode = baselineMode
        self.coverage = coverage
        self.results = results
        self.gates = gates
        self.summary = PortraitReportSummary(results: results, gates: gates)
    }

    public var isPassing: Bool {
        summary.failedSamples == 0
            && summary.failedGates == 0
            && gates.allSatisfy { $0.passed || $0.skipped }
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    public func markdown() -> String {
        var lines: [String] = []
        lines.append("# Portrait golden regression — \(suite)")
        lines.append("")
        lines.append("- generatedAt: \(generatedAt)")
        lines.append("- corpusVersion: \(corpusVersion)")
        lines.append("- corpusSHA256: `\(corpusSHA256)`")
        lines.append("- baselineMode: \(baselineMode.rawValue)")
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append("| samples | passed | failed | gates | gate failures |")
        lines.append("|---|---|---|---|---|")
        lines.append(
            "| \(summary.totalSamples) | \(summary.passedSamples) | "
                + "\(summary.failedSamples) | \(summary.totalGates) | "
                + "\(summary.failedGates) |"
        )
        lines.append("")
        lines.append("## Gates")
        lines.append("")
        lines.append("| status | gate | value | threshold | details |")
        lines.append("|---|---|---|---|---|")
        for gate in gates {
            let status = gate.skipped ? "SKIP" : (gate.passed ? "PASS" : "FAIL")
            lines.append(
                "| \(status) | \(gate.name) | \(Self.format(gate.value)) | "
                    + "\(Self.format(gate.threshold)) | \(gate.message) |"
            )
        }
        lines.append("")
        lines.append("## Coverage")
        lines.append("")
        lines.append(coverage.markdown())
        lines.append("")
        lines.append("## Categories")
        lines.append("")
        lines.append(categoryTable())
        lines.append("")
        let failing = results.filter { !$0.isPassing }
        if !failing.isEmpty {
            lines.append("## Failures")
            lines.append("")
            lines.append("| sample | category | background | skin / edge | baseline |")
            lines.append("|---|---|---|---|---|")
            for result in failing.prefix(40) {
                let absoluteFailures = result.failures.joined(separator: "; ")
                let baselineFailures = result.baselineRegressions.joined(separator: "; ")
                lines.append(
                    "| \(result.sampleID) | \(result.categoryLabel) | "
                        + "\(result.metrics.backgroundDistortedLines) distorted | "
                        + "\(Self.escape(absoluteFailures)) | "
                        + "\(Self.escape(baselineFailures)) |"
                )
            }
            if failing.count > 40 {
                lines.append("")
                lines.append("… and \(failing.count - 40) more failures in the JSON report.")
            }
        } else {
            lines.append("All samples passed the per-sample quality gates.")
        }
        return lines.joined(separator: "\n")
    }

    /// Markdown coverage table grouped by category, useful in the CI summary.
    public func categoryTable() -> String {
        var lines: [String] = []
        lines.append("| group | samples | failed | distorted bg | skin | edge |")
        lines.append("|---|---|---|---|---|---|")
        for (label, group) in groupedResults() {
            let failed = group.filter { !$0.isPassing }.count
            let distorted = group.filter { $0.metrics.backgroundDistortedLines > 0 }.count
            let skin = group.filter { $0.failures.contains { $0.hasPrefix("skin.") } }.count
            let edge = group.filter { $0.failures.contains { $0.hasPrefix("edge.") } }.count
            lines.append(
                "| \(label) | \(group.count) | \(failed) | \(distorted) | \(skin) | \(edge) |"
            )
        }
        return lines.joined(separator: "\n")
    }

    private func groupedResults() -> [(String, [PortraitSampleResult])] {
        let toneGroups = Dictionary(grouping: results, by: \.skinTone)
            .sorted { $0.key < $1.key }
            .map { ("tone \($0.key)", $0.value) }
        let backgroundGroups = Dictionary(grouping: results, by: \.background)
            .sorted { $0.key < $1.key }
            .map { ("background \($0.key)", $0.value) }
        let framingGroups = Dictionary(grouping: results, by: \.framing)
            .sorted { $0.key < $1.key }
            .map { ("framing \($0.key)", $0.value) }
        return toneGroups + backgroundGroups + framingGroups
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }
}

/// Aggregate counts in a report.
public struct PortraitReportSummary: Codable, Sendable, Equatable {
    public var totalSamples: Int
    public var passedSamples: Int
    public var failedSamples: Int
    public var totalGates: Int
    public var failedGates: Int

    public init(results: [PortraitSampleResult], gates: [PortraitGateResult]) {
        totalSamples = results.count
        passedSamples = results.filter(\.isPassing).count
        failedSamples = results.filter { !$0.isPassing }.count
        totalGates = gates.count
        failedGates = gates.filter { !$0.passed && !$0.skipped }.count
    }
}

// MARK: - Golden selection and artifacts

/// Representative output goldens committed under `Tests/Integration/Goldens`.
///
/// The list is intentionally small (12 of 100): the full corpus is covered by
/// metric gates and signatures, while these 12 make spatial drift visible in a
/// reviewable diff. Update the baseline and goldens together when the pipeline
/// intentionally changes.
public enum PortraitGoldenSelection {
    public static let sampleIDs: [String] = [
        "ps-001", "ps-006", "ps-009", "ps-010",
        "ps-013", "ps-017", "ps-018", "ps-022",
        "ps-024", "ps-032", "ps-043", "ps-066"
    ]
}

/// One tile of the contact sheet.
public struct PortraitContactSheetEntry: Sendable {
    public var sampleID: String
    public var skinTone: SkinToneBand
    public var source: PixelBuffer
    public var output: PixelBuffer
    public var difference: PixelBuffer

    public init(
        sampleID: String,
        skinTone: SkinToneBand,
        source: PixelBuffer,
        output: PixelBuffer,
        difference: PixelBuffer
    ) {
        self.sampleID = sampleID
        self.skinTone = skinTone
        self.source = source
        self.output = output
        self.difference = difference
    }
}

/// Builds the images attached to the CI artifact.
public enum PortraitArtifactBuilder {
    /// Contact sheet with source/output/amplified-diff triplets, five groups per
    /// row. No text is rendered; the tile order is the corpus order and the left
    /// stripe encodes the skin tone.
    public static func contactSheet(
        entries: [PortraitContactSheetEntry],
        columns: Int = 4,
        thumbnailWidth: Int = 72,
        thumbnailHeight: Int = 96
    ) throws -> PixelBuffer {
        guard !entries.isEmpty else {
            throw GoldenSupportError.invalidConfiguration(reason: "empty contact sheet")
        }
        let columnCount = max(1, columns)
        let rows = (entries.count + columnCount - 1) / columnCount
        let gutter = 4
        let stripeWidth = 5
        let groupWidth = thumbnailWidth * 3 + gutter * 2 + stripeWidth
        let tileWidth = groupWidth
        let tileHeight = thumbnailHeight
        let sheetWidth = columnCount * (tileWidth + gutter) + gutter
        let sheetHeight = rows * (tileHeight + gutter) + gutter
        var sheet = try PixelBuffer(
            width: sheetWidth,
            height: sheetHeight,
            fill: RGB8(gray: 18)
        )
        for (index, entry) in entries.enumerated() {
            let column = index % columnCount
            let row = index / columnCount
            let originX = gutter + column * (tileWidth + gutter)
            let originY = gutter + row * (tileHeight + gutter)
            let sourceTile = resized(entry.source, width: thumbnailWidth, height: thumbnailHeight)
            let outputTile = resized(entry.output, width: thumbnailWidth, height: thumbnailHeight)
            let differenceTile = resized(entry.difference, width: thumbnailWidth, height: thumbnailHeight)
            let toneStripe = PortraitRenderer.baseSkinColor(for: entry.skinTone)
            for y in 0 ..< thumbnailHeight {
                for x in 0 ..< stripeWidth {
                    sheet[originX + x, originY + y] = RGBA8(color: toneStripe)
                }
            }
            copy(sourceTile, to: &sheet, x: originX + stripeWidth, y: originY)
            copy(
                outputTile,
                to: &sheet,
                x: originX + stripeWidth + thumbnailWidth + gutter,
                y: originY
            )
            copy(
                differenceTile,
                to: &sheet,
                x: originX + stripeWidth + (thumbnailWidth + gutter) * 2,
                y: originY
            )
        }
        return sheet
    }

    /// Four-quadrant diagnostics image: source, output, amplified diff and an
    /// overlay with ground-truth lines, skin outline and subject outline.
    public static func diagnostics(
        scene: PortraitScene,
        source: PixelBuffer,
        output: PixelBuffer
    ) throws -> PixelBuffer {
        let tileWidth = max(1, source.width / 2)
        let tileHeight = max(1, source.height / 2)
        let difference = try ImageComparator.differenceImage(
            expected: source,
            actual: output,
            amplification: 6
        )
        var sheet = try PixelBuffer(
            width: tileWidth * 2,
            height: tileHeight * 2,
            fill: RGB8(gray: 8)
        )
        copy(
            resized(source, width: tileWidth, height: tileHeight),
            to: &sheet,
            x: 0,
            y: 0
        )
        copy(
            resized(output, width: tileWidth, height: tileHeight),
            to: &sheet,
            x: tileWidth,
            y: 0
        )
        copy(
            resized(difference, width: tileWidth, height: tileHeight),
            to: &sheet,
            x: 0,
            y: tileHeight
        )
        var overlay = resized(output, width: tileWidth, height: tileHeight)
        drawGroundTruth(
            scene: scene,
            into: &overlay,
            widthScale: Double(tileWidth) / Double(max(1, source.width)),
            heightScale: Double(tileHeight) / Double(max(1, source.height))
        )
        copy(overlay, to: &sheet, x: tileWidth, y: tileHeight)
        return sheet
    }

    /// Copies a buffer into a larger one at the given origin.
    public static func copy(_ source: PixelBuffer, to target: inout PixelBuffer, x: Int, y: Int) {
        for row in 0 ..< source.height {
            let targetY = y + row
            guard targetY >= 0, targetY < target.height else { continue }
            for column in 0 ..< source.width {
                let targetX = x + column
                guard targetX >= 0, targetX < target.width else { continue }
                target[targetX, targetY] = source[column, row]
            }
        }
    }

    /// Nearest-neighbour box average downscale. Keeps the artifact cheap without
    /// pulling in CoreGraphics resampling.
    public static func resized(
        _ source: PixelBuffer,
        width: Int,
        height: Int
    ) -> PixelBuffer {
        let targetWidth = max(1, width)
        let targetHeight = max(1, height)
        guard let buffer = try? PixelBuffer(
            width: targetWidth,
            height: targetHeight,
            fill: RGB8(gray: 0)
        ) else {
            return source
        }
        var output = buffer
        let scaleX = Double(source.width) / Double(targetWidth)
        let scaleY = Double(source.height) / Double(targetHeight)
        for y in 0 ..< targetHeight {
            let sourceY0 = Int(Double(y) * scaleY)
            let sourceY1 = max(sourceY0 + 1, Int(Double(y + 1) * scaleY))
            for x in 0 ..< targetWidth {
                let sourceX0 = Int(Double(x) * scaleX)
                let sourceX1 = max(sourceX0 + 1, Int(Double(x + 1) * scaleX))
                var red = 0
                var green = 0
                var blue = 0
                var count = 0
                for sampleY in sourceY0 ..< min(source.height, sourceY1) {
                    for sampleX in sourceX0 ..< min(source.width, sourceX1) {
                        let pixel = source[sampleX, sampleY]
                        red += Int(pixel.red)
                        green += Int(pixel.green)
                        blue += Int(pixel.blue)
                        count += 1
                    }
                }
                guard count > 0 else { continue }
                output[x, y] = RGBA8(
                    red: UInt8(red / count),
                    green: UInt8(green / count),
                    blue: UInt8(blue / count)
                )
            }
        }
        return output
    }

    private static func drawGroundTruth(
        scene: PortraitScene,
        into buffer: inout PixelBuffer,
        widthScale: Double,
        heightScale: Double
    ) {
        let red = RGBA8(red: 232, green: 54, blue: 48)
        for line in scene.groundTruth.lines {
            switch line.orientation {
            case .vertical:
                let x = Int(line.position * Double(buffer.width))
                let startY = Int(line.start * Double(buffer.height))
                let endY = Int(line.end * Double(buffer.height))
                for y in startY ... max(startY, endY) where y >= 0 && y < buffer.height {
                    if x >= 0, x < buffer.width {
                        buffer[x, y] = red
                    }
                }
            case .horizontal:
                let y = Int(line.position * Double(buffer.height))
                let startX = Int(line.start * Double(buffer.width))
                let endX = Int(line.end * Double(buffer.width))
                for x in startX ... max(startX, endX) where x >= 0 && x < buffer.width {
                    if y >= 0, y < buffer.height {
                        buffer[x, y] = red
                    }
                }
            }
        }
        let skin = MaskOperations.boundaryPoints(scene.groundTruth.skinMask)
        let green = RGBA8(red: 62, green: 214, blue: 120)
        for point in skin {
            let x = Int(Double(point.x) * widthScale)
            let y = Int(Double(point.y) * heightScale)
            guard x >= 0, x < buffer.width, y >= 0, y < buffer.height else { continue }
            buffer[x, y] = green
        }
        let person = MaskOperations.boundaryPoints(scene.groundTruth.personMask)
        let blue = RGBA8(red: 66, green: 140, blue: 255)
        for point in person {
            let x = Int(Double(point.x) * widthScale)
            let y = Int(Double(point.y) * heightScale)
            guard x >= 0, x < buffer.width, y >= 0, y < buffer.height else { continue }
            buffer[x, y] = blue
        }
    }
}
