import XCTest
@testable import PerformanceKit

final class MemoryFootprintTests: XCTestCase {
    private final class SequenceBox: @unchecked Sendable {
        var values: [UInt64]
        var index = 0

        init(_ values: [UInt64]) {
            self.values = values
        }

        func next() -> UInt64 {
            defer { index += 1 }
            if index < values.count {
                return values[index]
            }
            return values.last ?? 0
        }
    }

    func testTrackerUsesPeakMinusBaseline() throws {
        let box = SequenceBox([100_000_000, 120_000_000, 150_000_000, 140_000_000])
        let reader = ClosureMemoryFootprintReader {
            MemoryFootprint(bytes: box.next())
        }
        var tracker = MemoryPeakTracker(reader: reader)
        try tracker.start()
        try tracker.sample()
        try tracker.sample()
        try tracker.sample()

        XCTAssertEqual(tracker.peakDeltaMegabytes, 50, accuracy: 0.001)
        XCTAssertEqual(tracker.peakMegabytes, 150, accuracy: 0.001)
        let measurement = try tracker.measurement(scenarioID: "preview.memoryPeak")
        XCTAssertEqual(measurement.p95, 50, accuracy: 0.001)
    }

    func testBaselineCaptureStartsAtZeroDelta() throws {
        let reader = ClosureMemoryFootprintReader {
            MemoryFootprint(bytes: 42_000_000)
        }
        var tracker = MemoryPeakTracker(reader: reader)
        try tracker.start()
        XCTAssertEqual(tracker.peakDeltaMegabytes, 0, accuracy: 0.001)
        XCTAssertEqual(tracker.peakMegabytes, 42, accuracy: 0.001)
    }

    func testMeasurementCanUseAbsolutePeak() throws {
        let reader = ClosureMemoryFootprintReader {
            MemoryFootprint(bytes: 250_000_000)
        }
        var tracker = MemoryPeakTracker(reader: reader)
        try tracker.start()
        try tracker.sample()
        let measurement = try tracker.measurement(
            scenarioID: "preview.memoryPeak",
            absolute: true
        )
        XCTAssertEqual(measurement.p95, 250, accuracy: 0.001)
    }

    func testUnsupportedReaderThrows() {
        var tracker = MemoryPeakTracker(reader: UnsupportedMemoryFootprintReader())
        XCTAssertThrowsError(try tracker.start()) { error in
            guard case PerformanceKitError.memoryUnavailable = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}
