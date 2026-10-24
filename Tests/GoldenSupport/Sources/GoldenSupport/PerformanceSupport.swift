import Foundation

/// One timing sample set for a named operation.
///
/// The harness deliberately does **not** assert: callers compare `p95Seconds`
/// against a ``PerformanceBudget`` so the failure message stays in the test
/// where the budget is owned. CI only checks thresholds; it never asserts
/// absolute device performance (contracts §7.1).
public struct PerformanceMeasurement: Sendable, Codable, Equatable {
    public let name: String
    public let iterations: Int
    public let durationsSeconds: [Double]
    public let meanSeconds: Double
    public let p50Seconds: Double
    public let p95Seconds: Double
    public let minSeconds: Double
    public let maxSeconds: Double

    public init(name: String, durationsSeconds: [Double]) throws {
        guard !durationsSeconds.isEmpty else {
            throw GoldenSupportError.invalidConfiguration(reason: "measurement has no samples")
        }
        guard durationsSeconds.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw GoldenSupportError.invalidConfiguration(
                reason: "measurement contains a negative or non-finite duration"
            )
        }
        let sorted = durationsSeconds.sorted()
        self.name = name
        self.iterations = durationsSeconds.count
        self.durationsSeconds = durationsSeconds
        self.meanSeconds = durationsSeconds.reduce(0, +) / Double(durationsSeconds.count)
        self.p50Seconds = PerformanceStatistics.percentile(sorted, fraction: 0.50)
        self.p95Seconds = PerformanceStatistics.percentile(sorted, fraction: 0.95)
        self.minSeconds = sorted[0]
        self.maxSeconds = sorted[sorted.count - 1]
    }

    public var summary: String {
        "\(name): n=\(iterations) mean=\(PerformanceStatistics.format(meanSeconds))s "
            + "p50=\(PerformanceStatistics.format(p50Seconds))s "
            + "p95=\(PerformanceStatistics.format(p95Seconds))s "
            + "max=\(PerformanceStatistics.format(maxSeconds))s"
    }
}

/// A performance target from contracts §10, expressed in seconds.
public struct PerformanceBudget: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let targetSeconds: Double
    /// Extra headroom before a measurement counts as a regression (0.10 = 10%).
    public let allowanceFraction: Double

    public init(id: String, targetSeconds: Double, allowanceFraction: Double = 0.1) {
        self.id = id
        self.targetSeconds = max(0, targetSeconds)
        self.allowanceFraction = max(0, allowanceFraction)
    }

    public var limitSeconds: Double { targetSeconds * (1 + allowanceFraction) }

    public func verdict(for measurement: PerformanceMeasurement) -> PerformanceVerdict {
        let passed = measurement.p95Seconds <= limitSeconds
        return PerformanceVerdict(
            budgetID: id,
            measuredP95Seconds: measurement.p95Seconds,
            limitSeconds: limitSeconds,
            passed: passed,
            message: "\(id): p95 \(PerformanceStatistics.format(measurement.p95Seconds))s "
                + "\(passed ? "<=" : ">") limit \(PerformanceStatistics.format(limitSeconds))s "
                + "(target \(PerformanceStatistics.format(targetSeconds))s, "
                + "allowance \(PerformanceStatistics.format(allowanceFraction * 100))%)"
        )
    }

    // Budgets from contracts §10. Values are targets for a release build on the
    // reference device; CI checks regressions with the allowance applied.
    public static let previewFirstFrame = PerformanceBudget(
        id: "preview.firstFrame",
        targetSeconds: 1.5
    )
    public static let poseWarpFrame = PerformanceBudget(
        id: "preview.poseWarpFrame",
        targetSeconds: 1.0 / 30.0
    )
    public static let sliderResponse = PerformanceBudget(
        id: "preview.sliderResponse",
        targetSeconds: 0.1
    )
    public static let learningFivePairs = PerformanceBudget(
        id: "learning.fivePairs",
        targetSeconds: 90
    )
    public static let export12MP = PerformanceBudget(
        id: "export.12MP",
        targetSeconds: 6
    )
}

/// The pass/fail decision for one measurement against one budget.
public struct PerformanceVerdict: Sendable, Codable, Equatable {
    public let budgetID: String
    public let measuredP95Seconds: Double
    public let limitSeconds: Double
    public let passed: Bool
    public let message: String
}

/// Synchronous and asynchronous timing harness with warm-up iterations and
/// monotonic `ContinuousClock` measurements.
public enum PerformanceHarness {
    /// Measures a synchronous operation.
    ///
    /// - Parameters:
    ///   - name: Test-visible name, e.g. `"warp.1080p"`.
    ///   - iterations: Recorded iterations (default 5).
    ///   - warmupIterations: Unrecorded iterations run first (default 1).
    public static func measure(
        name: String,
        iterations: Int = 5,
        warmupIterations: Int = 1,
        operation: () throws -> Void
    ) throws -> PerformanceMeasurement {
        guard iterations > 0, warmupIterations >= 0 else {
            throw GoldenSupportError.invalidConfiguration(
                reason: "iterations must be > 0 and warm-up iterations >= 0"
            )
        }
        let clock = ContinuousClock()
        for _ in 0..<warmupIterations {
            try operation()
        }
        var durations: [Double] = []
        durations.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = clock.now
            try operation()
            durations.append(seconds(clock.now - start))
        }
        return try PerformanceMeasurement(name: name, durationsSeconds: durations)
    }

    /// Measures an asynchronous operation. Cancellation propagates to the body.
    public static func measureAsync(
        name: String,
        iterations: Int = 5,
        warmupIterations: Int = 1,
        operation: () async throws -> Void
    ) async throws -> PerformanceMeasurement {
        guard iterations > 0, warmupIterations >= 0 else {
            throw GoldenSupportError.invalidConfiguration(
                reason: "iterations must be > 0 and warm-up iterations >= 0"
            )
        }
        let clock = ContinuousClock()
        for _ in 0..<warmupIterations {
            try await operation()
        }
        var durations: [Double] = []
        durations.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = clock.now
            try await operation()
            durations.append(seconds(clock.now - start))
        }
        return try PerformanceMeasurement(name: name, durationsSeconds: durations)
    }

    /// Converts a `Duration` to seconds.
    public static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

/// Shared percentile and formatting helpers (also used by the comparison
/// report so both report formats round the same way).
public enum PerformanceStatistics {
    /// Nearest-rank percentile over an already sorted array, clamped to `0...1`.
    public static func percentile(_ sortedValues: [Double], fraction: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        let rank = Int((clamped * Double(sortedValues.count)).rounded(.up))
        let index = min(max(rank - 1, 0), sortedValues.count - 1)
        return sortedValues[index]
    }

    public static func format(_ seconds: Double) -> String {
        if seconds >= 1 {
            return String(format: "%.3f", seconds)
        }
        if seconds >= 0.001 {
            return String(format: "%.4f", seconds)
        }
        return String(format: "%.6f", seconds)
    }
}
