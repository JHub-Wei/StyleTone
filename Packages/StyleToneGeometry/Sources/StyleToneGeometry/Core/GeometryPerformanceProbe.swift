import Foundation

/// Timing samples for one geometry operation.
///
/// The probe deliberately returns data instead of asserting a budget. Tests and
/// CI compare ``p95Seconds`` against their own threshold, because absolute
/// device performance is not a CI invariant (contracts §7.1).
public struct GeometryPerformanceSample: Sendable, Equatable, Codable {
    /// Operation name, e.g. `"geometry.preview.1080p"`.
    public let operation: String
    /// Backend identifier, e.g. `"geometry.metal"`.
    public let backend: String
    /// Mesh vertices per axis (32 preview, 64 export).
    public let gridDimension: Int
    /// Rendered frame size.
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Number of measured iterations.
    public let iterations: Int
    /// Individual measured durations in seconds.
    public let durationsSeconds: [Double]
    public let meanSeconds: Double
    public let p50Seconds: Double
    public let p95Seconds: Double

    public init(
        operation: String,
        backend: String,
        gridDimension: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        durationsSeconds: [Double]
    ) throws {
        guard !durationsSeconds.isEmpty,
              durationsSeconds.allSatisfy({ $0.isFinite && $0 >= 0 })
        else {
            throw GeometryError.invalidMeasurement
        }
        let sorted = durationsSeconds.sorted()
        self.operation = operation
        self.backend = backend
        self.gridDimension = gridDimension
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.iterations = durationsSeconds.count
        self.durationsSeconds = durationsSeconds
        self.meanSeconds = durationsSeconds.reduce(0, +) / Double(durationsSeconds.count)
        self.p50Seconds = Self.percentile(sorted, fraction: 0.50)
        self.p95Seconds = Self.percentile(sorted, fraction: 0.95)
    }

    /// Frames per second implied by the p95 duration.
    public var p95FramesPerSecond: Double {
        p95Seconds > 0 ? 1 / p95Seconds : .infinity
    }

    /// One-line CI-friendly summary.
    public var summary: String {
        let timings = String(
            format: "mean=%.4fs p50=%.4fs p95=%.4fs p95fps=%.1f",
            meanSeconds,
            p50Seconds,
            p95Seconds,
            p95FramesPerSecond
        )
        return "\(operation) backend=\(backend) "
            + "grid=\(gridDimension)x\(gridDimension) "
            + "size=\(pixelWidth)x\(pixelHeight) n=\(iterations) \(timings)"
    }

    /// Sorted nearest-rank percentile.
    public static func percentile(_ sorted: [Double], fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        let rank = Int((clamped * Double(sorted.count)).rounded(.up))
        let index = min(max(rank - 1, 0), sorted.count - 1)
        return sorted[index]
    }
}

/// Small synchronous timing harness used by the geometry tests and by the
/// preview debug HUD. It does not allocate GPU resources itself; the closure
/// performs the real work.
public enum GeometryPerformanceProbe {
    /// Measures a synchronous operation with warm-up iterations.
    ///
    /// - Parameters:
    ///   - operation: Stable operation name for the report.
    ///   - backend: Backend identifier of the object under test.
    ///   - gridDimension: Mesh density used by the operation.
    ///   - pixelSize: Frame size used by the operation.
    ///   - iterations: Measured iterations, must be positive.
    ///   - warmUpIterations: Unmeasured warm-up iterations.
    ///   - body: Operation to time.
    public static func measure(
        operation: String,
        backend: String,
        gridDimension: Int,
        pixelSize: PixelSize,
        iterations: Int = 10,
        warmUpIterations: Int = 3,
        _ body: () throws -> Void
    ) throws -> GeometryPerformanceSample {
        guard iterations > 0, warmUpIterations >= 0 else {
            throw GeometryError.invalidMeasurement
        }
        for _ in 0 ..< warmUpIterations {
            try body()
        }
        let clock = ContinuousClock()
        var durations: [Double] = []
        durations.reserveCapacity(iterations)
        for _ in 0 ..< iterations {
            let start = clock.now
            try body()
            let duration = clock.now - start
            let components = duration.components
            durations.append(
                Double(components.seconds)
                    + Double(components.attoseconds) / 1_000_000_000_000_000_000
            )
        }
        return try GeometryPerformanceSample(
            operation: operation,
            backend: backend,
            gridDimension: gridDimension,
            pixelWidth: pixelSize.width,
            pixelHeight: pixelSize.height,
            durationsSeconds: durations
        )
    }

    /// Budget used by the preview harness: 1080p at 30 fps (p95 frame time).
    public static let previewFrameBudgetSeconds = 1.0 / 30.0
}
