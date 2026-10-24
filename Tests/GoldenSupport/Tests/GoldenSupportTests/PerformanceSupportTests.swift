import XCTest
@testable import GoldenSupport

final class PerformanceSupportTests: XCTestCase {
    func testSyncMeasureRunsWarmupAndIterations() throws {
        var callCount = 0
        let measurement = try PerformanceHarness.measure(
            name: "counter",
            iterations: 4,
            warmupIterations: 2
        ) {
            callCount += 1
        }
        XCTAssertEqual(callCount, 6)
        XCTAssertEqual(measurement.iterations, 4)
        XCTAssertEqual(measurement.durationsSeconds.count, 4)
        XCTAssertGreaterThanOrEqual(measurement.p95Seconds, measurement.p50Seconds)
        XCTAssertLessThanOrEqual(measurement.minSeconds, measurement.maxSeconds)
    }

    func testAsyncMeasure() async throws {
        var callCount = 0
        let measurement = try await PerformanceHarness.measureAsync(
            name: "async",
            iterations: 3,
            warmupIterations: 1
        ) {
            callCount += 1
            await Task.yield()
        }
        XCTAssertEqual(callCount, 4)
        XCTAssertEqual(measurement.iterations, 3)
        XCTAssertTrue(measurement.meanSeconds >= 0)
    }

    func testInvalidHarnessArgumentsThrow() {
        XCTAssertThrowsError(
            try PerformanceHarness.measure(name: "bad", iterations: 0) {}
        )
        XCTAssertThrowsError(
            try PerformanceHarness.measure(name: "bad", iterations: 1, warmupIterations: -1) {}
        )
    }

    func testMeasurementStatistics() throws {
        let measurement = try PerformanceMeasurement(
            name: "stats",
            durationsSeconds: [0.1, 0.2, 0.3, 0.4, 0.5]
        )
        XCTAssertEqual(measurement.meanSeconds, 0.3, accuracy: 1e-12)
        XCTAssertEqual(measurement.minSeconds, 0.1, accuracy: 1e-12)
        XCTAssertEqual(measurement.maxSeconds, 0.5, accuracy: 1e-12)
        XCTAssertEqual(measurement.p50Seconds, 0.3, accuracy: 1e-12)
        XCTAssertEqual(measurement.p95Seconds, 0.5, accuracy: 1e-12)
        XCTAssertEqual(measurement.iterations, 5)
    }

    func testEmptyMeasurementThrows() {
        XCTAssertThrowsError(try PerformanceMeasurement(name: "empty", durationsSeconds: []))
        XCTAssertThrowsError(
            try PerformanceMeasurement(name: "negative", durationsSeconds: [-1])
        )
    }

    func testBudgetVerdict() throws {
        let budget = PerformanceBudget(id: "budget", targetSeconds: 1.0, allowanceFraction: 0.1)
        XCTAssertEqual(budget.limitSeconds, 1.1, accuracy: 1e-12)

        let passing = try PerformanceMeasurement(
            name: "fast",
            durationsSeconds: [0.5, 0.6, 0.7, 0.8, 1.0]
        )
        XCTAssertTrue(budget.verdict(for: passing).passed)

        let failing = try PerformanceMeasurement(
            name: "slow",
            durationsSeconds: [1.0, 1.2, 1.3, 1.4, 1.5]
        )
        let verdict = budget.verdict(for: failing)
        XCTAssertFalse(verdict.passed)
        XCTAssertTrue(verdict.message.contains("budget"))
    }

    func testDefaultBudgetsMatchContracts() {
        XCTAssertEqual(PerformanceBudget.previewFirstFrame.targetSeconds, 1.5, accuracy: 1e-12)
        XCTAssertEqual(PerformanceBudget.learningFivePairs.targetSeconds, 90, accuracy: 1e-12)
        XCTAssertEqual(PerformanceBudget.export12MP.targetSeconds, 6, accuracy: 1e-12)
        XCTAssertEqual(PerformanceBudget.sliderResponse.targetSeconds, 0.1, accuracy: 1e-12)
        XCTAssertEqual(
            PerformanceBudget.poseWarpFrame.targetSeconds,
            1.0 / 30.0,
            accuracy: 1e-12
        )
    }

    func testDurationConversion() {
        XCTAssertEqual(PerformanceHarness.seconds(.milliseconds(250)), 0.25, accuracy: 1e-9)
        XCTAssertEqual(PerformanceHarness.seconds(.seconds(2)), 2, accuracy: 1e-9)
        XCTAssertEqual(
            PerformanceHarness.seconds(.microseconds(1500)),
            0.0015,
            accuracy: 1e-12
        )
    }

    func testMeasurementCodableRoundTrip() throws {
        let measurement = try PerformanceMeasurement(
            name: "codable",
            durationsSeconds: [0.01, 0.02, 0.03]
        )
        let data = try JSONEncoder().encode(measurement)
        let decoded = try JSONDecoder().decode(PerformanceMeasurement.self, from: data)
        XCTAssertEqual(decoded, measurement)
    }
}
