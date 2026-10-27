import Foundation

/// Errors raised by the performance harness itself.
public enum PerformanceKitError: Error, Sendable, Equatable, LocalizedError {
    case invalidConfiguration(String)
    case invalidMeasurement(String)
    case unsupportedSchemaVersion(Int)
    case duplicateBaseline(scenarioID: String, environmentID: String)
    case invalidBaseline(String)
    case memoryUnavailable(String)
    case reportEncodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(reason):
            return "Invalid performance configuration: \(reason)"
        case let .invalidMeasurement(reason):
            return "Invalid performance measurement: \(reason)"
        case let .unsupportedSchemaVersion(version):
            return "Unsupported performance baseline schema version \(version)."
        case let .duplicateBaseline(scenarioID, environmentID):
            return "Duplicate baseline for \(scenarioID) on \(environmentID)."
        case let .invalidBaseline(reason):
            return "Invalid performance baseline: \(reason)"
        case let .memoryUnavailable(reason):
            return "Memory footprint is unavailable: \(reason)"
        case let .reportEncodingFailed(reason):
            return "Performance report encoding failed: \(reason)"
        }
    }
}

// MARK: - Statistics

/// Shared percentile helpers. Values are sorted once at construction.
public enum PerformanceStatistics {
    /// Nearest-rank percentile over sorted values, clamped to `0...1`.
    public static func percentile(_ sortedValues: [Double], fraction: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        let rank = Int((clamped * Double(sortedValues.count)).rounded(.up))
        let index = min(max(rank - 1, 0), sortedValues.count - 1)
        return sortedValues[index]
    }

    /// Formats seconds/units for a report line.
    public static func format(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.1f", value)
        }
        if value >= 1 {
            return String(format: "%.3f", value)
        }
        if value >= 0.001 {
            return String(format: "%.4f", value)
        }
        return String(format: "%.6f", value)
    }

    /// Converts a `Duration` to seconds.
    public static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

// MARK: - Measurement

/// The recorded samples of one scenario and their p95.
///
/// The p95 is the value the gate compares: contract §10 is written in terms of
/// p95 (or a floor for fps), and p50 alone hides thermal spikes.
public struct PerformanceMeasurement: Codable, Sendable, Equatable {
    public let scenarioID: String
    public let unit: PerformanceUnit
    /// Recorded values in `unit`, in measurement order.
    public let values: [Double]
    public let sampleCount: Int
    public let mean: Double
    public let p50: Double
    public let p95: Double
    public let minimum: Double
    public let maximum: Double

    public init(
        scenarioID: String,
        unit: PerformanceUnit,
        values: [Double]
    ) throws {
        guard !scenarioID.isEmpty else {
            throw PerformanceKitError.invalidMeasurement("scenario identifier is empty")
        }
        guard !values.isEmpty else {
            throw PerformanceKitError.invalidMeasurement("no samples recorded")
        }
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw PerformanceKitError.invalidMeasurement(
                "samples must be finite and non-negative"
            )
        }
        let sorted = values.sorted()
        self.scenarioID = scenarioID
        self.unit = unit
        self.values = values
        self.sampleCount = values.count
        self.mean = values.reduce(0, +) / Double(values.count)
        self.p50 = PerformanceStatistics.percentile(sorted, fraction: 0.50)
        self.p95 = PerformanceStatistics.percentile(sorted, fraction: 0.95)
        self.minimum = sorted[0]
        self.maximum = sorted[sorted.count - 1]
    }

    /// Frames per second implied by ``p95`` when the unit is seconds.
    public var p95FramesPerSecond: Double {
        guard unit == .seconds, p95 > 0 else { return 0 }
        return 1 / p95
    }

    /// One-line report summary.
    public var summary: String {
        "\(scenarioID): n=\(sampleCount) "
            + "mean=\(PerformanceStatistics.format(mean)) "
            + "p50=\(PerformanceStatistics.format(p50)) "
            + "p95=\(PerformanceStatistics.format(p95)) "
            + "\(unit.symbol)"
    }
}

// MARK: - Clock

/// Monotonic timing helper with warm-up iterations.
public enum PerformanceClock {
    /// Measures a synchronous operation.
    public static func measure(
        scenario: PerformanceScenario,
        iterations: Int,
        warmUpIterations: Int = 1,
        operation: () throws -> Void
    ) throws -> PerformanceMeasurement {
        guard iterations > 0 else {
            throw PerformanceKitError.invalidConfiguration("iterations must be > 0")
        }
        guard warmUpIterations >= 0 else {
            throw PerformanceKitError.invalidConfiguration("warm-up iterations must be >= 0")
        }
        for _ in 0 ..< warmUpIterations {
            try operation()
        }
        let clock = ContinuousClock()
        var values: [Double] = []
        values.reserveCapacity(iterations)
        for _ in 0 ..< iterations {
            let start = clock.now
            try operation()
            values.append(PerformanceStatistics.seconds(clock.now - start))
        }
        return try PerformanceMeasurement(
            scenarioID: scenario.id,
            unit: scenario.unit,
            values: values
        )
    }

    /// Measures an asynchronous operation with the same warm-up rules.
    public static func measureAsync(
        scenario: PerformanceScenario,
        iterations: Int,
        warmUpIterations: Int = 1,
        operation: () async throws -> Void
    ) async throws -> PerformanceMeasurement {
        guard iterations > 0 else {
            throw PerformanceKitError.invalidConfiguration("iterations must be > 0")
        }
        guard warmUpIterations >= 0 else {
            throw PerformanceKitError.invalidConfiguration("warm-up iterations must be >= 0")
        }
        for _ in 0 ..< warmUpIterations {
            try await operation()
        }
        let clock = ContinuousClock()
        var values: [Double] = []
        values.reserveCapacity(iterations)
        for _ in 0 ..< iterations {
            let start = clock.now
            try await operation()
            values.append(PerformanceStatistics.seconds(clock.now - start))
        }
        return try PerformanceMeasurement(
            scenarioID: scenario.id,
            unit: scenario.unit,
            values: values
        )
    }
}
