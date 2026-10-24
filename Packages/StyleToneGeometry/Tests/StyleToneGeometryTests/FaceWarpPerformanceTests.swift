import Foundation
import StyleToneCore
import XCTest
@testable import StyleToneGeometry

final class FaceWarpPerformanceTests: XCTestCase {
    func testPreviewContributionFitsThirtyFPSBudget() throws {
        let analyses: [(String, PortraitAnalysis)] = [
            ("1face", FaceWarpTestSupport.analysis([FaceWarpTestSupport.face()])),
            (
                "3faces",
                FaceWarpTestSupport.analysis(FaceWarpTestSupport.threeFaces())
            )
        ]
        let contributor = FaceWarpContributor()
        let parameters = FaceParameters(slim: 0.8, jaw: 0.7)

        for (label, analysis) in analyses {
            let sample = try GeometryPerformanceProbe.measure(
                operation: "face.plan.\(label)",
                backend: "geometry.face.cpu",
                gridDimension: 32,
                pixelSize: FaceWarpTestSupport.imageSize,
                iterations: 20,
                warmUpIterations: 3
            ) {
                _ = try contributor.plan(
                    for: analysis,
                    parameters: parameters,
                    gridDimension: 32
                )
            }
            print("FACE_GEOMETRY_PERF \(sample.summary)")
            XCTAssertLessThan(
                sample.p95Seconds,
                GeometryPerformanceProbe.previewFrameBudgetSeconds,
                "\(label) face contribution must fit a 1080p 30 fps frame"
            )
        }
    }

    func testExportDensityContributionMeasurement() throws {
        let analysis = FaceWarpTestSupport.analysis(
            FaceWarpTestSupport.threeFaces()
        )
        let contributor = FaceWarpContributor()
        let parameters = FaceParameters(slim: 0.8, jaw: 0.7)
        let sample = try GeometryPerformanceProbe.measure(
            operation: "face.plan.export.3faces",
            backend: "geometry.face.cpu",
            gridDimension: 64,
            pixelSize: FaceWarpTestSupport.imageSize,
            iterations: 10,
            warmUpIterations: 2
        ) {
            _ = try contributor.plan(
                for: analysis,
                parameters: parameters,
                gridDimension: 64
            )
        }
        print("FACE_GEOMETRY_PERF \(sample.summary)")
        XCTAssertLessThan(
            sample.p95Seconds,
            4 * GeometryPerformanceProbe.previewFrameBudgetSeconds,
            "64x64 export planning should stay well below a multi-frame budget"
        )
    }
}
