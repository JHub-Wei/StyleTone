import Foundation
import StyleToneCore
import XCTest
@testable import StyleToneGeometry

final class BodyWarpPerformanceTests: XCTestCase {
    func testPreviewGridContributionFitsPreviewBudget() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(personMask: mask)
        let parameters = BodyWarpTestSupport.parameters(arm: 0.8, waist: 0.8)
        let contributor = BodyWarpContributor()

        let sample = try GeometryPerformanceProbe.measure(
            operation: "geometry.body.contribute",
            backend: "geometry.cpu.body",
            gridDimension: 32,
            pixelSize: BodyWarpTestSupport.imageSize,
            iterations: 16,
            warmUpIterations: 4
        ) {
            _ = try contributor.makePlan(
                analysis: analysis,
                parameters: parameters,
                gridWidth: 32,
                gridHeight: 32
            )
        }

        print("GEOMETRY_PERF \(sample.summary)")
        XCTAssertLessThan(
            sample.p95Seconds,
            GeometryPerformanceProbe.previewFrameBudgetSeconds,
            "body contribution must leave room inside the 30 fps geometry budget"
        )
    }
}
