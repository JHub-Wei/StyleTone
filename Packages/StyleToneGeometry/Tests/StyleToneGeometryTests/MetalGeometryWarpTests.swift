#if canImport(Metal)
import CoreGraphics
import Foundation
import GoldenSupport
import Metal
import StyleToneCore
import XCTest
@testable import StyleToneGeometry

final class MetalGeometryWarpTests: XCTestCase {
    private func makeBackend() throws -> MetalGeometryWarp {
        guard let backend = MetalGeometryWarp.makeIfAvailable() else {
            throw XCTSkip("Metal device unavailable on this runner")
        }
        return backend
    }

    private let forcedConfiguration = GeometryWarpConfiguration(
        quality: .preview,
        allowsIdentityShortcut: false
    )

    func testIdentityMeshIsNearExact() throws {
        let backend = try makeBackend()
        let image = try GeometryTestSupport.gradientWithBorder(width: 64, height: 48)
        let field = try WarpField(width: 32, height: 32)

        let output = try backend.warp(
            image,
            field: field,
            configuration: forcedConfiguration
        )
        var thresholds = ImageThresholds.strict
        thresholds.channelTolerance = 1
        thresholds.allowedDifferingPixelRatio = 0.02
        thresholds.maxMeanDeltaE00 = 1.0
        thresholds.maxP95DeltaE00 = 2.0
        thresholds.maxDeltaE00 = 6.0
        thresholds.minSSIM = 0.99
        let report = try ImageComparator.compare(
            expected: image,
            actual: output,
            thresholds: thresholds
        )
        XCTAssertTrue(report.passes, report.summary)
    }

    func testTranslationAtPixelCenters() throws {
        let backend = try makeBackend()
        let image = try GeometryTestSupport.makeImage(width: 64, height: 32) { x, _ in
            let value = UInt8((Double(x) / 63.0 * 255).rounded())
            return RGBA8(red: value, green: value, blue: value)
        }
        let field = try GeometryTestSupport.constantField(
            width: 32,
            height: 32,
            offset: SIMD2<Float>(0.25, 0)
        )
        let output = try backend.warp(
            image,
            field: field,
            configuration: forcedConfiguration
        )
        let source = try PixelBuffer(image: image)
        let warped = try PixelBuffer(image: output)

        for y in [3, 16, 28] {
            XCTAssertEqual(
                Double(warped[48, y].red),
                Double(source[32, y].red),
                accuracy: 2,
                "y=\(y)"
            )
        }
    }

    func testFeatheredBoundaryHasNoBlackFrame() throws {
        let backend = try makeBackend()
        let image = try GeometryTestSupport.gradientWithBorder(width: 64, height: 64)
        let field = try GeometryTestSupport.featheredField(
            width: 32,
            height: 32,
            offset: SIMD2<Float>(0.2, 0.12)
        )
        let output = try backend.warp(
            image,
            field: field,
            configuration: forcedConfiguration
        )
        try GeometryTestSupport.assertNoBlackBorder(output, border: 2)

        let source = try PixelBuffer(image: image)
        let warped = try PixelBuffer(image: output)
        for x in stride(from: 0, to: 64, by: 9) {
            XCTAssertEqual(
                Double(warped[x, 0].red),
                Double(source[x, 0].red),
                accuracy: 3
            )
        }
    }

    func testClampSamplerPreventsEmptyEdges() throws {
        let backend = try makeBackend()
        let image = try GeometryTestSupport.gradientWithBorder(width: 64, height: 64)
        let field = try GeometryTestSupport.constantField(
            width: 32,
            height: 32,
            offset: SIMD2<Float>(0.5, 0.5)
        )
        let output = try backend.warp(
            image,
            field: field,
            configuration: forcedConfiguration
        )
        try GeometryTestSupport.assertNoBlackBorder(output, border: 3)
    }

    func testMetalAndCPURenderAgreeWithinTolerance() throws {
        let backend = try makeBackend()
        let image = try GeometryTestSupport.gradientWithBorder(width: 64, height: 48)
        let field = try GeometryTestSupport.featheredField(
            width: 32,
            height: 32,
            offset: SIMD2<Float>(0.08, 0.04)
        )

        let metalOutput = try backend.warp(
            image,
            field: field,
            configuration: forcedConfiguration
        )
        let cpuOutput = try CPUGeometryWarp().warp(
            image,
            field: field,
            configuration: forcedConfiguration
        )
        var thresholds = ImageThresholds.standard
        thresholds.channelTolerance = 3
        thresholds.allowedDifferingPixelRatio = 0.05
        thresholds.maxMeanDeltaE00 = 2.0
        thresholds.maxP95DeltaE00 = 5.0
        thresholds.maxDeltaE00 = 12.0
        thresholds.minSSIM = 0.98
        let report = try ImageComparator.compare(
            expected: cpuOutput,
            actual: metalOutput,
            thresholds: thresholds
        )
        XCTAssertTrue(report.passes, report.summary)
    }

    func test1080pPreviewAndExportPerformance() throws {
        let backend = try makeBackend()
        let size = PixelSize(width: 1920, height: 1080)
        let image = try GeometryTestSupport.makeImage(
            width: size.width,
            height: size.height
        ) { x, y in
            RGBA8(
                red: UInt8((x * 255) / max(size.width - 1, 1)),
                green: UInt8((y * 255) / max(size.height - 1, 1)),
                blue: 128
            )
        }
        let field = try GeometryTestSupport.featheredField(
            width: 32,
            height: 32,
            offset: SIMD2<Float>(0.02, 0.015)
        )

        let preview = try GeometryPerformanceProbe.measure(
            operation: "geometry.preview.1080p",
            backend: backend.identifier,
            gridDimension: 32,
            pixelSize: size,
            iterations: 8,
            warmUpIterations: 3
        ) {
            _ = try backend.renderTexture(
                image,
                field: field,
                configuration: self.forcedConfiguration
            )
        }
        print("GEOMETRY_PERF \(preview.summary)")
        print("GEOMETRY_PERF_DEVICE \(backend.deviceName)")

        let export = try GeometryPerformanceProbe.measure(
            operation: "geometry.export.1080p",
            backend: backend.identifier,
            gridDimension: 64,
            pixelSize: size,
            iterations: 4,
            warmUpIterations: 1
        ) {
            _ = try backend.warp(
                image,
                field: field,
                configuration: self.forcedConfiguration
            )
        }
        print("GEOMETRY_PERF \(export.summary)")

        XCTAssertEqual(preview.pixelWidth, 1920)
        XCTAssertEqual(export.pixelWidth, 1920)
        XCTAssertGreaterThan(preview.p95FramesPerSecond, 0)

        if ProcessInfo.processInfo.environment["ST_GEOMETRY_PERF_STRICT"] == "1" {
            XCTAssertLessThanOrEqual(
                preview.p95Seconds,
                GeometryPerformanceProbe.previewFrameBudgetSeconds,
                "1080p preview p95 exceeds 30 fps budget: \(preview.summary)"
            )
        }
    }
}
#endif
