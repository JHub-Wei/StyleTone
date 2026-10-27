import Foundation

// MARK: - Verdict

/// Outcome of one gate evaluation.
public enum PerformanceGateStatus: String, Codable, Sendable, CaseIterable {
    /// Within the contract budget and the 10 % baseline allowance.
    case passed
    /// More than 10 % slower (or lower fps) than the recorded baseline.
    case regression
    /// The p95 exceeds a contracts §10 budget.
    case contractExceeded
    /// No baseline exists for this scenario on this environment.
    case baselineMissing
    /// A baseline is required by policy but missing.
    case baselineRequired
    /// A baseline exists but its `gateEnabled` flag is `false`.
    case baselineNotGated
    /// The baseline belongs to another environment or build configuration.
    case environmentMismatch
    /// Too few samples for a trustworthy p95.
    case insufficientSamples
    /// The baseline entry itself is malformed.
    case invalidBaseline
    /// The measurement is malformed or does not match the scenario.
    case invalidMeasurement
    /// Explicitly informational; never blocks.
    case informational

    /// `true` when this status must fail a gated CI/device run.
    public var isBlocking: Bool {
        switch self {
        case .regression, .contractExceeded, .insufficientSamples,
             .invalidBaseline, .invalidMeasurement, .baselineRequired:
            return true
        case .passed, .baselineMissing, .baselineNotGated, .environmentMismatch,
             .informational:
            return false
        }
    }

    /// Human readable label for report tables.
    public var label: String {
        switch self {
        case .passed: return "pass"
        case .regression: return "regression"
        case .contractExceeded: return "contract exceeded"
        case .baselineMissing: return "no baseline"
        case .baselineRequired: return "baseline required"
        case .baselineNotGated: return "baseline not gated"
        case .environmentMismatch: return "environment mismatch"
        case .insufficientSamples: return "insufficient samples"
        case .invalidBaseline: return "invalid baseline"
        case .invalidMeasurement: return "invalid measurement"
        case .informational: return "informational"
        }
    }
}

/// One immutable gate decision.
public struct PerformanceVerdict: Codable, Sendable, Equatable {
    public let status: PerformanceGateStatus
    public let scenarioID: String
    public let unit: PerformanceUnit
    public let measuredValue: Double?
    public let baselineValue: Double?
    public let limitValue: Double?
    public let contractTarget: Double?
    public let sampleCount: Int
    public let environmentID: String?
    /// Signed degradation fraction against the baseline (positive = worse).
    public let deviationFraction: Double?
    /// Human readable explanation, no PII.
    public let message: String

    public init(
        status: PerformanceGateStatus,
        scenarioID: String,
        unit: PerformanceUnit,
        measuredValue: Double? = nil,
        baselineValue: Double? = nil,
        limitValue: Double? = nil,
        contractTarget: Double? = nil,
        sampleCount: Int = 0,
        environmentID: String? = nil,
        deviationFraction: Double? = nil,
        message: String
    ) {
        self.status = status
        self.scenarioID = scenarioID
        self.unit = unit
        self.measuredValue = measuredValue
        self.baselineValue = baselineValue
        self.limitValue = limitValue
        self.contractTarget = contractTarget
        self.sampleCount = sampleCount
        self.environmentID = environmentID
        self.deviationFraction = deviationFraction
        self.message = message
    }

    /// `true` when this verdict must fail a gated run.
    public var isBlocking: Bool { status.isBlocking }
}

// MARK: - Configuration

/// Gate policy. The 10 % regression threshold is fixed by WP-24 acceptance.
public struct PerformanceGateConfiguration: Sendable, Equatable {
    /// Fraction worse than the baseline that blocks (0.10 = 10 %).
    public var maxRegressionFraction: Double
    /// When `false`, contract budgets are recorded but do not block. Used on
    /// shared CI runners where a debug build cannot meet device budgets.
    public var enforceContractBudget: Bool
    /// When `false`, missing baselines still block. Defaults to `false` so the
    /// first run on a new device can record a baseline.
    public var requireBaseline: Bool

