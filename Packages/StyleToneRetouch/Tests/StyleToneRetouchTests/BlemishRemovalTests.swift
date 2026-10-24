import GoldenSupport
import StyleToneCore
import XCTest
@testable import StyleToneRetouch

final class BlemishRemovalTests: XCTestCase {
    private let retoucher = SkinRetoucher()

    func testRemovesDarkBlemishAndLeavesSurroundingsUntouched() async throws {
        let size = PixelSize(width: 192, height: 192)
        let point = BlemishPoint(
            point: NormalizedPoint(x: 0.5, y: 0.5),
            radius: 0.055
        )
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[2].color,
            blemishes: [point]
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size)
        )
        let output = try await retoucher.removeBlemish(
            input,
            at: point,
            analysis: analysis
        )
        let before = try PixelBuffer(image: input)
        let after = try PixelBuffer(image: output)

        let centerBefore = SyntheticSkin.meanLuma(
            before,
            center: point.point,
            radius: point.radius * 0.6
        )
        let centerAfter = SyntheticSkin.meanLuma(
            after,
            center: point.point,
            radius: point.radius * 0.6
        )
        let ring = SyntheticSkin.ringLuma(
            before,
            center: point.point,
            innerRadius: point.radius * 1.05,
            outerRadius: point.radius * 1.5
        )

        XCTAssertLessThan(centerBefore, ring - 5, "fixture blemish is not dark")
        XCTAssertLessThan(
            abs(centerAfter - ring),
            abs(centerBefore - ring) * 0.35,
            "blemish was not repaired"
        )
        XCTAssertEqual(output.pixelSize, input.pixelSize)

        let outside = SyntheticSkin.maximumDifferenceOutside(
            before,
            after,
            center: point.point,
            radius: point.radius * 1.02
        )
        XCTAssertLessThanOrEqual(outside, 1, "pixels outside the disk changed")
    }

    func testBatchRemovalRepairsEveryPointOnce() async throws {
        let size = PixelSize(width: 192, height: 192)
        let points = [
            BlemishPoint(point: NormalizedPoint(x: 0.30, y: 0.30), radius: 0.04),
            BlemishPoint(point: NormalizedPoint(x: 0.70, y: 0.48), radius: 0.04),
            BlemishPoint(point: NormalizedPoint(x: 0.48, y: 0.75), radius: 0.04)
        ]
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[3].color,
            blemishes: points
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size)
        )
        let output = try await retoucher.removeBlemishes(
            input,
            at: points,
            analysis: analysis
        )
        let before = try PixelBuffer(image: input)
        let after = try PixelBuffer(image: output)

        for point in points {
            let centerBefore = SyntheticSkin.meanLuma(
                before,
                center: point.point,
                radius: point.radius * 0.6
            )
            let centerAfter = SyntheticSkin.meanLuma(
                after,
                center: point.point,
                radius: point.radius * 0.6
            )
            let ring = SyntheticSkin.ringLuma(
                before,
                center: point.point,
                innerRadius: point.radius * 1.05,
                outerRadius: point.radius * 1.5
            )
            XCTAssertLessThan(
                abs(centerAfter - ring),
                abs(centerBefore - ring) * 0.5,
                "point \(point.point) was not repaired"
            )
        }
    }

    func testRepairWorksWithoutSkinMask() async throws {
        let size = PixelSize(width: 160, height: 160)
        let point = BlemishPoint(
            point: NormalizedPoint(x: 0.4, y: 0.55),
            radius: 0.05
        )
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[4].color,
            blemishes: [point]
        )
        let output = try await retoucher.removeBlemish(
            input,
            at: point,
            analysis: SyntheticSkin.analysis(size: size, mask: nil)
        )
        let before = try PixelBuffer(image: input)
        let after = try PixelBuffer(image: output)
        let centerBefore = SyntheticSkin.meanLuma(
            before,
            center: point.point,
            radius: point.radius * 0.6
        )
        let centerAfter = SyntheticSkin.meanLuma(
            after,
            center: point.point,
            radius: point.radius * 0.6
        )
        let ring = SyntheticSkin.ringLuma(
            before,
            center: point.point,
            innerRadius: point.radius * 1.05,
            outerRadius: point.radius * 1.5
        )
        XCTAssertLessThan(abs(centerAfter - ring), abs(centerBefore - ring) * 0.5)
    }

    func testInvalidAndEmptyPointsReturnOriginalAsset() async throws {
        let size = PixelSize(width: 96, height: 96)
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[2].color
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size)
        )

        let empty = try await retoucher.removeBlemishes(
            input,
            at: [],
            analysis: analysis
        )
        XCTAssertTrue(empty.cgImage === input.cgImage)

        let invalid = [
            BlemishPoint(point: NormalizedPoint(x: -0.2, y: 0.5), radius: 0.03),
            BlemishPoint(point: NormalizedPoint(x: 1.2, y: 0.5), radius: 0.03),
            BlemishPoint(point: NormalizedPoint(x: 0.5, y: -0.1), radius: 0.03),
            BlemishPoint(
                point: NormalizedPoint(x: .nan, y: 0.5),
                radius: 0.03
            )
        ]
        let unchanged = try await retoucher.removeBlemishes(
            input,
            at: invalid,
            analysis: analysis
        )
        XCTAssertTrue(unchanged.cgImage === input.cgImage)
    }

    func testTinyImagesAndEdgePointsAreSafe() async throws {
        let onePixel = try MockImageAssetFactory.solid(
            color: .midGray,
            size: PixelSize(width: 1, height: 1)
        )
        let onePoint = BlemishPoint(
            point: NormalizedPoint(x: 0.5, y: 0.5),
            radius: 0.08
        )
        let tiny = try await retoucher.removeBlemish(
            onePixel,
            at: onePoint,
            analysis: SyntheticSkin.analysis(
                size: PixelSize(width: 1, height: 1),
                mask: nil
            )
        )
        XCTAssertEqual(tiny.pixelSize, onePixel.pixelSize)

        let size = PixelSize(width: 64, height: 64)
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[3].color
        )
        let corner = BlemishPoint(
            point: NormalizedPoint(x: 0.02, y: 0.02),
            radius: 0.05
        )
        let output = try await retoucher.removeBlemish(
            input,
            at: corner,
            analysis: SyntheticSkin.analysis(
                size: size,
                mask: try SyntheticSkin.fullMask(size: size)
            )
        )
        XCTAssertEqual(output.pixelSize, input.pixelSize)
    }
}
