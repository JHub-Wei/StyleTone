import Foundation
import Metal
import PerformanceKit
import StyleToneCore
import StyleToneGeometry
import XCTest

/// 1080p warp frame budget on the Metal backend.
///
/// The measured path is `renderTexture` without a CPU readback, which is the
/// interactive preview path. WP-06 records the same baseline; WP-24 adds the
/// 10 % regression gate and the device strict budget switch.
final class WarpFramePerformanceTests: XCTestCase {
    func test1080pPreviewFrame() throws {
        guard let backend = MetalGeometryWarp.makeIfAvailable() else {
            throw XCTSkip("Metal device unavailable on this runner")
        }

        let scenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "preview.frameTime")
        )
        let session = try PerformanceSession(source: "WarpFramePerformanceTests")
        defer { session.finish(test: self) }

        let image = try PerformanceFixtures.gradientImage(
            size: PixelSize(width: 1_920, height: 1_080)
        )
        let field = try makeSyntheticWarpField(dimension: 32)
        let configuration = GeometryWarpConfiguration(
            quality: .preview,
            allowsIdentityShortcut: false
        )

        // 20 samples so the nearest-rank p95 is the second-slowest frame, not
        // the single worst frame. The 8-sample version was too sensitive to one
        // CI scheduler hiccup (a 55 ms outlier in an otherwise 30 ms run).
        let measurement = try PerformanceClock.measure(
            scenario: scenario,
            iterations: 20,
            warmUpIterations: 5
        ) {
            _ = try backend.renderTexture(
                image,
                field: field,
                configuration: configuration
            )
        }

        session.record(
            measurement,
            scenario: scenario,
            notes: "backend=\(backend.identifier) device=\(backend.deviceName) "
                + "\(measurement.fpsDescription)"
        )

        if PerformanceTestProfile.enforcesContractBudget {
            XCTAssertLessThanOrEqual(
                measurement.p95,
                1.0 / 30.0,
                "1080p preview p95 \(measurement.p95)s misses 30 fps: "
                    + measurement.summary
            )
        }
    }

    /// A CPU fallback is a correctness path, not an interactive target. This
    /// check fails if a device without Metal silently lost the GPU backend.
    func testPreviewBackendIsGPUAcceleratedWhenAvailable() async {
        guard MetalGeometryWarp.makeIfAvailable() != nil else {
            return
        }
        let engine = makeSyntheticGeometryEngine(quality: .preview)
        let isGPU = await engine.isGPUAccelerated
        let identifier = await engine.backendIdentifier
        XCTAssertTrue(isGPU, "preview should use the Metal backend when available")
        XCTAssertFalse(identifier.isEmpty)
    }
}
