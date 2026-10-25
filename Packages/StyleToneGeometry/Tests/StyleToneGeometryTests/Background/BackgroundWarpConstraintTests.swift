import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneGeometry

private struct ConstantDisplacementPass: GeometryPass {
    let identifier = "test.constant"
    func contribute(
        to field: inout WarpField,
        analysis: PortraitAnalysis,
        parameters: GeometryParameters
    ) throws {
        for index in field.offsets.indices {
            field.offsets[index] = SIMD2<Float>(0.01, 0)
        }
    }
}

/// Behavior tests for the WP-15 background protection constraint.
final class BackgroundWarpConstraintTests: XCTestCase {
    private let constraint = BackgroundWarpConstraint()

    // MARK: Detection + line rigidity

    func testDoorFrameWaveIsStraightened() throws {
        let edgeMask = try BackgroundTestSupport.doorFrameMask()
        let analysis = BackgroundTestSupport.analysis(edgeMask: edgeMask)
        let field = try BackgroundTestSupport.horizontalWaveField(
            dimension: 64,
            amplitude: 0.02,
            cycles: 1
        )

        let plan = try constraint.makePlan(field: field, analysis: analysis)

        XCTAssertGreaterThanOrEqual(plan.lines.count, 4)
        XCTAssertGreaterThanOrEqual(plan.rectangles.count, 1)
        XCTAssertGreaterThan(
            plan.metrics.maximumLineDeviationBefore,
            0.008,
            "the sine wave must visibly bend the vertical lines before protection"
        )
        XCTAssertLessThan(
            plan.metrics.maximumLineDeviationAfter,
            0.0015,
            "a rigid line must not bend after protection"
        )
        XCTAssertLessThan(
            plan.metrics.maximumLineDeviationAfter,
            plan.metrics.maximumLineDeviationBefore * 0.25
        )
        XCTAssertLessThan(
            plan.metrics.maximumStructureDisplacementAfter,
            0.004
        )
        XCTAssertGreaterThan(
            plan.metrics.backgroundRetention,
            0,
            "the plan must keep some background motion to avoid a hard seam"
        )
        XCTAssertLessThan(plan.metrics.backgroundRetention, 0.7)

        // The right jamb at x ≈ 0.778 coincides with field column 49; its
        // protection must be near full.
        let protection = try XCTUnwrap(plan.protectionWeight(x: 49, y: 31))
        XCTAssertGreaterThan(protection, 0.8)
    }

    func testTableEdgeBumpIsFlattened() throws {
        let edgeMask = try BackgroundTestSupport.tableEdgeMask()
        let analysis = BackgroundTestSupport.analysis(edgeMask: edgeMask)
        let field = try BackgroundTestSupport.verticalBumpField(
            dimension: 64,
            amplitude: 0.02,
            centerX: 0.5,
            centerY: 0.58,
            sigma: 0.10
        )

        let plan = try constraint.makePlan(field: field, analysis: analysis)

        XCTAssertEqual(plan.lines.count, 1)
        XCTAssertEqual(plan.lines.first?.orientation, .horizontal)
        XCTAssertTrue(plan.rectangles.isEmpty)
        XCTAssertGreaterThan(plan.metrics.maximumLineDeviationBefore, 0.005)
        XCTAssertLessThan(plan.metrics.maximumLineDeviationAfter, 0.001)
        XCTAssertLessThan(
            plan.metrics.maximumLineDeviationAfter,
            plan.metrics.maximumLineDeviationBefore * 0.2
        )
        XCTAssertLessThan(
            plan.metrics.maximumStructureDisplacementAfter,
            0.004
        )
    }

    func testFloorTilesDetectRectanglesAndProtectSeams() throws {
        let edgeMask = try BackgroundTestSupport.gridMask()
        let analysis = BackgroundTestSupport.analysis(edgeMask: edgeMask)
        let field = try BackgroundTestSupport.constantField(
            dimension: 64,
            offset: SIMD2<Float>(0.01, 0)
        )

        let plan = try constraint.makePlan(field: field, analysis: analysis)

        XCTAssertGreaterThanOrEqual(plan.lines.count, 8)
        XCTAssertGreaterThanOrEqual(plan.rectangles.count, 6)

        // A seam vertex at (25/63 ≈ 0.397) is fully protected.
        let seamProtection = try XCTUnwrap(plan.protectionWeight(x: 25, y: 25))
        XCTAssertGreaterThan(seamProtection, 0.8)

        // A tile centre gets rectangle fill protection but less than a seam.
        let centreProtection = try XCTUnwrap(plan.protectionWeight(x: 19, y: 19))
        XCTAssertGreaterThan(centreProtection, 0.3)
        XCTAssertLessThan(centreProtection, seamProtection)

        XCTAssertLessThan(plan.metrics.backgroundRetention, 0.65)
        XCTAssertLessThan(plan.metrics.maximumStructureDisplacementAfter, 0.006)
    }

