import StyleToneCore
import XCTest
@testable import StyleToneGeometry

final class GeometryPerformanceProbeTests: XCTestCase {
    func testProbeRecordsAllIterations() throws {
        let sample = try GeometryPerformanceProbe.measure(
            operation: "test.empty",
            backend: "test",
            gridDimension: 32,
            pixelSize: PixelSize(width: 16, height: 16),
            iterations: 5,
            warmUpIterations: 1
        ) {
            // Deliberately empty: the probe must handle very short operations.
        }

        XCTAssertEqual(sample.iterations, 5)
        XCTAssertEqual(sample.durationsSeconds.count, 5)
        XCTAssertEqual(sample.operation, "test.empty")
        XCTAssertEqual(sample.pixelWidth, 16)
        XCTAssertGreaterThanOrEqual(sample.meanSeconds, 0)
        XCTAssertGreaterThanOrEqual(sample.p95Seconds, sample.p50Seconds)
    }

    func testPercentileUsesNearestRank() {
        let values = [1.0, 2.0, 3.0, 4.0, 5.0]
        XCTAssertEqual(GeometryPerformanceSample.percentile(values, fraction: 0.5), 3.0)
        XCTAssertEqual(GeometryPerformanceSample.percentile(values, fraction: 0.95), 5.0)
        XCTAssertEqual(GeometryPerformanceSample.percentile([], fraction: 0.5), 0)
    }

    func testInvalidMeasurementIsRejected() {
        XCTAssertThrowsError(
            try GeometryPerformanceSample(
                operation: "invalid",
                backend: "test",
                gridDimension: 32,
                pixelWidth: 1,
                pixelHeight: 1,
                durationsSeconds: [-1]
            )
        ) { error in
            XCTAssertEqual(error as? GeometryError, .invalidMeasurement)
        }
        XCTAssertThrowsError(
            try GeometryPerformanceProbe.measure(
                operation: "invalid",
                backend: "test",
                gridDimension: 32,
                pixelSize: PixelSize(width: 1, height: 1),
                iterations: 0
            ) {}
        ) { error in
            XCTAssertEqual(error as? GeometryError, .invalidMeasurement)
        }
    }

    func testSummaryContainsFramesPerSecond() throws {
        let sample = try GeometryPerformanceSample(
            operation: "geometry.preview.1080p",
            backend: "geometry.metal",
            gridDimension: 32,
            pixelWidth: 1920,
            pixelHeight: 1080,
            durationsSeconds: [0.02, 0.02, 0.02]
        )
        XCTAssertEqual(sample.p95FramesPerSecond, 50, accuracy: 0.001)
        XCTAssertTrue(sample.summary.contains("p95fps=50.0"))
    }
}
