import Foundation
import StyleToneCore
import XCTest
@testable import StyleToneGeometry

/// Unit tests for the structure-grid sampling and line/rectangle detection.
final class BackgroundStructureDetectorTests: XCTestCase {
    private let configuration = BackgroundProtectionConfiguration()

    private func detect(
        _ mask: MaskBuffer,
        dimension: Int = 64
    ) throws -> BackgroundStructureDetector.Outcome {
        let grid = try BackgroundMaskSampler.sample(
            mask: mask,
            width: dimension,
            height: dimension,
            threshold: configuration.minimumEdgeValue,
            desiredStride: 1,
            maximumSamples: 2_000_000
        )
        return BackgroundStructureDetector(configuration: configuration)
            .detect(
                maximums: grid.maximums,
                means: grid.means,
                dimension: dimension
            )
    }

    func testDoorFrameProducesFourLinesAndOneRectangle() throws {
        let mask = try BackgroundTestSupport.doorFrameMask()
        let outcome = try detect(mask)

        XCTAssertEqual(outcome.lines.count, 4)
        XCTAssertEqual(
            outcome.lines.filter { $0.orientation == .horizontal }.count,
            2
        )
        XCTAssertEqual(
            outcome.lines.filter { $0.orientation == .vertical }.count,
            2
        )
        XCTAssertGreaterThanOrEqual(outcome.rectangles.count, 1)

        let positions = outcome.lines.map(\.position)
        for expected in [0.22, 0.78] {
            XCTAssertTrue(
                positions.contains { abs($0 - Float(expected)) < 0.02 },
                "missing vertical line at \(expected): \(positions)"
            )
        }
        for expected in [0.10, 0.90] {
            XCTAssertTrue(
                positions.contains { abs($0 - Float(expected)) < 0.02 },
                "missing horizontal line at \(expected): \(positions)"
            )
        }

        let rectangle = try XCTUnwrap(outcome.rectangles.first)
        XCTAssertEqual(rectangle.rect.x, 0.22, accuracy: 0.02)
        XCTAssertEqual(rectangle.rect.width, 0.56, accuracy: 0.03)
        XCTAssertEqual(rectangle.rect.y, 0.10, accuracy: 0.02)
        XCTAssertEqual(rectangle.rect.height, 0.80, accuracy: 0.03)
        XCTAssertGreaterThan(rectangle.strength, 0.8)
    }

    func testFloorTilesProduceGridLinesAndCells() throws {
        let mask = try BackgroundTestSupport.gridMask()
        let outcome = try detect(mask)

        XCTAssertGreaterThanOrEqual(outcome.lines.count, 8)
        XCTAssertEqual(
            outcome.lines.filter { $0.orientation == .horizontal }.count,
            4
        )
        XCTAssertEqual(
            outcome.lines.filter { $0.orientation == .vertical }.count,
            4
        )
        XCTAssertGreaterThanOrEqual(outcome.rectangles.count, 6)
        for rectangle in outcome.rectangles {
            XCTAssertEqual(rectangle.rect.width, 0.2, accuracy: 0.03)
            XCTAssertEqual(rectangle.rect.height, 0.2, accuracy: 0.03)
        }
    }

    func testTableEdgeProducesSingleLineWithoutRectangle() throws {
        let mask = try BackgroundTestSupport.tableEdgeMask()
        let outcome = try detect(mask)

        XCTAssertEqual(outcome.lines.count, 1)
        XCTAssertEqual(outcome.lines.first?.orientation, .horizontal)
        XCTAssertEqual(outcome.lines.first?.position ?? 0, 0.58, accuracy: 0.02)
        XCTAssertTrue(outcome.rectangles.isEmpty)
    }

    func testDenseTextureDoesNotProduceLines() throws {
        let mask = try BackgroundTestSupport.denseTextureMask()
        let outcome = try detect(mask)
        XCTAssertTrue(outcome.lines.isEmpty)
        XCTAssertTrue(outcome.rectangles.isEmpty)
    }

    func testSparseEdgesDoNotProduceLines() throws {
        let mask = try BackgroundTestSupport.sparseEdgeMask()
        let outcome = try detect(mask)
        XCTAssertTrue(outcome.lines.isEmpty)
        XCTAssertTrue(outcome.rectangles.isEmpty)
    }

    func testDiagonalEdgeIsNotReportedAsStraightLine() throws {
        let mask = try BackgroundTestSupport.diagonalMask()
        let outcome = try detect(mask)
        XCTAssertTrue(outcome.lines.isEmpty)
        XCTAssertTrue(outcome.rectangles.isEmpty)
    }

    func testSmallMaskStillDetectsStructure() throws {
        let size = PixelSize(width: 80, height: 60)
        let mask = try BackgroundTestSupport.doorFrameMask(size: size)
        let outcome = try detect(mask, dimension: 48)
        XCTAssertGreaterThanOrEqual(outcome.lines.count, 3)
    }

    func testSamplingStrideRespectsSmallMasks() {
        XCTAssertEqual(
            BackgroundMaskSampler.samplingStride(
                maskWidth: 240,
                maskHeight: 180,
                desiredStride: 4,
                maximumSamples: 1_500_000
            ),
            1
        )
        XCTAssertEqual(
            BackgroundMaskSampler.samplingStride(
                maskWidth: 4032,
                maskHeight: 3024,
                desiredStride: 4,
                maximumSamples: 1_500_000
            ),
            4
        )
        XCTAssertEqual(
            BackgroundMaskSampler.samplingStride(
                maskWidth: 12_000,
                maskHeight: 9_000,
                desiredStride: 1,
                maximumSamples: 100_000
            ),
            33
        )
    }

    func testMaskGridInterpolatesPeakAndMean() throws {
        let mask = try BackgroundTestSupport.tableEdgeMask(size: PixelSize(width: 64, height: 64))
        let grid = try BackgroundMaskSampler.sample(
            mask: mask,
            width: 64,
            height: 64,
            threshold: 24,
            desiredStride: 1,
            maximumSamples: 1_000_000
        )
        XCTAssertEqual(grid.maximum(at: SIMD2<Float>(0.5, 0.58)), 1, accuracy: 0.1)
        XCTAssertEqual(grid.maximum(at: SIMD2<Float>(0.5, 0.2)), 0, accuracy: 0.01)
        XCTAssertGreaterThan(grid.mean(at: SIMD2<Float>(0.5, 0.58)), 0)
    }
}