    func testDiagonalEdgeGetsGenericEdgeProtection() throws {
        let edgeMask = try BackgroundTestSupport.diagonalMask()
        let analysis = BackgroundTestSupport.analysis(edgeMask: edgeMask)
        let field = try BackgroundTestSupport.constantField(
            dimension: 64,
            offset: SIMD2<Float>(0.01, 0)
        )

        let plan = try constraint.makePlan(field: field, analysis: analysis)

        XCTAssertTrue(plan.lines.isEmpty)
        XCTAssertTrue(plan.warnings.contains(.noStructureDetected))
        let maximumProtection = plan.protectionWeights.max() ?? 0
        XCTAssertGreaterThan(maximumProtection, 0.25)
    }

    // MARK: Subject support

    func testFaceSlimmingIsNotWeakened() throws {
        let personMask = try BackgroundTestSupport.personMask()
        let edgeMask = try BackgroundTestSupport.doorFrameMask()
        let analysis = BackgroundTestSupport.analysis(
            faces: [BackgroundTestSupport.face()],
            body: BackgroundTestSupport.body(),
            personMask: personMask,
            edgeMask: edgeMask
        )
        let field = try BackgroundTestSupport.faceField(
            analysis: analysis,
            dimension: 64
        )
        XCTAssertGreaterThan(field.maxMagnitude, 0.001)

        var protectedField = field
        try constraint.constrain(&protectedField, analysis: analysis)
        let plan = try constraint.makePlan(field: field, analysis: analysis)

        var checked = 0
        var maximumDifference: Float = 0
        for index in field.offsets.indices where plan.subjectSupport[index] >= 0.99999 {
            if BackgroundTestSupport.magnitude(field.offsets[index]) > 0 {
                checked += 1
            }
            maximumDifference = max(
                maximumDifference,
                BackgroundTestSupport.magnitude(
                    field.offsets[index] - protectedField.offsets[index]
                )
            )
        }
        XCTAssertGreaterThan(checked, 10, "the face must have moving vertices")
        XCTAssertLessThan(maximumDifference, 1e-6)
        XCTAssertGreaterThan(plan.metrics.subjectRetention, 0.999)

        let faceRect = MockPortraitAnalysisFactory.defaultFaceRect
        XCTAssertEqual(
            BackgroundTestSupport.meanMagnitude(protectedField, in: faceRect),
            BackgroundTestSupport.meanMagnitude(field, in: faceRect),
            accuracy: 1e-5
        )
    }

