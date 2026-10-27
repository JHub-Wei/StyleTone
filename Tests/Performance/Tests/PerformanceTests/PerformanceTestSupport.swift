import CoreGraphics
import Foundation
import PerformanceKit
import StyleToneCore
import StyleToneGeometry
import StyleToneUI
import XCTest

// MARK: - Synthetic geometry

/// A deterministic non-identity pass for the warp performance tests.
///
/// It is intentionally trivial: the test measures the engine's mesh build and
/// renderer, not a production face/body pass. The outer ring is pinned so the
/// field satisfies the boundary invariant.
struct SyntheticShiftPass: GeometryPass {
    let identifier = "performance.syntheticShift"
    let offsetX: Float
    let offsetY: Float

    init(offsetX: Float = 0.012, offsetY: Float = 0.008) {
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    func contribute(
        to field: inout WarpField,
        analysis: PortraitAnalysis,
        parameters: GeometryParameters
    ) throws {
        for y in 0 ..< field.height {
            for x in 0 ..< field.width {
                let edge = min(x, y, field.width - 1 - x, field.height - 1 - y)
                let feather = min(Float(edge) / 3, 1)
                guard feather > 0 else { continue }
                field.addOffset(
                    SIMD2<Float>(offsetX * feather, offsetY * feather),
                    x: x,
                    y: y
                )
            }
        }
    }
}

/// Creates a non-zero feathered field at the requested grid density.
func makeSyntheticWarpField(
    dimension: Int,
    offsetX: Float = 0.012,
    offsetY: Float = 0.008
) throws -> WarpField {
    var field = try WarpField(width: dimension, height: dimension)
    let pass = SyntheticShiftPass(offsetX: offsetX, offsetY: offsetY)
    try pass.contribute(
        to: &field,
        analysis: .empty(imageSize: PixelSize(width: 1, height: 1)),
        parameters: .neutral
    )
    return field
}

/// Engine used by the slider-response and export tests.
func makeSyntheticGeometryEngine(quality: GeometryQuality) -> GeometryRenderingEngine {
    GeometryRenderingEngine(
        passes: [
            GeometryPassEntry(
                phase: .face,
                pass: SyntheticShiftPass()
            )
        ],
        configuration: GeometryWarpConfiguration(quality: quality)
    )
}

// MARK: - Preview scaler counting

/// A scaler that counts real invocations and delegates to the production
/// CoreGraphics scaler.
final class CountingPreviewScaler: EditorPreviewScaling, @unchecked Sendable {
    private let lock = NSLock()
    private let scaler = CoreGraphicsPreviewScaler()
    private var invocations = 0

    func preparePreview(
        image: ImageAsset,
        analysis: PortraitAnalysis,
        maximumLongEdge: Int
    ) throws -> EditorPreviewContext {
        lock.lock()
        invocations += 1
        lock.unlock()
        return try scaler.preparePreview(
            image: image,
            analysis: analysis,
            maximumLongEdge: maximumLongEdge
        )
    }

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocations
    }
}

// MARK: - Async waiting

/// Yields until the pipeline reports an active job or the budget expires.
@MainActor
func waitForActiveRender(
    _ pipeline: EditorRenderPipeline,
    attempts: Int = 10_000
) async -> Bool {
    for _ in 0 ..< attempts {
        if pipeline.activeQuality != nil {
            return true
        }
        await Task.yield()
    }
    return false
}

// MARK: - Measurement helpers

/// Thread-safe wrapper around ``MemoryPeakTracker`` so async measurement
/// closures can sample memory without mutating a captured struct.
final class LockedMemoryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var tracker: MemoryPeakTracker

    init(reader: any MemoryFootprintReading) {
        self.tracker = MemoryPeakTracker(reader: reader)
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        try tracker.start()
    }

    func sample() throws {
        lock.lock()
        defer { lock.unlock() }
        try tracker.sample()
    }

    func measurement(
        scenarioID: String,
        absolute: Bool = false
    ) throws -> PerformanceMeasurement {
        lock.lock()
        defer { lock.unlock() }
        return try tracker.measurement(scenarioID: scenarioID, absolute: absolute)
    }

    var peakMegabytes: Double {
        lock.lock()
        defer { lock.unlock() }
        return tracker.peakMegabytes
    }

    var peakDeltaMegabytes: Double {
        lock.lock()
        defer { lock.unlock() }
        return tracker.peakDeltaMegabytes
    }
}

extension PerformanceMeasurement {
    /// Converts the p95 frame time to fps for report notes.
    var fpsDescription: String {
        guard unit == .seconds, p95 > 0 else { return "n/a" }
        return String(format: "%.1f fps", 1 / p95)
    }
}

extension PerformanceSession {
    /// Records a measurement and asserts the contract budget immediately.
    ///
    /// The gate handles the regression comparison; this helper adds the
    /// contract assertion that must hold on every run, including debug CI.
    @discardableResult
    func recordAndAssertContract(
        _ measurement: PerformanceMeasurement,
        scenario: PerformanceScenario,
        contract: Double,
        notes: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> PerformanceVerdict {
        let verdict = record(measurement, scenario: scenario, notes: notes)
        XCTAssertLessThanOrEqual(
            measurement.p95,
            contract,
            "\(scenario.id) p95 \(measurement.p95) exceeds contract \(contract): "
                + measurement.summary,
            file: file,
            line: line
        )
        return verdict
    }
}
