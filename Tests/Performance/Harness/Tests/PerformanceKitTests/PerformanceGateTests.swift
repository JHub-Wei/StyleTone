import XCTest
@testable import PerformanceKit

final class PerformanceGateTests: XCTestCase {
    private let environment = PerformanceEnvironment(
        id: "test.environment",
        kind: .ci,
        deviceModel: "test",
        osVersion: "1.0",
        architecture: "arm64",
        buildConfiguration: .debug,
        physicalMemoryMegabytes: 16_384
    )

    private func scenario(
        id: String = "unit.lower",
        unit: PerformanceUnit = .seconds,
        direction: PerformanceDirection = .lowerIsBetter,
        target: Double? = nil,
        minimumSamples: Int = 1,
        noiseFloor: Double = 0
    ) -> PerformanceScenario {
        PerformanceScenario(
            id: id,
            displayName: id,
            unit: unit,
            direction: direction,
            contractTarget: target,
            minimumSamples: minimumSamples,
            noiseFloor: noiseFloor,
            method: "unit test"
        )
    }

    private func measurement(
        _ value: Double,
        scenario: PerformanceScenario,
        count: Int = 1
    ) throws -> PerformanceMeasurement {
        try PerformanceMeasurement(
            scenarioID: scenario.id,
            unit: scenario.unit,
            values: Array(repeating: value, count: count)
        )
    }

    private func baseline(
        _ value: Double,
        scenario: PerformanceScenario,
        environmentID: String = "test.environment",
        gateEnabled: Bool = true
    ) -> PerformanceBaselineEntry {
        PerformanceBaselineEntry(
            scenarioID: scenario.id,
            environmentID: environmentID,
            value: value,
            unit: scenario.unit,
            statistic: scenario.regressionStatistic,
            sampleCount: 5,
            recordedAt: "2026-10-27T00:00:00Z",
            commit: "unit",
            source: "unit test",
            gateEnabled: gateEnabled
        )
    }

    func testExactlyTenPercentIsNotARegression() throws {
        let scenario = scenario()
        let verdict = PerformanceGate().evaluate(
            measurement: try measurement(1.10, scenario: scenario),
            scenario: scenario,
            baseline: baseline(1.0, scenario: scenario),
            environment: environment
        )
        XCTAssertEqual(verdict.status, .passed)
        XCTAssertFalse(verdict.isBlocking)
    }

    func testMoreThanTenPercentBlocks() throws {
        let scenario = scenario()
        let verdict = PerformanceGate().evaluate(
            measurement: try measurement(1.101, scenario: scenario),
            scenario: scenario,
            baseline: baseline(1.0, scenario: scenario),
            environment: environment
        )
        XCTAssertEqual(verdict.status, .regression)
        XCTAssertTrue(verdict.isBlocking)
        XCTAssertGreaterThan(verdict.deviationFraction ?? 0, 0.10)
    }

    func testFasterThanBaselinePasses() throws {
        let scenario = scenario()
        let verdict = PerformanceGate().evaluate(
            measurement: try measurement(0.8, scenario: scenario),
            scenario: scenario,
            baseline: baseline(1.0, scenario: scenario),
            environment: environment
        )
        XCTAssertEqual(verdict.status, .passed)
    }

    func testHigherIsBetterRegressionUsesTheSameTenPercentRule() throws {
        let scenario = scenario(
            id: "unit.fps",
            unit: .framesPerSecond,
            direction: .higherIsBetter,
            target: 30
        )
        let baselineEntry = baseline(40, scenario: scenario)

        let elevenPercentDrop = try measurement(35.6, scenario: scenario)
        XCTAssertEqual(
            PerformanceGate().evaluate(
                measurement: elevenPercentDrop,
                scenario: scenario,
                baseline: baselineEntry,
                environment: environment
            ).status,
            .regression
        )

        let ninePercentDrop = try measurement(36.4, scenario: scenario)
        XCTAssertEqual(
            PerformanceGate().evaluate(
                measurement: ninePercentDrop,
                scenario: scenario,
                baseline: baselineEntry,
                environment: environment
            ).status,
            .passed
        )
    }

    func testContractBudgetBlocksEvenWithoutBaseline() throws {
        let scenario = scenario(id: "unit.budget", target: 1.5)
        let verdict = PerformanceGate().evaluate(
            measurement: try measurement(1.6, scenario: scenario),
            scenario: scenario,
            baseline: nil,
            environment: environment
        )
        XCTAssertEqual(verdict.status, .contractExceeded)
        XCTAssertTrue(verdict.isBlocking)
    }

    func testContractBudgetIsDirectionAwareForFPS() throws {
        let scenario = scenario(
            id: "unit.fpsBudget",
            unit: .framesPerSecond,
            direction: .higherIsBetter,
            target: 30
        )
        let verdict = PerformanceGate().evaluate(
            measurement: try measurement(29.9, scenario: scenario),
            scenario: scenario,
            baseline: nil,
            environment: environment
        )
        XCTAssertEqual(verdict.status, .contractExceeded)
    }

    func testMissingBaselineIsInformationalByDefault() throws {
        let scenario = scenario()
        let verdict = PerformanceGate().evaluate(
            measurement: try measurement(1.0, scenario: scenario),
            scenario: scenario,
            baseline: nil,
            environment: environment
        )
        XCTAssertEqual(verdict.status, .baselineMissing)
        XCTAssertFalse(verdict.isBlocking)
    }

