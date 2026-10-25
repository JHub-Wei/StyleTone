import Foundation
import StyleToneCore
import XCTest
@testable import StyleToneGeometry

final class BodyWarpContributorTests: XCTestCase {
    private let contributor = BodyWarpContributor()
    private let grid = 64

    func testNoBodyIsSafeAndWarns() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(
            includeBody: false,
            personMask: mask
        )

        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.warnings, [.noBody])
        XCTAssertEqual(plan.peakDisplacement, 0)
        XCTAssertTrue(plan.offsets.allSatisfy { $0 == .zero })
    }

    func testEmptyPoseIsSafeAndWarns() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(
            missingJoints: Set(BodyJointKind.allCases),
            personMask: mask
        )
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.warnings.contains(.incompletePose))
        XCTAssertTrue(plan.offsets.allSatisfy { $0 == .zero })
    }

    func testMissingSegmentationIsSafeAndWarns() throws {
        let analysis = BodyWarpTestSupport.analysis(personMask: nil)
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.warnings, [.noSegmentation])
    }

    func testGlobalOcclusionSkipsEverything() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(
            personMask: mask,
            warnings: [.occlusion]
        )
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.warnings.contains(.occlusion))
        XCTAssertTrue(plan.offsets.allSatisfy { $0 == .zero })
    }

    func testBlankMaskIsSafeAndWarns() throws {
        let blank = try MaskBuffer(
            width: 8,
            height: 8,
            bytes: Data(repeating: 0, count: 64)
        )
        let analysis = BodyWarpTestSupport.analysis(personMask: blank)
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.warnings.contains(.occlusion))
    }

    func testAppliesSymmetricWaistAndBothArmInsets() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(personMask: mask)
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(arm: 0.8, waist: 0.8),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertEqual(
            plan.appliedRegions,
            Set([BodyWarpRegion.leftArm, .rightArm, .waist])
        )
        XCTAssertGreaterThan(plan.peakDisplacement, 0.005)
        XCTAssertLessThanOrEqual(
            plan.peakDisplacement,
            BodyWarpConfiguration.standard.maximumCombinedInset + 1e-9
        )
        XCTAssertTrue(plan.offsets.allSatisfy { $0.x.isFinite && $0.y.isFinite })

        let field = try BodyWarpTestSupport.field(for: plan)
        let leftWaist = field.bilinearOffset(at: SIMD2<Float>(0.42, 0.4556))
        let rightWaist = field.bilinearOffset(at: SIMD2<Float>(0.58, 0.4556))
        XCTAssertGreaterThan(leftWaist.x, 0.0005)
        XCTAssertLessThan(rightWaist.x, -0.0005)
        XCTAssertEqual(leftWaist.y, 0, accuracy: 1e-6)
        XCTAssertEqual(rightWaist.y, 0, accuracy: 1e-6)

        let leftOuterArm = field.bilinearOffset(at: SIMD2<Float>(0.30, 0.43))
        let rightOuterArm = field.bilinearOffset(at: SIMD2<Float>(0.695, 0.43))
        XCTAssertGreaterThan(leftOuterArm.x, 0.0005)
        XCTAssertLessThan(rightOuterArm.x, -0.0005)
    }

    func testHandsAndBackgroundStayStill() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(personMask: mask)
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )
        let field = try BodyWarpTestSupport.field(for: plan)

        for point in [
            SIMD2<Float>(0.35, 0.57),
            SIMD2<Float>(0.35, 0.61),
            SIMD2<Float>(0.65, 0.57),
            SIMD2<Float>(0.65, 0.61)
        ] {
            let offset = field.bilinearOffset(at: point)
            XCTAssertLessThan(
                magnitude(offset),
                0.001,
                "hand influence leaked at \(point)"
            )
        }

        for point in [
            SIMD2<Float>(0.12, 0.20),
            SIMD2<Float>(0.12, 0.40),
            SIMD2<Float>(0.12, 0.60),
            SIMD2<Float>(0.12, 0.80),
            SIMD2<Float>(0.05, 0.30),
            SIMD2<Float>(0.95, 0.30),
            SIMD2<Float>(0.08, 0.50)
        ] {
            XCTAssertEqual(
                field.bilinearOffset(at: point),
                SIMD2<Float>.zero,
                "background moved at \(point)"
            )
        }

        let waistCenter = field.bilinearOffset(at: SIMD2<Float>(0.50, 0.4556))
        XCTAssertEqual(waistCenter.x, 0, accuracy: 1e-7)
        XCTAssertEqual(waistCenter.y, 0, accuracy: 1e-7)
    }

    func testStrengthIsMonotonicAndBounded() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(personMask: mask)

        let weak = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(arm: 0.30, waist: 0.30),
            gridWidth: grid,
            gridHeight: grid
        )
        let strong = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(arm: 0.90, waist: 0.90),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertGreaterThan(weak.peakDisplacement, 0)
        XCTAssertGreaterThan(strong.peakDisplacement, weak.peakDisplacement * 1.5)
        XCTAssertLessThanOrEqual(
            strong.peakDisplacement,
            BodyWarpConfiguration.standard.maximumCombinedInset + 1e-9
        )

        var clamped = BodyWarpConfiguration.standard
        clamped.maximumArmInset = 0.001
        clamped.maximumWaistInset = 0.001
        clamped.maximumCombinedInset = 0.0008
        let clampedContributor = BodyWarpContributor(configuration: clamped)
        let clampedPlan = try clampedContributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(clampedPlan.didClampToLimit)
        XCTAssertTrue(clampedPlan.warnings.contains(.strengthLimited))
        XCTAssertLessThanOrEqual(clampedPlan.peakDisplacement, 0.0008 + 1e-9)
        for offset in clampedPlan.offsets {
            let metric = BodyWarpTestSupport.metricOffset(offset)
            XCTAssertLessThanOrEqual(magnitude(metric), 0.0008 + 1e-9)
        }
    }

    func testLowConfidenceAttenuatesAndWarns() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let highAnalysis = BodyWarpTestSupport.analysis(
            bodyConfidence: 0.90,
            personMask: mask
        )
        let lowAnalysis = BodyWarpTestSupport.analysis(
            bodyConfidence: 0.45,
            personMask: mask
        )
        let parameters = BodyWarpTestSupport.parameters()

        let high = try contributor.makePlan(
            analysis: highAnalysis,
            parameters: parameters,
            gridWidth: grid,
            gridHeight: grid
        )
        let low = try contributor.makePlan(
            analysis: lowAnalysis,
            parameters: parameters,
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertFalse(high.warnings.contains(.lowConfidence))
        XCTAssertTrue(low.warnings.contains(.lowConfidence))
        XCTAssertGreaterThan(low.peakDisplacement, 0)
        XCTAssertLessThan(low.peakDisplacement, high.peakDisplacement * 0.60)
    }

    func testVeryLowConfidenceSkips() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(
            bodyConfidence: 0.10,
            personMask: mask
        )
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.warnings.contains(.lowConfidence))
    }

    func testMultiplePeopleAreSkippedByDefault() throws {
        let twoPeopleMask = try BodyWarpTestSupport.makeMask(twoPeople: true)
        let analysis = BodyWarpTestSupport.analysis(personMask: twoPeopleMask)
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.warnings.contains(.multiplePeople))
    }

    func testMultipleFacesAlsoTriggerTheSafetyPolicy() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(
            personMask: mask,
            faces: [
                BodyWarpTestSupport.face(x: 0.20),
                BodyWarpTestSupport.face(x: 0.60)
            ]
        )
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.warnings.contains(.multiplePeople))
    }

    func testPrimaryBodyPolicyShapesWhileStillWarning() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        var configuration = BodyWarpConfiguration.standard
        configuration.multiplePersonPolicy = .primaryBody
        let contributor = BodyWarpContributor(configuration: configuration)
        let analysis = BodyWarpTestSupport.analysis(
            personMask: mask,
            faces: [
                BodyWarpTestSupport.face(x: 0.20),
                BodyWarpTestSupport.face(x: 0.60)
            ]
        )
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(plan.warnings.contains(.multiplePeople))
        XCTAssertFalse(plan.isEmpty)
        XCTAssertGreaterThan(plan.peakDisplacement, 0)
    }

    func testMissingArmKeepsOtherSideAndWaist() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(
            missingJoints: [.leftWrist],
            personMask: mask
        )
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(plan.warnings.contains(.incompletePose))
        XCTAssertFalse(plan.appliedRegions.contains(.leftArm))
        XCTAssertTrue(plan.appliedRegions.contains(.rightArm))
        XCTAssertTrue(plan.appliedRegions.contains(.waist))
    }

    func testContributeAddsPlanOffsetsToExistingField() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(personMask: mask)
        let parameters = BodyWarpTestSupport.parameters(arm: 0.7, waist: 0.7)
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: parameters,
            gridWidth: grid,
            gridHeight: grid
        )

        var field = try WarpField(width: grid, height: grid)
        try contributor.contribute(
            to: &field,
            analysis: analysis,
            parameters: parameters
        )

        XCTAssertEqual(field.offsets, plan.offsets)
        XCTAssertEqual(field.width, plan.width)
        XCTAssertEqual(field.height, plan.height)
    }

    func testZeroStrengthIsANoOpWithoutWarnings() throws {
        let mask = try BodyWarpTestSupport.makeMask()
        let analysis = BodyWarpTestSupport.analysis(personMask: mask)
        let plan = try contributor.makePlan(
            analysis: analysis,
            parameters: BodyWarpTestSupport.parameters(arm: 0, waist: 0),
            gridWidth: grid,
            gridHeight: grid
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.warnings.isEmpty)
        XCTAssertEqual(plan.peakDisplacement, 0)
    }

    private func magnitude(_ vector: SIMD2<Float>) -> Float {
        (vector.x * vector.x + vector.y * vector.y).squareRoot()
    }

    private func magnitude(_ vector: SIMD2<Double>) -> Double {
        (vector.x * vector.x + vector.y * vector.y).squareRoot()
    }
}
