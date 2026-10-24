import XCTest
@testable import StyleToneGeometry

final class MeshWarpSamplerTests: XCTestCase {
    func testIdentityFieldIsIdentity() throws {
        let field = try WarpField(width: 32, height: 32)
        let points: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(0.25, 0.75),
            SIMD2<Float>(0.5, 0.5),
            SIMD2<Float>(1, 1)
        ]
        for point in points {
            let source = MeshWarpSampler.sourcePosition(for: point, field: field)
            XCTAssertEqual(source.x, point.x, accuracy: 1e-6)
            XCTAssertEqual(source.y, point.y, accuracy: 1e-6)
        }
    }

    func testConstantOffsetSubtractsFromOutputPosition() throws {
        let field = try GeometryTestSupport.constantField(
            width: 8,
            height: 8,
            offset: SIMD2<Float>(0.1, -0.2)
        )
        let source = MeshWarpSampler.sourcePosition(
            for: SIMD2<Float>(0.5, 0.5),
            field: field
        )
        XCTAssertEqual(source.x, 0.4, accuracy: 1e-6)
        XCTAssertEqual(source.y, 0.7, accuracy: 1e-6)
    }

    func testFirstTriangleInterpolationMatchesCellWeights() throws {
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
        let source = MeshWarpSampler.sourcePosition(
            for: SIMD2<Float>(0.25, 0.25),
            field: field
        )
        XCTAssertEqual(source.x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(source.y, 0.2, accuracy: 1e-6)
    }

    func testSecondTriangleInterpolationMatchesCellWeights() throws {
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
        let source = MeshWarpSampler.sourcePosition(
            for: SIMD2<Float>(0.75, 0.75),
            field: field
        )
        XCTAssertEqual(source.x, 0.6, accuracy: 1e-6)
        XCTAssertEqual(source.y, 0.6, accuracy: 1e-6)
    }

    func testBothTrianglesAgreeOnTheDiagonal() throws {
        let field = try WarpField(
            width: 2,
            height: 2,
            offsets: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(0.2, 0.1),
                SIMD2<Float>(0.1, 0.3),
                SIMD2<Float>(0.5, 0.5)
            ]
        )
        let source = MeshWarpSampler.sourcePosition(
            for: SIMD2<Float>(0.5, 0.5),
            field: field
        )
        // Weights are 0.5 * topLeft + 0.25 * topRight + 0.25 * bottomLeft.
        XCTAssertEqual(source.x, 0.5 - 0.075, accuracy: 1e-6)
        XCTAssertEqual(source.y, 0.5 - 0.1, accuracy: 1e-6)
    }

    func testSourcePositionCanLeaveTheImageForClamping() throws {
        let field = try GeometryTestSupport.constantField(
            width: 8,
            height: 8,
            offset: SIMD2<Float>(0.4, 0)
        )
        let source = MeshWarpSampler.sourcePosition(
            for: SIMD2<Float>(0.1, 0.5),
            field: field
        )
        XCTAssertLessThan(source.x, 0)
    }

    func testOutputPointsOutsideTheImageAreClamped() throws {
        let field = try GeometryTestSupport.constantField(
            width: 8,
            height: 8,
            offset: SIMD2<Float>(0.1, 0.1)
        )
        let atOrigin = MeshWarpSampler.sourcePosition(
            for: SIMD2<Float>(-1, -1),
            field: field
        )
        XCTAssertEqual(atOrigin.x, -0.1, accuracy: 1e-6)
        XCTAssertEqual(atOrigin.y, -0.1, accuracy: 1e-6)
    }

    func testPixelCenterConvenience() throws {
        let field = try WarpField(width: 4, height: 4)
        let source = MeshWarpSampler.sourcePosition(
            forPixelX: 2,
            pixelY: 1,
            width: 4,
            height: 4,
            field: field
        )
        XCTAssertEqual(source.x, 0.625, accuracy: 1e-6)
        XCTAssertEqual(source.y, 0.375, accuracy: 1e-6)
    }

    func testInvalidFieldFallsBackToIdentity() throws {
        // Construct a valid field, then corrupt it to exercise the defensive
        // path without using an invalid initializer.
        var corrupt = try WarpField(width: 2, height: 2)
        corrupt.offsets.removeLast()
        let source = MeshWarpSampler.sourcePosition(
            for: SIMD2<Float>(0.3, 0.7),
            field: corrupt
        )
        XCTAssertEqual(source.x, 0.3, accuracy: 1e-6)
        XCTAssertEqual(source.y, 0.7, accuracy: 1e-6)
    }
}