    public init(
        maxRegressionFraction: Double = 0.10,
        enforceContractBudget: Bool = true,
        requireBaseline: Bool = false
    ) {
        self.maxRegressionFraction = min(max(maxRegressionFraction, 0), 1)
        self.enforceContractBudget = enforceContractBudget
        self.requireBaseline = requireBaseline
    }
}

// MARK: - Gate

/// Compares a measurement with the contract budget and the committed baseline.
///
/// Evaluation order is deliberate:
/// 1. malformed measurement / too few samples;
/// 2. contract budget (absolute, always authoritative when enabled);
/// 3. baseline presence, environment and `gateEnabled`;
/// 4. the 10 % regression rule with a small absolute noise floor.
///
/// A contract failure is therefore never hidden by a missing baseline, and a
/// missing baseline never hides a regression once one is recorded.
public struct PerformanceGate: Sendable {
    public let configuration: PerformanceGateConfiguration

    public init(configuration: PerformanceGateConfiguration = PerformanceGateConfiguration()) {
        self.configuration = configuration
    }

    public func evaluate(
        measurement: PerformanceMeasurement,
        scenario: PerformanceScenario,
        baseline: PerformanceBaselineEntry?,
        environment: PerformanceEnvironment? = nil
    ) -> PerformanceVerdict {
        guard measurement.scenarioID == scenario.id else {
            return verdict(
                .invalidMeasurement,
                scenario: scenario,
                measurement: measurement,
                message: "measurement id \(measurement.scenarioID) does not match "
                    + scenario.id
            )
        }
        guard measurement.unit == scenario.unit else {
            return verdict(
                .invalidMeasurement,
                scenario: scenario,
                measurement: measurement,
                message: "measurement unit \(measurement.unit.rawValue) does not match "
                    + scenario.unit.rawValue
            )
        }
        guard measurement.sampleCount >= scenario.minimumSamples else {
            return verdict(
                .insufficientSamples,
                scenario: scenario,
                measurement: measurement,
                message: "\(measurement.sampleCount) samples is fewer than the "
                    + "\(scenario.minimumSamples) required for a trustworthy p95"
            )
        }

        if configuration.enforceContractBudget,
           let target = scenario.contractTarget,
           let failure = contractFailure(
               measured: measurement.p95,
               scenario: scenario,
               target: target
           ) {
            return verdict(
                .contractExceeded,
                scenario: scenario,
                measurement: measurement,
                limit: target,
                message: failure
            )
        }

        guard let baseline else {
            return verdict(
                policyBlockingMissingBaseline ? .baselineRequired : .baselineMissing,
                scenario: scenario,
                measurement: measurement,
                message: "no baseline for \(scenario.id) on "
                    + (environment?.id ?? "this environment")
            )
        }

        if let environment, baseline.environmentID != environment.id {
            return verdict(
                .environmentMismatch,
                scenario: scenario,
                measurement: measurement,
                baseline: baseline,
                message: "baseline environment \(baseline.environmentID) does not match "
                    + environment.id
            )
        }
        guard baseline.unit == scenario.unit else {
            return verdict(
                .invalidBaseline,
                scenario: scenario,
                measurement: measurement,
                baseline: baseline,
                message: "baseline unit \(baseline.unit.rawValue) does not match "
                    + scenario.unit.rawValue
            )
        }
        guard baseline.value.isFinite, baseline.value > 0 else {
            return verdict(
                .invalidBaseline,
                scenario: scenario,
                measurement: measurement,
                baseline: baseline,
                message: "baseline value must be finite and positive"
            )
        }
        guard baseline.gateEnabled else {
            return verdict(
                .baselineNotGated,
                scenario: scenario,
                measurement: measurement,
                baseline: baseline,
                message: "baseline \(baseline.id) is recorded but not gated"
            )
        }

        let limit = regressionLimit(baseline: baseline.value, scenario: scenario)
        let delta = directionalDelta(
            measured: measurement.p95,
            baseline: baseline.value,
            scenario: scenario
        )
        let deviation = delta / baseline.value
        let exceedsLimit = directionalWorse(
            measured: measurement.p95,
            limit: limit,
            scenario: scenario
        )
        let exceedsNoiseFloor = delta > scenario.noiseFloor

        if exceedsLimit, exceedsNoiseFloor {
            return verdict(
                .regression,
                scenario: scenario,
                measurement: measurement,
                baseline: baseline,
                limit: limit,
                deviation: deviation,
                message: String(
                    format: "%@ regressed %.1f%% (p95 %.4f %@ vs baseline %.4f; "
                        + "limit %.4f, noise floor %.4f)",
                    scenario.displayName,
                    deviation * 100,
                    measurement.p95,
                    scenario.unit.symbol,
                    baseline.value,
                    limit,
                    scenario.noiseFloor
                )
            )
        }

        return verdict(
            .passed,
            scenario: scenario,
            measurement: measurement,
            baseline: baseline,
            limit: limit,
            deviation: deviation,
            message: String(
                format: "%@ p95 %.4f %@ within %.4f limit (baseline %.4f)",
                scenario.displayName,
                measurement.p95,
                scenario.unit.symbol,
                limit,
                baseline.value
            )
        )
    }

