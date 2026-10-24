import XCTest
@testable import GoldenSupport
import StyleToneCore

final class ImageComparisonTests: XCTestCase {
    func testIdenticalImagesPassIdentityThresholds() throws {
        let buffer = try FixtureCatalog.fixture(id: "colorchart.macbeth24").render()
        let report = try ImageComparator.compare(expected: buffer, actual: buffer, thresholds: .identity)

        XCTAssertTrue(report.passes, report.summary)
        XCTAssertEqual(report.differingPixelCount, 0)
        XCTAssertEqual(report.differingPixelRatio, 0)
        XCTAssertEqual(report.meanDeltaE00, 0, accuracy: 1e-12)
        XCTAssertEqual(report.maxDeltaE00, 0, accuracy: 1e-12)
        XCTAssertEqual(report.ssim, 1, accuracy: 1e-12)
        XCTAssertNil(report.differenceBoundingBox)
        XCTAssertEqual(report.expectedSize, buffer.pixelSize)
    }

    func testSinglePixelChangeIsDetectedAndBounded() throws {
        let expected = try PixelBuffer(width: 16, height: 16, fill: .black)
        var actual = expected
        actual[7, 9] = RGBA8(color: .white)

        let report = try ImageComparator.compare(expected: expected, actual: actual, thresholds: .identity)
        XCTAssertFalse(report.passes)
        XCTAssertEqual(report.differingPixelCount, 1)
        XCTAssertEqual(report.differingPixelRatio, 1.0 / 256.0, accuracy: 1e-12)
        XCTAssertEqual(report.maxChannelDelta, 255)
        XCTAssertEqual(report.differenceBoundingBox, PixelRect(x: 7, y: 9, width: 1, height: 1))
        XCTAssertGreaterThanOrEqual(report.failures.count, 3)
        XCTAssertTrue(report.failures.contains { $0.hasPrefix("maxDeltaE00") })
    }

    func testSizeMismatchThrows() throws {
        let first = try PixelBuffer(width: 4, height: 4, fill: .black)
        let second = try PixelBuffer(width: 4, height: 5, fill: .black)
        XCTAssertThrowsError(try ImageComparator.compare(expected: first, actual: second)) { error in
            XCTAssertEqual(
                error as? GoldenSupportError,
                .imageSizeMismatch(
                    expected: PixelSize(width: 4, height: 4),
                    actual: PixelSize(width: 4, height: 5)
                )
            )
        }
    }

    func testSSIMIsSymmetricAndMatchesAnalyticValueForFlatImages() throws {
        let first = try PixelBuffer(width: 8, height: 8, fill: RGB8(gray: 100))
        let second = try PixelBuffer(width: 8, height: 8, fill: RGB8(gray: 150))
        let forward = ImageComparator.structuralSimilarity(first, second)
        let reverse = ImageComparator.structuralSimilarity(second, first)
        XCTAssertEqual(forward, reverse, accuracy: 1e-12)

        let meanFirst = RGB8(gray: 100).luma
        let meanSecond = RGB8(gray: 150).luma
        let c1 = 6.5025
        let expected = (2 * meanFirst * meanSecond + c1)
            / (meanFirst * meanFirst + meanSecond * meanSecond + c1)
        XCTAssertEqual(forward, expected, accuracy: 1e-12)
        XCTAssertEqual(
            ImageComparator.structuralSimilarity(first, first),
            1,
            accuracy: 1e-12
        )
    }

    func testBlackAndWhiteImagesHaveHundredDeltaE() throws {
        let black = try PixelBuffer(width: 8, height: 8, fill: .black)
        let white = try PixelBuffer(width: 8, height: 8, fill: .white)
        let report = try ImageComparator.compare(expected: black, actual: white, thresholds: .standard)
        XCTAssertEqual(report.meanDeltaE00, 100, accuracy: 0.5)
        XCTAssertEqual(report.maxDeltaE00, 100, accuracy: 0.5)
        XCTAssertEqual(report.differingPixelRatio, 1, accuracy: 1e-12)
        XCTAssertLessThan(report.ssim, 0.01)
    }

    func testDeltaEMapIsRowMajor() throws {
        var first = try PixelBuffer(width: 2, height: 2, fill: .black)
        var second = try PixelBuffer(width: 2, height: 2, fill: .black)
        second[1, 0] = RGBA8(color: .white)
        first[0, 1] = RGBA8(color: .white)
        let map = try ImageComparator.deltaEMap(expected: first, actual: second)
        XCTAssertEqual(map.count, 4)
        XCTAssertEqual(map[1], 100, accuracy: 0.5)
        XCTAssertEqual(map[2], 100, accuracy: 0.5)
        XCTAssertEqual(map[0], 0, accuracy: 1e-9)
        XCTAssertEqual(map[3], 0, accuracy: 1e-9)
    }

    func testDifferenceImageIsAmplifiedGrayscale() throws {
        let expected = try PixelBuffer(width: 2, height: 1, fill: .black)
        var actual = expected
        actual[0, 0] = RGBA8(red: 10, green: 0, blue: 0)
        let difference = try ImageComparator.differenceImage(expected: expected, actual: actual, amplification: 8)
        XCTAssertEqual(difference[0, 0].red, 80)
        XCTAssertEqual(difference[0, 0].green, 80)
        XCTAssertEqual(difference[0, 0].blue, 80)
        XCTAssertEqual(difference[1, 0].red, 0)
    }

    func testThresholdsCanBeRelaxed() throws {
        var actual = try PixelBuffer(width: 16, height: 16, fill: RGB8(gray: 128))
        actual[0, 0] = RGBA8(color: RGB8(gray: 160))
        let strict = try ImageComparator.compare(
            expected: PixelBuffer(width: 16, height: 16, fill: RGB8(gray: 128)),
            actual: actual,
            thresholds: .identity
        )
        XCTAssertFalse(strict.passes)

        let relaxed = try ImageComparator.compare(
            expected: PixelBuffer(width: 16, height: 16, fill: RGB8(gray: 128)),
            actual: actual,
            thresholds: ImageThresholds(
                channelTolerance: 255,
                allowedDifferingPixelRatio: 1,
                maxMeanDeltaE00: 100,
                maxP95DeltaE00: 100,
                maxDeltaE00: 100,
                minSSIM: 0
            )
        )
        XCTAssertTrue(relaxed.passes)
    }

    func testReportCodableRoundTrip() throws {
        let expected = try FixtureCatalog.fixture(id: "checkerboard.8px").render()
        var actual = expected
        actual[3, 3] = RGBA8(color: .white)
        let report = try ImageComparator.compare(expected: expected, actual: actual, thresholds: .strict)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        let decoded = try JSONDecoder().decode(ImageDifferenceReport.self, from: data)
        XCTAssertEqual(decoded, report)
    }

    func testMarkdownContainsMetricsAndFailureReasons() throws {
        let expected = try PixelBuffer(width: 4, height: 4, fill: .black)
        var actual = expected
        actual[1, 1] = RGBA8(color: .white)
        let report = try ImageComparator.compare(expected: expected, actual: actual, thresholds: .identity)
        let markdown = report.markdown()
        XCTAssertTrue(markdown.contains("FAIL"))
        XCTAssertTrue(markdown.contains("mean ΔE00"))
        XCTAssertTrue(markdown.contains("differingPixelRatio"))
        XCTAssertTrue(markdown.contains("difference bounds"))
    }
}
