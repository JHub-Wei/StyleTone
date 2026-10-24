import CoreGraphics
import GoldenSupport
import StyleToneCore
import StyleToneImaging
import XCTest
@testable import StyleToneGeometry

final class CPUGeometryWarpTests: XCTestCase {
    private let backend = CPUGeometryWarp()

    func testZeroFieldReturnsTheExactInputImage() throws {
        let image = try GeometryTestSupport.gradientWithBorder(width: 64, height: 48)
        let field = try WarpField(width: 32, height: 32)
        let output = try backend.warp(
            image,
            field: field,
            configuration: GeometryWarpConfiguration(
                quality: .preview,
                allowsIdentityShortcut: true
            )
        )
        XCTAssertTrue(output.cgImage === image.cgImage)
        XCTAssertEqual(output.pixelSize, image.pixelSize)
    }

    func testForcedIdentityRendersWithinPixelAndDeltaEThresholds() throws {
        let image = try GeometryTestSupport.gradientWithBorder(width: 64, height: 48)
        let field = try WarpField(width: 32, height: 32)
        let output = try backend.warp(
            image,
            field: field,
            configuration: GeometryWarpConfiguration(
                quality: .preview,
                allowsIdentityShortcut: false
            )
        )
        var thresholds = ImageThresholds.standard
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

    func testConstantOffsetTranslatesContentAtPixelCenters() throws {
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
            configuration: GeometryWarpConfiguration(
                quality: .preview,
                allowsIdentityShortcut: false
            )
        )
        let source = try PixelBuffer(image: image)
        let warped = try PixelBuffer(image: output)

        // Output x = 48 samples source x = 32 because the offset is 0.25 * 64.
        for y in [4, 16, 27] {
            XCTAssertEqual(
                Double(warped[48, y].red),
                Double(source[32, y].red),
                accuracy: 2,
                "y=\(y)"
            )
        }
    }

    func testFeatheredBoundaryDoesNotProduceBlackBorders() throws {
        let image = try GeometryTestSupport.gradientWithBorder(width: 64, height: 64)
        let field = try GeometryTestSupport.featheredField(
            width: 32,
            height: 32,
            offset: SIMD2<Float>(0.2, 0.12)
        )
        let output = try backend.warp(
            image,
            field: field,
            configuration: GeometryWarpConfiguration(
                quality: .preview,
                allowsIdentityShortcut: false
            )
        )
        try GeometryTestSupport.assertNoBlackBorder(output, border: 2)

        // The pinned outer ring must keep the original red frame.
        let source = try PixelBuffer(image: image)
        let warped = try PixelBuffer(image: output)
        for x in stride(from: 0, to: 64, by: 7) {
            XCTAssertEqual(
                Double(warped[x, 0].red),
                Double(source[x, 0].red),
                accuracy: 2
            )
            XCTAssertEqual(
                Double(warped[x, 63].red),
                Double(source[x, 63].red),
                accuracy: 2
            )
        }
    }

    func testClampToEdgePreventsEmptyEdgesWithLargeInteriorOffset() throws {
        let image = try GeometryTestSupport.gradientWithBorder(width: 64, height: 64)
        let field = try GeometryTestSupport.constantField(
            width: 32,
            height: 32,
            offset: SIMD2<Float>(0.5, 0.5)
        )
        let output = try backend.warp(
            image,
            field: field,
            configuration: GeometryWarpConfiguration(
                quality: .preview,
                allowsIdentityShortcut: false
            )
        )
        try GeometryTestSupport.assertNoBlackBorder(output, border: 3)

        let warped = try PixelBuffer(image: output)
        for y in 0 ..< 64 {
            XCTAssertEqual(warped[0, y].alpha, 255)
            XCTAssertEqual(warped[63, y].alpha, 255)
        }
        for x in 0 ..< 64 {
            XCTAssertEqual(warped[x, 0].alpha, 255)
            XCTAssertEqual(warped[x, 63].alpha, 255)
        }
    }

    func testPreservesDisplayP3ColorSpace() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let image = try GeometryTestSupport.makeImage(
            width: 16,
            height: 16,
            colorSpace: p3
        ) { x, y in
            RGBA8(red: UInt8(x * 16), green: UInt8(y * 16), blue: 128)
        }
        let field = try GeometryTestSupport.constantField(
            width: 8,
            height: 8,
            offset: SIMD2<Float>(0.1, 0.05)
        )
        let output = try backend.warp(
            image,
            field: field,
            configuration: GeometryWarpConfiguration(
                quality: .preview,
                allowsIdentityShortcut: false
            )
        )
        XCTAssertEqual(output.pixelSize, image.pixelSize)
        XCTAssertEqual(ImageColorSpace.detect(output.colorSpace), .displayP3)
    }

    func test1080pCPUFallbackFrameTimeRecord() throws {
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
        let sample = try GeometryPerformanceProbe.measure(
            operation: "geometry.cpu.fallback.1080p",
            backend: backend.identifier,
            gridDimension: 32,
            pixelSize: size,
            iterations: 1,
            warmUpIterations: 0
        ) {
            _ = try backend.warp(
                image,
                field: field,
                configuration: GeometryWarpConfiguration(
                    quality: .preview,
                    allowsIdentityShortcut: false
                )
            )
        }
        print("GEOMETRY_PERF \(sample.summary)")
        XCTAssertEqual(sample.pixelWidth, 1920)
        XCTAssertEqual(sample.pixelHeight, 1080)
    }

    func testCancellationPropagates() async throws {
        let image = try GeometryTestSupport.gradientWithBorder(width: 64, height: 64)
        let field = try GeometryTestSupport.constantField(
            width: 32,
            height: 32,
            offset: SIMD2<Float>(0.1, 0.1)
        )
        let warpBackend = backend
        let task = Task { () -> Error? in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            do {
                _ = try warpBackend.warp(
                    image,
                    field: field,
                    configuration: GeometryWarpConfiguration(
                        quality: .preview,
                        allowsIdentityShortcut: false
                    )
                )
                return nil
            } catch {
                return error
            }
        }
        let error = await task.value
        XCTAssertNotNil(
            error as? CancellationError,
            "expected CancellationError, got \(String(describing: error))"
        )
    }
}