    func testPersonMaskKeepsSubjectAndDampsBackground() throws {
        let personMask = try BackgroundTestSupport.personMask()
        let analysis = BackgroundTestSupport.analysis(personMask: personMask)
        let field = try BackgroundTestSupport.constantField(
            dimension: 64,
            offset: SIMD2<Float>(0.01, 0)
        )

        var protectedField = field
        try constraint.constrain(&protectedField, analysis: analysis)
        let plan = try constraint.makePlan(field: field, analysis: analysis)

        let centre = try XCTUnwrap(protectedField.offset(x: 31, y: 31))
        XCTAssertEqual(centre.x, 0.01, accuracy: 1e-6)
        let corner = try XCTUnwrap(protectedField.offset(x: 0, y: 0))
        XCTAssertEqual(corner.x, 0.006, accuracy: 1e-5)
        XCTAssertEqual(plan.metrics.subjectRetention, 1, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(plan.metrics.backgroundRetention, 0.6 - 1e-5)
        XCTAssertLessThan(plan.metrics.backgroundRetention, 0.75)
    }

    func testEmptyPersonMaskFallsBackToFaceBox() throws {
        let emptyMask = try MockMaskFactory.solid(
            value: 0,
            size: BackgroundTestSupport.size
        )
        let analysis = BackgroundTestSupport.analysis(
            faces: [BackgroundTestSupport.face()],
            personMask: emptyMask
        )
        let field = try BackgroundTestSupport.constantField(
            dimension: 64,
            offset: SIMD2<Float>(0.01, 0)
        )

        let plan = try constraint.makePlan(field: field, analysis: analysis)

        XCTAssertTrue(plan.warnings.contains(.subjectMaskEmpty))
        let faceCentre = try XCTUnwrap(plan.support(x: 31, y: 20))
        XCTAssertGreaterThan(faceCentre, 0.9)
        XCTAssertGreaterThan(plan.metrics.subjectRetention, 0.99)
    }

    // MARK: Degradation + toggles

    func testMissingEdgeMaskWarnsAndStillDampsBackground() throws {
        let analysis = BackgroundTestSupport.analysis()
        let field = try BackgroundTestSupport.constantField(
            dimension: 32,
            offset: SIMD2<Float>(0.01, 0)
        )

        var protectedField = field
        try constraint.constrain(&protectedField, analysis: analysis)
        let plan = try constraint.makePlan(field: field, analysis: analysis)

        XCTAssertTrue(plan.warnings.contains(.edgeMaskUnavailable))
        XCTAssertTrue(plan.warnings.contains(.subjectRegionUnavailable))
        XCTAssertTrue(plan.lines.isEmpty)
        XCTAssertTrue(plan.rectangles.isEmpty)
        XCTAssertEqual(plan.metrics.backgroundRetention, 0.6, accuracy: 0.01)
        XCTAssertEqual(
            protectedField.offsets[0].x,
            0.006,
            accuracy: 1e-6
        )
    }

    func testEmptyEdgeMaskWarns() throws {
        let emptyMask = try MockMaskFactory.solid(
            value: 0,
            size: BackgroundTestSupport.size
        )
        let analysis = BackgroundTestSupport.analysis(edgeMask: emptyMask)
        let field = try BackgroundTestSupport.constantField(
            dimension: 32,
            offset: SIMD2<Float>(0.01, 0)
        )
        let plan = try constraint.makePlan(field: field, analysis: analysis)
        XCTAssertTrue(plan.warnings.contains(.edgeMaskEmpty))
        XCTAssertFalse(plan.warnings.contains(.noStructureDetected))
    }

    func testMaskSizeMismatchStillUsesNormalizedGeometry() throws {
        let size = BackgroundTestSupport.size
        let smallSize = PixelSize(width: 120, height: 90)
        let edgeMask = try BackgroundTestSupport.doorFrameMask(size: smallSize)
        let analysis = BackgroundTestSupport.analysis(size: size, edgeMask: edgeMask)
        let field = try BackgroundTestSupport.constantField(
            dimension: 32,
            offset: SIMD2<Float>(0.01, 0)
        )
        let plan = try constraint.makePlan(field: field, analysis: analysis)

        XCTAssertTrue(plan.warnings.contains(
            .maskSizeMismatch(expected: size, actual: smallSize)
        ))
        XCTAssertGreaterThanOrEqual(plan.lines.count, 3)
    }

    func testRiskAssessmentReportsDisabledSwitch() throws {
        let edgeMask = try BackgroundTestSupport.doorFrameMask()
        let analysis = BackgroundTestSupport.analysis(edgeMask: edgeMask)
        let field = try BackgroundTestSupport.horizontalWaveField(
            dimension: 32,
            amplitude: 0.02
        )

        let risky = try constraint.assessRisk(
            field: field,
            analysis: analysis,
            protectionEnabled: false
        )
        XCTAssertNotEqual(risky.level, .low)
        XCTAssertGreaterThan(risky.riskyVertexCount, 0)
        XCTAssertGreaterThan(risky.structureVertexCount, 0)
        XCTAssertTrue(risky.warnings.contains(.protectionDisabled))
        XCTAssertTrue(risky.warnings.contains {
            if case .protectionDisabledWithStructures(_, _, _) = $0 {
                return true
            }
            return false
        })

        let protected = try constraint.assessRisk(
            field: field,
            analysis: analysis,
            protectionEnabled: true
        )
        XCTAssertEqual(protected.level, .low)
        XCTAssertFalse(protected.warnings.contains(.protectionDisabled))
        XCTAssertEqual(protected.metrics.residualRiskyVertexCount, 0)
        XCTAssertLessThan(protected.metrics.maximumStructureDisplacementAfter, 0.006)
    }

    func testDisabledSwitchWithoutStructuresOnlyReportsInfo() throws {
        let analysis = BackgroundTestSupport.analysis()
        let field = try BackgroundTestSupport.constantField(
            dimension: 32,
            offset: SIMD2<Float>(0.01, 0)
        )
        let risk = try constraint.assessRisk(
            field: field,
            analysis: analysis,
            protectionEnabled: false
        )
        XCTAssertEqual(risk.level, .low)
        XCTAssertTrue(risk.warnings.contains(.protectionDisabled))
        XCTAssertFalse(risk.warnings.contains {
            if case .protectionDisabledWithStructures(_, _, _) = $0 {
                return true
            }
            return false
        })
    }

    func testPipelineToggleRunsConstraintOnlyWhenEnabled() throws {
        let edgeMask = try BackgroundTestSupport.doorFrameMask()
        let analysis = BackgroundTestSupport.analysis(edgeMask: edgeMask)
        let pipeline = GeometryPipeline(
            passes: [GeometryPassEntry(phase: .face, pass: ConstantDisplacementPass())],
            backgroundConstraint: constraint,
            gridDimension: 16
        )

        let protected = try pipeline.makeField(
            analysis: analysis,
            parameters: GeometryParameters(backgroundProtection: true)
        )
        let unprotected = try pipeline.makeField(
            analysis: analysis,
            parameters: GeometryParameters(backgroundProtection: false)
        )
        XCTAssertLessThan(protected.maxMagnitude, unprotected.maxMagnitude)
        XCTAssertNotEqual(protected.offsets, unprotected.offsets)
    }

    // MARK: Plan mechanics

    func testZeroFieldIsNoOp() throws {
        let analysis = BackgroundTestSupport.analysis(
            edgeMask: try BackgroundTestSupport.doorFrameMask()
        )
        let field = try WarpField(width: 32, height: 32)
        var protectedField = field
        try constraint.constrain(&protectedField, analysis: analysis)

        XCTAssertTrue(protectedField.isZero())
        let plan = try constraint.makePlan(field: field, analysis: analysis)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.warnings.isEmpty)
        XCTAssertEqual(plan.metrics.maximumDisplacementBefore, 0)
    }

