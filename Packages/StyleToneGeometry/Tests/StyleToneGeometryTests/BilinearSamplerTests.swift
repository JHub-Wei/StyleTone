import XCTest
@testable import StyleToneGeometry

final class BilinearSamplerTests: XCTestCase {
    private let pixels: [SIMD4<Float>] = [
        SIMD4<Float>(1, 0, 0, 1),
        SIMD4<Float>(0, 1, 0, 1),
        SIMD4<Float>(0, 0, 1, 1),
        SIMD4<Float>(1, 1, 1, 1)
    ]

    func testSamplesExactPixelCenters() {
        let red = BilinearSampler.sample(
            pixels,
            width: 2,
            height: 2,
            at: SIMD2<Float>(0.25, 0.25)
        )
        XCTAssertEqual(red, SIMD4<Float>(1, 0, 0, 1))

        let green = BilinearSampler.sample(
            pixels,
            width: 2,
            height: 2,
            at: SIMD2<Float>(0.75, 0.25)
        )
        XCTAssertEqual(green, SIMD4<Float>(0, 1, 0, 1))

        let blue = BilinearSampler.sample(
            pixels,
            width: 2,
            height: 2,
            at: SIMD2<Float>(0.25, 0.75)
        )
        XCTAssertEqual(blue, SIMD4<Float>(0, 0, 1, 1))

        let white = BilinearSampler.sample(
            pixels,
            width: 2,
            height: 2,
            at: SIMD2<Float>(0.75, 0.75)
        )
        XCTAssertEqual(white, SIMD4<Float>(1, 1, 1, 1))
    }

    func testInterpolatesInsideACell() {
        let average = BilinearSampler.sample(
            pixels,
            width: 2,
            height: 2,
            at: SIMD2<Float>(0.5, 0.5)
        )
        XCTAssertEqual(average.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(average.y, 0.5, accuracy: 1e-6)
        XCTAssertEqual(average.z, 0.5, accuracy: 1e-6)
        XCTAssertEqual(average.w, 1, accuracy: 1e-6)
    }

    func testClampsToEdgeOutsideTheImage() {
        let clamped = BilinearSampler.sample(
            pixels,
            width: 2,
            height: 2,
            at: SIMD2<Float>(-3, -3)
        )
        XCTAssertEqual(clamped, SIMD4<Float>(1, 0, 0, 1))

        let bottomRight = BilinearSampler.sample(
            pixels,
            width: 2,
            height: 2,
            at: SIMD2<Float>(5, 5)
        )
        XCTAssertEqual(bottomRight, SIMD4<Float>(1, 1, 1, 1))
    }

    func testSinglePixelImage() {
        let sample = BilinearSampler.sample(
            [SIMD4<Float>(0.2, 0.4, 0.6, 0.8)],
            width: 1,
            height: 1,
            at: SIMD2<Float>(0.9, 0.1)
        )
        XCTAssertEqual(sample, SIMD4<Float>(0.2, 0.4, 0.6, 0.8))
    }

    func testNonUniformHorizontalRow() {
        let row: [SIMD4<Float>] = [
            SIMD4<Float>(0, 0, 0, 1),
            SIMD4<Float>(0.5, 0.5, 0.5, 1),
            SIMD4<Float>(1, 1, 1, 1)
        ]
        let exact = BilinearSampler.sample(
            row,
            width: 3,
            height: 1,
            at: SIMD2<Float>(0.5, 0.5)
        )
        XCTAssertEqual(exact.x, 0.5, accuracy: 1e-6)

        let firstThird = BilinearSampler.sample(
            row,
            width: 3,
            height: 1,
            at: SIMD2<Float>(1.0 / 3.0, 0.5)
        )
        XCTAssertEqual(firstThird.x, 0.25, accuracy: 1e-6)
    }

    func testInterpolatesAlpha() {
        let samples: [SIMD4<Float>] = [
            SIMD4<Float>(0, 0, 0, 0),
            SIMD4<Float>(0, 0, 0, 1),
            SIMD4<Float>(0, 0, 0, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ]
        let alpha = BilinearSampler.sample(
            samples,
            width: 2,
            height: 2,
            at: SIMD2<Float>(0.5, 0.5)
        ).w
        XCTAssertEqual(alpha, 0.5, accuracy: 1e-6)
    }

    func testInvalidBufferReturnsZero() {
        let sample = BilinearSampler.sample(
            [],
            width: 2,
            height: 2,
            at: SIMD2<Float>(0.5, 0.5)
        )
        XCTAssertEqual(sample, .zero)
    }
}