    // MARK: - Rules

    private var policyBlockingMissingBaseline: Bool {
        configuration.requireBaseline
    }

    /// Budget failures are direction-aware.
    private func contractFailure(
        measured: Double,
        scenario: PerformanceScenario,
        target: Double
    ) -> String? {
        let failed: Bool
        switch scenario.direction {
        case .lowerIsBetter:
            failed = measured > target
        case .higherIsBetter:
            failed = measured < target
        }
        guard failed else { return nil }
        return String(
            format: "%@ p95 %.4f %@ exceeds contract %@ %.4f",
            scenario.displayName,
            measured,
            scenario.unit.symbol,
            scenario.direction == .lowerIsBetter ? "budget" : "floor",
            target
        )
    }

    private func regressionLimit(
        baseline: Double,
        scenario: PerformanceScenario
    ) -> Double {
        switch scenario.direction {
        case .lowerIsBetter:
            return baseline * (1 + configuration.maxRegressionFraction)
        case .higherIsBetter:
            return baseline * (1 - configuration.maxRegressionFraction)
        }
    }

    private func directionalDelta(
        measured: Double,
        baseline: Double,
        scenario: PerformanceScenario
    ) -> Double {
        switch scenario.direction {
        case .lowerIsBetter:
            return measured - baseline
        case .higherIsBetter:
            return baseline - measured
        }
    }

    private func directionalWorse(
        measured: Double,
        limit: Double,
        scenario: PerformanceScenario
    ) -> Bool {
        switch scenario.direction {
        case .lowerIsBetter:
            return measured > limit
        case .higherIsBetter:
            return measured < limit
        }
    }

    // MARK: - Construction

    private func verdict(
        _ status: PerformanceGateStatus,
        scenario: PerformanceScenario,
        measurement: PerformanceMeasurement,
        baseline: PerformanceBaselineEntry? = nil,
        limit: Double? = nil,
        deviation: Double? = nil,
        message: String
    ) -> PerformanceVerdict {
        PerformanceVerdict(
            status: status,
            scenarioID: scenario.id,
            unit: scenario.unit,
            measuredValue: measurement.p95,
            baselineValue: baseline?.value,
            limitValue: limit,
            contractTarget: scenario.contractTarget,
            sampleCount: measurement.sampleCount,
            environmentID: baseline?.environmentID,
            deviationFraction: deviation,
            message: message
        )
    }
}