    func testPlanApplicationRejectsMismatchedGrid() throws {
        let analysis = BackgroundTestSupport.analysis()
        let field = try BackgroundTestSupport.constantField(dimension: 32)
        let plan = try constraint.makePlan(field: field, analysis: analysis)
        var other = try WarpField(width: 16, height: 16)
        XCTAssertThrowsError(try plan.applyingConstraint(to: &other)) { error in
            guard case GeometryError.invalidGrid(_, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testConstraintMatchesApplyingPlan() throws {
        let analysis = BackgroundTestSupport.analysis(
            edgeMask: try BackgroundTestSupport.tableEdgeMask()
        )
        let field = try BackgroundTestSupport.verticalBumpField(
            dimension: 32,
            amplitude: 0.02
        )
        let plan = try constraint.makePlan(field: field, analysis: analysis)
        var applied = field
        try plan.applyingConstraint(to: &applied)
        var constrained = field
        try constraint.constrain(&constrained, analysis: analysis)
        XCTAssertEqual(applied.offsets, constrained.offsets)
    }

    func testPlansAreDeterministic() throws {
        let analysis = BackgroundTestSupport.analysis(
            edgeMask: try BackgroundTestSupport.gridMask()
        )
        let field = try BackgroundTestSupport.horizontalWaveField(
            dimension: 32,
            amplitude: 0.02
        )
        let first = try constraint.makePlan(field: field, analysis: analysis)
        let second = try constraint.makePlan(field: field, analysis: analysis)

        XCTAssertEqual(first.constrainedOffsets, second.constrainedOffsets)
        XCTAssertEqual(first.lines, second.lines)
        XCTAssertEqual(first.rectangles, second.rectangles)
        XCTAssertEqual(first.metrics, second.metrics)
        XCTAssertEqual(first.warnings, second.warnings)
    }

    func testConstraintIdentifierIsStable() {
        XCTAssertEqual(
            BackgroundWarpConstraint.constraintIdentifier,
            "background.structure-protection"
        )
        XCTAssertEqual(constraint.identifier, BackgroundWarpConstraint.constraintIdentifier)
    }
}
