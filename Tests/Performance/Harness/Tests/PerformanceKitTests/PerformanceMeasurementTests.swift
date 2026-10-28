import XCTest
@testable import PerformanceKit

final class PerformanceMeasurementTests: XCTestCase {
    func testNearestRankPercentile() {
        let values: [Double] = [1, 2, 3, 4, 5]
        XCTAssertEqual(PerformanceStatistics.percentile(values, fraction: 0.5), 3)
        XCTAssertEqual(PerformanceStatistics.percentile(values, fraction: 0.95), 5)
        XCTAssertEqual(PerformanceStatistics.percentile([], fraction: 0.5), 0)
        XCTAssertEqual(PerformanceStatistics.percentile(values, fraction: -1), 1)
        XCTAssertEqual(PerformanceStatistics.percentile(values, fraction: 2), 5)
    }

    func testMeasurementComputesStats() throws {
        let measurement = try PerformanceMeasurement(
            scenarioID: "unit.test",
            unit: .seconds,
            values: [0.02, 0.01, 0.03, 0.04, 0.05]
        )
        XCTAssertEqual(measurement.sampleCount, 5)
        XCTAssertEqual(measurement.p50, 0.03, accuracy: 1e-12)
        XCTAssertEqual(measurement.p95, 0.05, accuracy: 1e-12)
        XCTAssertEqual(measurement.minimum, 0.01, accuracy: 1e-12)
        XCTAssertEqual(measurement.maximum, 0.05, accuracy: 1e-12)
        XCTAssertEqual(measurement.mean, 0.03, accuracy: 1e-12)
    }

    func testEmptyAndNegativeSamplesAreRejected() {
        XCTAssertThrowsError(
            try PerformanceMeasurement(scenarioID: "unit.test", unit: .seconds, values: [])
        )
        XCTAssertThrowsError(
            try PerformanceMeasurement(scenarioID: "unit.test", unit: .seconds, values: [-1])
        )
        XCTAssertThrowsError(
            try PerformanceMeasurement(
                scenarioID: "unit.test",
                unit: .seconds,
                values: [.infinity]
            )
        )
    }

    func testFramesPerSecondFromP95() throws {
        let measurement = try PerformanceMeasurement(
            scenarioID: "preview.frameTime",
            unit: .seconds,
            values: [0.025]
        )
        XCTAssertEqual(measurement.p95FramesPerSecond, 40, accuracy: 1e-9)
    }

    func testSynchronousClockRecordsRequestedIterations() throws {
        let scenario = PerformanceScenario(
            id: "unit.clock",
            displayName: "Clock",
            unit: .seconds,
            direction: .lowerIsBetter,
            minimumSamples: 1,
            method: "test"
        )
        var counter = 0
        let measurement = try PerformanceClock.measure(
            scenario: scenario,
            iterations: 3,
            warmUpIterations: 1
        ) {
            counter += 1
        }
        XCTAssertEqual(counter, 4)
        XCTAssertEqual(measurement.sampleCount, 3)
    }

    func testAsynchronousClockRecordsRequestedIterations() async throws {
        let scenario = PerformanceScenario(
            id: "unit.asyncClock",
            displayName: "Async clock",
            unit: .seconds,
            direction: .lowerIsBetter,
            minimumSamples: 1,
            method: "test"
        )
        var counter = 0
        let measurement = try await PerformanceClock.measureAsync(
            scenario: scenario,
            iterations: 2,
            warmUpIterations: 1
        ) {
            counter += 1
        }
        XCTAssertEqual(counter, 3)
        XCTAssertEqual(measurement.sampleCount, 2)
    }
}
