import Foundation
import StyleToneCore
import XCTest
@testable import StyleToneGeometry

/// Performance checks for the background constraint.
///
/// The CI runner is a debug build on a paravirtual GPU; the numbers are a
/// regression signal, not a device benchmark. The strict budget is opt-in via
/// `ST_BACKGROUND_PERF_STRICT=1` (same convention as WP-06).
final class BackgroundProtectionPerformanceTests: XCTestCase {
    func testConstraintWith12MegapixelEdgeMask() throws {
        let size = PixelSize(width: 4032, height: 3024)
        let edgeMask = try makeLargeEdgeMask(size: size)
        let analysis = BackgroundTestSupport.analysis(size: size, edgeMask: edgeMask)
        let field = try BackgroundTestSupport.horizontalWaveField(
            dimension: 64,
            amplitude: 0.02
        )
        let constraint = BackgroundWarpConstraint()

        // Warm-up.
        var warmup = field
        try constraint.constrain(&warmup, analysis: analysis)

        let clock = ContinuousClock()
        var samples: [Double] = []
        let runs = 6
        for _ in 0 ..< runs {
            var copy = field
            let start = clock.now
            try constraint.constrain(&copy, analysis: analysis)
            let elapsed = clock.now - start
            let milliseconds = Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
            samples.append(milliseconds)
        }
        let sorted = samples.sorted()
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        print(
            "BACKGROUND_CONSTRAINT_PERF grid=64 mask=4032x3024 "
                + "p50_ms=\(String(format: "%.2f", p50)) "
                + "p95_ms=\(String(format: "%.2f", p95)) "
                + "runs=\(runs)"
        )

        XCTAssertLessThan(p95, 2_000, "the constraint must not hang the frame")
        if ProcessInfo.processInfo.environment["ST_BACKGROUND_PERF_STRICT"] == "1" {
            XCTAssertLessThan(p95, 400, "strict debug-build budget")
        }
    }

    /// Builds a 12 MP edge mask with a regular line grid without reading an
    /// image. Only a few hundred thousand pixels are written.
    private func makeLargeEdgeMask(size: PixelSize) throws -> MaskBuffer {
        var bytes = [UInt8](repeating: 0, count: size.width * size.height)
        let thickness = 6
        let verticals = [0.20, 0.35, 0.50, 0.65, 0.80]
        let horizontals = [0.15, 0.40, 0.65, 0.90]

        for fraction in verticals {
            let center = Int(fraction * Double(size.width))
            let low = max(0, center - thickness / 2)
            let high = min(size.width, low + thickness)
            for y in 0 ..< size.height {
                let row = y * size.width
                for x in low ..< high {
                    bytes[row + x] = 255
                }
            }
        }
        for fraction in horizontals {
            let center = Int(fraction * Double(size.height))
            let low = max(0, center - thickness / 2)
            let high = min(size.height, low + thickness)
            for y in low ..< high {
                let row = y * size.width
                for x in 0 ..< size.width {
                    bytes[row + x] = 255
                }
            }
        }
        return try MaskBuffer(
            width: size.width,
            height: size.height,
            bytes: Data(bytes)
        )
    }
}
