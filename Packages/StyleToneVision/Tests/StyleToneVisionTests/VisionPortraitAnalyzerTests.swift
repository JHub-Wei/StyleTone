import XCTest
import GoldenSupport
import StyleToneCore
import TestShared
@testable import StyleToneVision

final class VisionPortraitAnalyzerTests: XCTestCase {
    func testBlankImageDegradesWithoutCrashing() async throws {
        let image = try VisionTestImage.solid(
            size: PixelSize(width: 320, height: 240),
            color: RGB8(gray: 128)
        )
        let analyzer = VisionPortraitAnalyzer(
            configuration: VisionAnalysisConfiguration(
                maximumAnalysisDimension: 512,
                personSegmentationEnabled: false
            )
        )
        let result = try await analyzer.analyzeDetailed(image)

        XCTAssertEqual(result.analysis.imageSize, image.pixelSize)
        XCTAssertTrue(result.analysis.faces.isEmpty)
        XCTAssertTrue(result.analysis.warnings.contains(.noFace))
        XCTAssertTrue(result.analysis.warnings.contains(.noBody))
        XCTAssertLessThanOrEqual(result.confidence, 0.30)
        XCTAssertEqual(result.diagnostics.proxySize, image.pixelSize)
        XCTAssertNil(result.analysis.skinMask)

        let background = try XCTUnwrap(result.analysis.backgroundEdgeMask)
        XCTAssertEqual(background.width, image.pixelSize.width)
        XCTAssertEqual(background.height, image.pixelSize.height)
    }

    func testFaceSilhouetteKeepsCoordinatesAndMaskGeometry() async throws {
        let image = try VisionTestImage.fixture(named: "face.silhouette")
        let analyzer = VisionPortraitAnalyzer(
            configuration: VisionAnalysisConfiguration(
                maximumAnalysisDimension: 512,
                personSegmentationEnabled: false
            )
        )
        let result = try await analyzer.analyze(image)

        XCTAssertEqual(result.imageSize, image.pixelSize)
        for face in result.faces {
            XCTAssertTrue(face.boundingBox.x >= 0 && face.boundingBox.maxX <= 1)
            XCTAssertTrue(face.boundingBox.y >= 0 && face.boundingBox.maxY <= 1)
            for kind in FaceLandmarkKind.allCases {
                for point in face.points(for: kind) {
                    XCTAssertTrue(point.isNormalized, "\(kind) escaped 0...1")
                }
            }
        }
        if result.faces.isEmpty {
            XCTAssertTrue(result.warnings.contains(.noFace))
        }
        if result.faces.count > 1 {
            XCTAssertTrue(result.warnings.contains(.multipleFaces))
        }

        let background = try XCTUnwrap(result.backgroundEdgeMask)
        XCTAssertEqual(background.width, image.pixelSize.width)
        XCTAssertEqual(background.height, image.pixelSize.height)
    }

    func testLargeImageUsesProxyAndRestoresOriginalMaskSize() async throws {
        let image = try VisionTestImage.gradient(
            size: PixelSize(width: 2048, height: 1536)
        )
        let analyzer = VisionPortraitAnalyzer(
            configuration: VisionAnalysisConfiguration(
                maximumAnalysisDimension: 1024,
                segmentationQuality: .fast
            )
        )
        let result = try await analyzer.analyzeDetailed(image)

        XCTAssertEqual(result.analysis.imageSize, image.pixelSize)
        XCTAssertEqual(result.diagnostics.proxySize.longEdge, 1024)
        XCTAssertTrue(result.diagnostics.proxySize.width < image.pixelSize.width)

        let masks = [
            result.analysis.personMask,
            result.analysis.skinMask,
            result.analysis.backgroundEdgeMask
        ].compactMap { $0 }
        XCTAssertFalse(masks.isEmpty)
        for mask in masks {
            XCTAssertEqual(mask.width, image.pixelSize.width)
            XCTAssertEqual(mask.height, image.pixelSize.height)
            XCTAssertEqual(mask.bytes.count, mask.width * mask.height)
        }
    }

    func testEveryProducedMaskHasImageDimensions() async throws {
        let image = try VisionTestImage.fixture(named: "grid.tiles")
        let analyzer = VisionPortraitAnalyzer(
            configuration: VisionAnalysisConfiguration(
                maximumAnalysisDimension: 512,
                segmentationQuality: .fast
            )
        )
        let result = try await analyzer.analyze(image)
        let masks: [MaskBuffer] = [
            result.personMask,
            result.skinMask,
            result.backgroundEdgeMask
        ].compactMap { $0 }
        XCTAssertFalse(masks.isEmpty)
        for mask in masks {
            XCTAssertEqual(mask.width, image.pixelSize.width)
            XCTAssertEqual(mask.height, image.pixelSize.height)
        }
    }

    func testAnalysisOf1024ProxyCompletesWithinDebugEnvelope() async throws {
        let image = try VisionTestImage.gradient(
            size: PixelSize(width: 1024, height: 768)
        )
        let analyzer = VisionPortraitAnalyzer(
            configuration: VisionAnalysisConfiguration(
                maximumAnalysisDimension: 1024,
                segmentationQuality: .fast
            )
        )
        let measurement = try await PerformanceHarness.measureAsync(
            name: "analysis.1024.debug",
            iterations: 2,
            warmupIterations: 1
        ) {
            _ = try await analyzer.analyze(image)
        }
        // Debug XCTest builds are roughly an order of magnitude slower than
        // the Release device build. This envelope catches accidental
        // regressions; the 1.5 s acceptance budget is checked by the opt-in
        // test below on a Release build/device.
        XCTAssertLessThan(measurement.p95Seconds, 8.0, measurement.summary)
    }

    /// Contract target: 1024 px analysis p95 ≤ 1.5 s. Debug XCTest builds are
    /// not a valid measurement, so this is opt-in:
    ///
    /// `ST_RUN_VISION_1024_PERF=1 swift test -c release --filter ...`
    func testAnalysisOf1024ProxyMeetsDeviceBudget() async throws {
        guard ProcessInfo.processInfo.environment["ST_RUN_VISION_1024_PERF"] == "1" else {
            throw XCTSkip(
                "Set ST_RUN_VISION_1024_PERF=1 for the 1.5 s device/release budget"
            )
        }
        let image = try VisionTestImage.gradient(
            size: PixelSize(width: 1024, height: 768)
        )
        let analyzer = VisionPortraitAnalyzer(
            configuration: VisionAnalysisConfiguration(
                maximumAnalysisDimension: 1024,
                segmentationQuality: .fast
            )
        )
        let measurement = try await PerformanceHarness.measureAsync(
            name: "analysis.1024",
            iterations: 3,
            warmupIterations: 1
        ) {
            _ = try await analyzer.analyze(image)
        }
        let budget = PerformanceBudget(id: "analysis.1024", targetSeconds: 1.5)
        let verdict = budget.verdict(for: measurement)
        XCTAssertTrue(verdict.passed, verdict.message)
    }
}
