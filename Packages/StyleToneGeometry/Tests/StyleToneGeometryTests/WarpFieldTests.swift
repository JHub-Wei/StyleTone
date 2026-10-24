import XCTest
@testable import StyleToneGeometry

final class WarpFieldTests: XCTestCase {
    func testZeroFieldHasExpectedShape() throws {
        let field = try WarpField(width: 32, height: 32)

        XCTAssertEqual(field.width, 32)
        XCTAssertEqual(field.height, 32)
        XCTAssertEqual(field.vertexCount, 1024)
        XCTAssertEqual(field.offsets.count, 1024)
        XCTAssertTrue(field.isZero())
        XCTAssertEqual(field.maxMagnitude, 0)
    }

    func testRejectsInvalidGridsAndOffsetCounts() {
        XCTAssertThrowsError(try WarpField(width: 1, height: 32)) { error in
            XCTAssertEqual(error as? GeometryError, .invalidGrid(width: 1, height: 32))
        }
        XCTAssertThrowsError(try WarpField(width: 32, height: 0)) { error in
            XCTAssertEqual(error as? GeometryError, .invalidGrid(width: 32, height: 0))
        }
        XCTAssertThrowsError(
            try WarpField(
                width: 4,
                height: 4,
                offsets: [SIMD2<Float>](repeating: .zero, count: 15)
            )
        ) { error in
            XCTAssertEqual(
                error as? GeometryError,
                .offsetCountMismatch(expected: 16, actual: 15)
            )
        }
    }

    func testRejectsNonFiniteOffsets() {
        var offsets = [SIMD2<Float>](repeating: .zero, count: 4)
        offsets[2] = SIMD2<Float>(.nan, 0)
        XCTAssertThrowsError(try WarpField(width: 2, height: 2, offsets: offsets)) { error in
            XCTAssertEqual(error as? GeometryError, .nonFiniteOffset(index: 2))
        }
    }

    func testOffsetAccessAndMutationAreBoundsChecked() throws {
        var field = try WarpField(width: 2, height: 2)
        XCTAssertTrue(field.setOffset(SIMD2<Float>(0.1, 0.2), x: 1, y: 1))
        XCTAssertEqual(field.offset(x: 1, y: 1), SIMD2<Float>(0.1, 0.2))
        XCTAssertFalse(field.setOffset(.zero, x: 2, y: 0))
        XCTAssertFalse(field.addOffset(.zero, x: -1, y: 0))
        XCTAssertNil(field.offset(x: 0, y: 2))
        XCTAssertNil(field.index(x: 2, y: 2))
    }

    func testBilinearOffsetInterpolatesGrid() throws {
        let field = try WarpField(
            width: 2,
            height: 2,
            offsets: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(0.2, 0),
                SIMD2<Float>(0, 0.2),
                SIMD2<Float>(0.2, 0.2)
            ]
        )

        let center = field.bilinearOffset(at: SIMD2<Float>(0.5, 0.5))
        XCTAssertEqual(center.x, 0.1, accuracy: 1e-6)
        XCTAssertEqual(center.y, 0.1, accuracy: 1e-6)

        let quarter = field.bilinearOffset(at: SIMD2<Float>(0.25, 0.75))
        XCTAssertEqual(quarter.x, 0.05, accuracy: 1e-6)
        XCTAssertEqual(quarter.y, 0.15, accuracy: 1e-6)
    }

    func testBilinearOffsetClampsOutsideTheGrid() throws {
        let field = try WarpField(
            width: 2,
            height: 2,
            offsets: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(0.2, 0),
                SIMD2<Float>(0, 0.2),
                SIMD2<Float>(0.2, 0.2)
            ]
        )

        let clamped = field.bilinearOffset(at: SIMD2<Float>(-1, 2))
        XCTAssertEqual(clamped.x, 0, accuracy: 1e-6)
        XCTAssertEqual(clamped.y, 0.2, accuracy: 1e-6)
    }

    func testIsZeroUsesEpsilon() throws {
        var field = try WarpField(width: 2, height: 2)
        field.offsets[0] = SIMD2<Float>(1e-7, -1e-7)
        XCTAssertTrue(field.isZero(epsilon: 1e-6))
        field.offsets[0] = SIMD2<Float>(1e-3, 0)
        XCTAssertFalse(field.isZero(epsilon: 1e-6))
    }

    func testMaxMagnitudeUsesEuclideanLength() throws {
        let field = try GeometryTestSupport.constantField(
            width: 4,
            height: 4,
            offset: SIMD2<Float>(0.3, 0.4)
        )
        XCTAssertEqual(field.maxMagnitude, 0.5, accuracy: 1e-6)
    }
}
