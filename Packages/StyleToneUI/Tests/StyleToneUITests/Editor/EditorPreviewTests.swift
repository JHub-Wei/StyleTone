import StyleToneCore
import XCTest
@testable import StyleToneUI

final class EditorPreviewTests: XCTestCase {
    func testTargetSizeKeepsLongEdgeAndAspect() {
        let landscape = PixelSize(width: 400, height: 300)
        XCTAssertEqual(
            CoreGraphicsPreviewScaler.targetSize(for: landscape, maximumLongEdge: 100),
            PixelSize(width: 100, height: 75)
        )

        let portrait = PixelSize(width: 300, height: 400)
        XCTAssertEqual(
            CoreGraphicsPreviewScaler.targetSize(for: portrait, maximumLongEdge: 100),
            PixelSize(width: 75, height: 100)
        )

        XCTAssertEqual(
            CoreGraphicsPreviewScaler.targetSize(for: landscape, maximumLongEdge: 1_000),
            landscape
        )
        XCTAssertEqual(
            CoreGraphicsPreviewScaler.targetSize(for: landscape, maximumLongEdge: 0),
            landscape
        )
    }

    func testScalerDownscalesImageAndResamplesMasks() throws {
        let size = PixelSize(width: 120, height: 80)
        let image = try EditorTestFactory.image(size: size)
        let analysis = try EditorTestFactory.analysis(size: size)
        let scaler = CoreGraphicsPreviewScaler()

        let context = try scaler.preparePreview(
            image: image,
            analysis: analysis,
            maximumLongEdge: 60
        )

        XCTAssertEqual(context.image.pixelSize, PixelSize(width: 60, height: 40))
        XCTAssertEqual(context.analysis.imageSize, PixelSize(width: 60, height: 40))
        XCTAssertEqual(context.analysis.personMask?.width, 60)
        XCTAssertEqual(context.analysis.personMask?.height, 40)
        XCTAssertEqual(context.analysis.skinMask?.width, 60)
        XCTAssertEqual(context.analysis.faces.first?.boundingBox, analysis.faces.first?.boundingBox)
        XCTAssertEqual(context.analysis.warnings, analysis.warnings)
    }

    func testPreviewPreparerCachesUntilQualityTierChanges() async throws {
        let size = PixelSize(width: 120, height: 80)
        let image = try EditorTestFactory.image(size: size)
        let analysis = try EditorTestFactory.analysis(size: size)
        let preparer = EditorPreviewPreparer()

        let first = try await preparer.preparePreview(
            image: image,
            analysis: analysis,
            maximumLongEdge: 60
        )
        let second = try await preparer.preparePreview(
            image: image,
            analysis: analysis,
            maximumLongEdge: 60
        )

        XCTAssertTrue(first.image.cgImage === second.image.cgImage)
        let countAfterCacheHit = await preparer.preparationCount
        XCTAssertEqual(countAfterCacheHit, 1)

        let third = try await preparer.preparePreview(
            image: image,
            analysis: analysis,
            maximumLongEdge: 80
        )
        XCTAssertEqual(third.image.pixelSize, PixelSize(width: 80, height: 53))

        let countAfterTierChange = await preparer.preparationCount
        XCTAssertEqual(countAfterTierChange, 2)
    }
}