    func testMissingBaselineCanBeRequired() throws {
        let scenario = scenario()
        let gate = PerformanceGate(
            configuration: PerformanceGateConfiguration(requireBaseline: true)
        )
        let verdict = gate.evaluate(
            measurement: try measurement(1.0, scenario: scenario),
            scenario: scenario,
            baseline: nil,
            environment: environment
        )
        XCTAssertEqual(verdict.status, .baselineRequired)
        XCTAssertTrue(verdict.isBlocking)
    }

    func testUngatedBaselineNeverBlocks() throws {
        let scenario = scenario()
        let verdict = PerformanceGate().evaluate(
            measurement: try measurement(10, scenario: scenario),
            scenario: scenario,
            baseline: baseline(1, scenario: scenario, gateEnabled: false),
            environment: environment
        )
        XCTAssertEqual(verdict.status, .baselineNotGated)
        XCTAssertFalse(verdict.isBlocking)
    }

    func testEnvironmentMismatchDoesNotCompare() throws {
        let scenario = scenario()
        let verdict = PerformanceGate().evaluate(
            measurement: try measurement(10, scenario: scenario),
            scenario: scenario,
            baseline: baseline(1, scenario: scenario, environmentID: "other"),
            environment: environment
        )
        XCTAssertEqual(verdict.status, .environmentMismatch)
    }

    func testTooFewSamplesBlocksBeforeComparing() throws {
        let scenario = scenario(minimumSamples: 8)
        let verdict = PerformanceGate().evaluate(
            measurement: try measurement(0.1, scenario: scenario, count: 3),
            scenario: scenario,
            baseline: baseline(0.1, scenario: scenario),
            environment: environment
        )
        XCTAssertEqual(verdict.status, .insufficientSamples)
        XCTAssertTrue(verdict.isBlocking)
    }

    func testInvalidMeasurementIsRejected() throws {
        let scenario = scenario()
        let other = try PerformanceMeasurement(
            scenarioID: "different",
            unit: .seconds,
            values: [1]
        )
        let verdict = PerformanceGate().evaluate(
            measurement: other,
            scenario: scenario,
            baseline: baseline(1, scenario: scenario),
            environment: environment
        )
        XCTAssertEqual(verdict.status, .invalidMeasurement)
        XCTAssertTrue(verdict.isBlocking)
    }

    func testNoiseFloorOnlyIgnoresTinyAbsoluteDeltas() throws {
        let scenario = scenario(noiseFloor: 0.005)
        let baselineEntry = baseline(0.025, scenario: scenario)

        // 15 % slower, but only 3.75 ms on a 25 ms frame: below the floor.
        let tiny = try measurement(0.02875, scenario: scenario)
        XCTAssertEqual(
            PerformanceGate().evaluate(
                measurement: tiny,
                scenario: scenario,
                baseline: baselineEntry,
                environment: environment
            ).status,
            .passed
        )

        // 30 % slower and 7.5 ms: above both the relative and absolute rules.
        let large = try measurement(0.0325, scenario: scenario)
        XCTAssertEqual(
            PerformanceGate().evaluate(
                measurement: large,
                scenario: scenario,
                baseline: baselineEntry,
                environment: environment
            ).status,
            .regression
        )
    }

    func testContractBudgetCanBeDisabledForDebugCI() throws {
        let scenario = scenario(id: "unit.budget", target: 1.5)
        let gate = PerformanceGate(
            configuration: PerformanceGateConfiguration(enforceContractBudget: false)
        )
        let verdict = gate.evaluate(
            measurement: try measurement(1.6, scenario: scenario),
            scenario: scenario,
            baseline: baseline(1.6, scenario: scenario),
            environment: environment
        )
        XCTAssertEqual(verdict.status, .passed)
    }

    func testMedianRegressionStatisticIgnoresASingleTailOutlier() throws {
        let scenario = PerformanceScenario(
            id: "unit.median",
            displayName: "Median",
            unit: .seconds,
            direction: .lowerIsBetter,
            regressionStatistic: .p50,
            minimumSamples: 5,
            noiseFloor: 0,
            method: "unit test"
        )
        let baselineEntry = baseline(0.030, scenario: scenario)

        // Median is 30 ms; one 50 ms scheduler hiccup must not block.
        let withOutlier = try PerformanceMeasurement(
            scenarioID: scenario.id,
            unit: .seconds,
            values: [0.030, 0.030, 0.030, 0.030, 0.030, 0.050]
        )
        let outlierVerdict = PerformanceGate().evaluate(
            measurement: withOutlier,
            scenario: scenario,
            baseline: baselineEntry,
            environment: environment
        )
        XCTAssertEqual(outlierVerdict.status, .passed)
        XCTAssertEqual(outlierVerdict.statistic, .p50)
        XCTAssertEqual(outlierVerdict.measuredValue, 0.030)

        // A real 13 % median regression still blocks.
        let regression = try PerformanceMeasurement(
            scenarioID: scenario.id,
            unit: .seconds,
            values: [0.034, 0.034, 0.034, 0.034, 0.034]
        )
        XCTAssertEqual(
            PerformanceGate().evaluate(
                measurement: regression,
                scenario: scenario,
                baseline: baselineEntry,
                environment: environment
            ).status,
            .regression
        )
    }
}
