import XCTest
@testable import StyleToneGeometry

final class GeometryBoundaryPolicyTests: XCTestCase {
    func testPinnedBorderIsExactlyZero() throws {
        var field = try GeometryTestSupport.constantField(
            width: 8,
            height: 8,
            offset: SIMD2<Float>(0.05, 0.05)
        )
        let policy = GeometryBoundaryPolicy(
            pinnedBorderVertices: 1,
            featherCells: 2,
            maximumDisplacement: 1
        )
        try policy.apply(to: &field)

        for y in 0 ..< 8 {
            for x in 0 ..< 8 {
                let edgeDistance = min(min(x, y), min(7 - x, 7 - y))
                if edgeDistance <= 1 {
                    XCTAssertEqual(
                        field.offsets[y * 8 + x],
                        SIMD2<Float>(0, 0),
                        "vertex (\(x),\(y))"
                    )
                }
            }
        }
    }

    func testFeatherRampUsesSmoothstep() throws {
        var field = try GeometryTestSupport.constantField(
            width: 12,
            height: 12,
            offset: SIMD2<Float>(0.01, 0.01)
        )
        let policy = GeometryBoundaryPolicy(
            pinnedBorderVertices: 1,
            featherCells: 4,
            maximumDisplacement: 1
        )
        try policy.apply(to: &field)

        // At edge distance 3 the ramp is 2/4 = 0.5 and smoothstep(0.5) = 0.5.
        let atDistanceThree = field.offsets[3 * 12 + 3]
        XCTAssertEqual(
            atDistanceThree.x,
            0.01 * 0.5,
            accuracy: 1e-6
        )
        XCTAssertEqual(
            atDistanceThree.y,
            0.01 * 0.5,
            accuracy: 1e-6
        )
        // At edge distance 5 the ramp is clamped to 1.
        let atDistanceFive = field.offsets[5 * 12 + 5]
        XCTAssertEqual(atDistanceFive.x, 0.01, accuracy: 1e-6)
    }

    func testFeatherIsMonotonicTowardsTheInterior() throws {
        let policy = GeometryBoundaryPolicy(
            pinnedBorderVertices: 1,
            featherCells: 4,
            maximumDisplacement: 1
        )
        var previous: Float = -1
        for distance in 0 ... 5 {
            let weight = policy.weight(x: distance, y: 5, width: 11, height: 11)
            XCTAssertGreaterThanOrEqual(weight, previous, "distance \(distance)")
            previous = weight
        }
        XCTAssertLessThan(policy.weight(x: 0, y: 5, width: 11, height: 11), 0.001)
        XCTAssertEqual(policy.weight(x: 5, y: 5, width: 11, height: 11), 1, accuracy: 1e-6)
    }

    func testMaximumDisplacementClampsMagnitude() throws {
        var field = try GeometryTestSupport.constantField(
            width: 8,
            height: 8,
            offset: SIMD2<Float>(0.3, 0.4)
        )
        let policy = GeometryBoundaryPolicy(
            pinnedBorderVertices: 1,
            featherCells: 0,
            maximumDisplacement: 0.1
        )
        try policy.apply(to: &field)

        let interior = field.offsets[4 * 8 + 4]
        let magnitude = (interior.x * interior.x + interior.y * interior.y).squareRoot()
        XCTAssertEqual(magnitude, 0.1, accuracy: 1e-6)
        XCTAssertEqual(interior.x / interior.y, 0.75, accuracy: 1e-6)
    }

    func testZeroFeatherOnlyPinsTheBorder() throws {
        var field = try GeometryTestSupport.constantField(
            width: 6,
            height: 6,
            offset: SIMD2<Float>(0.02, 0)
        )
        let policy = GeometryBoundaryPolicy(
            pinnedBorderVertices: 1,
            featherCells: 0,
            maximumDisplacement: 1
        )
        try policy.apply(to: &field)

        XCTAssertEqual(field.offsets[0], SIMD2<Float>(0, 0))
        XCTAssertEqual(field.offsets[2 * 6 + 2], SIMD2<Float>(0.02, 0))
    }

    func testApplyRejectsCorruptField() throws {
        var field = try GeometryTestSupport.constantField(
            width: 4,
            height: 4,
            offset: SIMD2<Float>(0, 0)
        )
        field.offsets.removeLast()
        XCTAssertThrowsError(try GeometryBoundaryPolicy.standard.apply(to: &field)) { error in
            XCTAssertEqual(
                error as? GeometryError,
                .offsetCountMismatch(expected: 16, actual: 15)
            )
        }
    }
}
