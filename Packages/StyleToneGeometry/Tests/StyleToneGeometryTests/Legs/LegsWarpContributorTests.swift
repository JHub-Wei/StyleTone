import CoreGraphics
import Foundation
import GoldenSupport
import StyleToneCore
import StyleToneImaging
import TestShared
import XCTest
@testable import StyleToneGeometry

final class LegsWarpContributorTests: XCTestCase {
    private let pass = LegsWarpContributor()

    private func makePlan(
        analysis: PortraitAnalysis,
        leg: Double = 0,
        legLength: Double = 1.0,
        configuration: LegsWarpConfiguration = .standard,
        grid: Int = 128
    ) throws -> LegsWarpPlan {
        try LegsWarpContributor(configuration: configuration).makePlan(
            analysis: analysis,
            parameters: LegsTestSupport.parameters(leg: leg, legLength: legLength),
            gridDimension: grid
        )
    }

    func testPassIdentifierAndConformance() {
        XCTAssertEqual(LegsWarpContributor.passIdentifier, "legs.slim-lengthen")
        let geometryPass: any GeometryPass = pass
        XCTAssertEqual(geometryPass.identifier, LegsWarpContributor.passIdentifier)
    }

    func testNoBodyIsSafeNoOp() throws {
        let analysis = LegsTestSupport.analysis(body: nil)
        let plan = try makePlan(analysis: analysis, leg: 1, legLength: 1.15)
        XCTAssertEqual(plan.skipReason, .noBody)
        XCTAssertTrue(plan.warnings.contains(.noBody))
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.peakDisplacement, 0)
        XCTAssertTrue(plan.offsets.allSatisfy { $0 == .zero })

        var field = try GeometryTestSupport.constantField(
            width: 32,
            height: 32,
            offset: SIMD2<Float>(0.01, -0.02)
        )
        let before = field.offsets
        try pass.contribute(
            to: &field,
            analysis: analysis,
            parameters: LegsTestSupport.parameters(leg: 1, legLength: 1.15)
        )
        XCTAssertEqual(field.offsets, before)
    }

    func testLowConfidenceIsSkipped() throws {
        let lowConfidenceBody = LegsTestSupport.bodyObservation(confidence: 0.2)
        let lowBody = try makePlan(
            analysis: LegsTestSupport.analysis(body: lowConfidenceBody),
            leg: 1,
            legLength: 1.1
        )
        XCTAssertEqual(lowBody.skipReason, .lowConfidence)
        XCTAssertTrue(lowBody.offsets.allSatisfy { $0 == .zero })

        let warned = try makePlan(
            analysis: LegsTestSupport.analysis(warnings: [.lowConfidence]),
            leg: 1,
            legLength: 1.1
        )
        XCTAssertEqual(warned.skipReason, .lowConfidence)
    }

    func testNeutralParametersAreSkipped() throws {
        let analysis = LegsTestSupport.analysis()
        let plan = try makePlan(analysis: analysis, leg: 0, legLength: 1.0)
        XCTAssertEqual(plan.skipReason, .neutralParameters)
        XCTAssertTrue(plan.warnings.contains(.neutralParameters))
        XCTAssertEqual(plan.effectiveLegLength, 1)
        XCTAssertTrue(plan.isEmpty)
    }

    func testIncompleteJointsAreSkipped() throws {
        let body = LegsTestSupport.bodyObservation(omitted: [.rightAnkle])
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(body: body),
            leg: 1,
            legLength: 1.1
        )
        XCTAssertEqual(plan.skipReason, .incompletePose)
        XCTAssertTrue(plan.warnings.contains(.incompletePose))
        XCTAssertTrue(plan.isEmpty)
    }

    func testCroppedFeetAreSkipped() throws {
        let body = LegsTestSupport.bodyObservation(ankleY: 0.995)
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(body: body),
            leg: 0,
            legLength: 1.15
        )
        XCTAssertEqual(plan.skipReason, .feetOutsideFrame)
        XCTAssertTrue(plan.warnings.contains(.feetOutsideFrame))
        XCTAssertTrue(plan.isEmpty)
    }

    func testInvertedPoseIsSkipped() throws {
        let body = LegsTestSupport.bodyObservation(kneeY: 0.95, ankleY: 0.70)
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(body: body),
            leg: 1,
            legLength: 1.1
        )
        XCTAssertEqual(plan.skipReason, .degeneratePose)
    }

    func testCrossingLegsAreSkipped() throws {
        let body = LegsTestSupport.bodyObservation(
            leftKneeX: 0.60,
            rightKneeX: 0.40
        )
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(body: body),
            leg: 1
        )
        XCTAssertEqual(plan.skipReason, .degeneratePose)
    }

    func testSlimmingMovesContoursTowardsCentrelineSymmetrically() throws {
        let analysis = LegsTestSupport.analysis()
        let plan = try makePlan(analysis: analysis, leg: 0.8, grid: 101)
        XCTAssertNil(plan.skipReason)
        XCTAssertLessThan(plan.peakDisplacement, 0.03)

        let halfWidth = 0.16 * 0.38
        let y = 0.72
        let leftOuter = try LegsTestSupport.offset(plan, x: 0.42 - halfWidth, y: y)
        let leftInner = try LegsTestSupport.offset(plan, x: 0.42 + halfWidth, y: y)
        let leftCentre = try LegsTestSupport.offset(plan, x: 0.42, y: y)
        let rightOuter = try LegsTestSupport.offset(plan, x: 0.58 + halfWidth, y: y)
        let rightInner = try LegsTestSupport.offset(plan, x: 0.58 - halfWidth, y: y)

        XCTAssertGreaterThan(leftOuter.x, 0.005, "left outer contour moves right")
        XCTAssertLessThan(leftInner.x, -0.005, "left inner contour moves left")
        XCTAssertEqual(Double(leftCentre.x), 0, accuracy: 0.0005)
        XCTAssertLessThan(rightOuter.x, -0.005, "right outer contour moves left")
        XCTAssertGreaterThan(rightInner.x, 0.005, "right inner contour moves right")
        XCTAssertEqual(Double(leftOuter.x), -Double(rightOuter.x), accuracy: 0.0005)
        XCTAssertEqual(Double(leftInner.x), -Double(rightInner.x), accuracy: 0.0005)
    }

    func testSlimmingIsZeroAtHipAndBelowAnkle() throws {
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(),
            leg: 1.0,
            grid: 101
        )
        let atHip = try LegsTestSupport.offset(plan, x: 0.42 - 0.06, y: 0.55)
        XCTAssertEqual(Double(atHip.x), 0, accuracy: 0.001)
        for y in [0.90, 0.93, 0.97] {
            let atFoot = try LegsTestSupport.offset(plan, x: 0.40, y: y)
            XCTAssertEqual(atFoot, .zero, "foot y=\(y)")
        }
    }

    func testLengtheningMapsHipContentToShiftedOutput() throws {
        let analysis = LegsTestSupport.analysis()
        let plan = try makePlan(analysis: analysis, legLength: 1.10)
        XCTAssertNil(plan.skipReason)
        XCTAssertEqual(plan.effectiveLegLength, 1.10, accuracy: 1e-9)

        let hip = 0.55
        let ankle = 0.90
        let legLength = ankle - hip
        let scale = 1.10
        let outputHip = ankle - scale * legLength
        let sourceAtOutputHip = try LegsTestSupport.sourceY(
            plan,
            x: 0.50,
            y: outputHip
        )
        XCTAssertEqual(sourceAtOutputHip, hip, accuracy: 0.006)

        let sourceAtAnkle = try LegsTestSupport.sourceY(plan, x: 0.50, y: ankle)
        XCTAssertEqual(sourceAtAnkle, ankle, accuracy: 0.002)

        // The field is exactly zero at and below the ankle on mesh vertices.
        // Bilinear/triangle interpolation between the last vertex just above
        // the ankle and the first vertex below it can still produce a
        // sub-micropixel offset, so the acceptance check uses a pixel-scale
        // tolerance.
        for y in [0.90, 0.93, 0.97] {
            let footOffset = try LegsTestSupport.offset(plan, x: 0.50, y: y)
            XCTAssertEqual(Double(footOffset.x), 0, accuracy: 0.0001, "foot x y=\(y)")
            XCTAssertEqual(Double(footOffset.y), 0, accuracy: 0.0001, "foot y=\(y)")
        }
    }

    func testHipMovesMoreThanKneeAndAnkleStaysFixed() throws {
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(),
            legLength: 1.10
        )
        let hipOffset = try LegsTestSupport.offset(plan, x: 0.50, y: 0.515)
        let kneeOffset = try LegsTestSupport.offset(plan, x: 0.50, y: 0.72)
        let ankleOffset = try LegsTestSupport.offset(plan, x: 0.50, y: 0.90)

        XCTAssertLessThan(hipOffset.y, -0.025)
        XCTAssertLessThan(kneeOffset.y, -0.005)
        XCTAssertGreaterThan(kneeOffset.y, hipOffset.y)
        XCTAssertEqual(Double(ankleOffset.y), 0, accuracy: 0.0001)
        XCTAssertEqual(Double(ankleOffset.x), 0, accuracy: 0.0001)
    }

    func testLengtheningIsMonotonicAndLocallyBounded() throws {
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(),
            legLength: 1.15
        )
        let start = 0.90 - 1.15 * 0.35
        let end = 0.90
        var previousSource = -Double.infinity
        var maximumLocalStretch = 0.0
        var steps = 0
        for index in 0 ... 200 {
            let y = start + (end - start) * Double(index) / 200
            let source = try LegsTestSupport.sourceY(plan, x: 0.50, y: y)
            XCTAssertGreaterThan(
                source,
                previousSource - 1e-6,
                "mapping folded at y=\(y)"
            )
            if index > 0, source > previousSource {
                let step = (end - start) / 200
                maximumLocalStretch = max(
                    maximumLocalStretch,
                    step / (source - previousSource)
                )
                steps += 1
            }
            previousSource = source
        }
        XCTAssertGreaterThan(steps, 0)
        XCTAssertLessThan(maximumLocalStretch, 1.30)
    }

    func testMaximumVerticalDisplacementCapsLengthening() throws {
        let configuration = LegsWarpConfiguration(
            maximumVerticalDisplacement: 0.03
        )
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(),
            legLength: 1.15,
            configuration: configuration
        )
        XCTAssertNil(plan.skipReason)
        XCTAssertEqual(plan.effectiveLegLength, 1 + 0.03 / 0.35, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(plan.peakDisplacement, 0.0301)
        XCTAssertTrue(plan.warnings.contains(.strengthLimited))
    }

    func testPerVertexContributionCapBinds() throws {
        let configuration = LegsWarpConfiguration(maximumContribution: 0.005)
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(),
            leg: 1.0,
            legLength: 1.15,
            configuration: configuration,
            grid: 64
        )
        XCTAssertNil(plan.skipReason)
        XCTAssertTrue(plan.didClampToLimit)
        XCTAssertLessThanOrEqual(plan.peakDisplacement, 0.0051)
    }

    func testConfigurationCapLimitsRequestedLength() throws {
        let configuration = LegsWarpConfiguration(maximumLengthening: 1.08)
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(),
            legLength: 1.15,
            configuration: configuration
        )
        XCTAssertEqual(plan.effectiveLegLength, 1.08, accuracy: 1e-9)
    }

    func testFacesAreProtectedDuringLengthening() throws {
        let analysis = LegsTestSupport.analysis(faces: [LegsTestSupport.face()])
        let plan = try makePlan(analysis: analysis, legLength: 1.15)

        let insideFace = try LegsTestSupport.offset(plan, x: 0.50, y: 0.40)
        XCTAssertEqual(insideFace, .zero, "face bbox must be undisplaced")
        let belowFace = try LegsTestSupport.offset(plan, x: 0.50, y: 0.50)
        XCTAssertLessThan(belowFace.y, -0.005)
    }

    func testOcclusionReducesBothStrengths() throws {
        let analysis = LegsTestSupport.analysis(warnings: [.occlusion])
        let plan = try makePlan(
            analysis: analysis,
            leg: 1.0,
            legLength: 1.15
        )
        XCTAssertEqual(plan.effectiveSlimStrength, 0.5, accuracy: 1e-9)
        XCTAssertEqual(plan.effectiveLegLength, 1.075, accuracy: 1e-9)
        XCTAssertTrue(plan.warnings.contains(.occlusionReduced))
    }

    func testFrameEdgeColumnsArePinned() throws {
        let body = LegsTestSupport.bodyObservation(
            leftHipX: 0.05,
            rightHipX: 0.20
        )
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(body: body),
            leg: 1.0
        )
        let zero = SIMD2<Float>(0, 0)
        for y in 0 ..< plan.height {
            XCTAssertEqual(plan.offset(x: 0, y: y) ?? zero, zero, "y=\(y)")
            XCTAssertEqual(plan.offset(x: plan.width - 1, y: y) ?? zero, zero, "y=\(y)")
        }
    }

    func testPersonMaskGatesBackgroundContent() throws {
        let mask = try MockMaskFactory.rectangle(
            size: LegsTestSupport.defaultSize,
            rect: NormalizedRect(x: 0.40, y: 0.40, width: 0.20, height: 0.60)
        )
        let analysis = LegsTestSupport.analysis(personMask: mask)
        let plan = try makePlan(analysis: analysis, legLength: 1.10)
        let inside = try LegsTestSupport.offset(plan, x: 0.50, y: 0.55)
        let outside = try LegsTestSupport.offset(plan, x: 0.35, y: 0.55)
        XCTAssertLessThan(inside.y, -0.005)
        XCTAssertEqual(outside, .zero)
    }

    func testPlanApplyingAddsToExistingOffsets() throws {
        let plan = try makePlan(
            analysis: LegsTestSupport.analysis(),
            leg: 0.5,
            legLength: 1.05,
            grid: 32
        )
        var field = try GeometryTestSupport.constantField(
            width: 32,
            height: 32,
            offset: SIMD2<Float>(0.01, 0.02)
        )
        let before = field.offsets
        try plan.applying(to: &field)
        for index in before.indices {
            XCTAssertEqual(field.offsets[index], before[index] + plan.offsets[index])
        }
    }

    func testInvalidGridIsRejected() {
        XCTAssertThrowsError(
            try pass.makePlan(
                analysis: LegsTestSupport.analysis(),
                parameters: LegsTestSupport.parameters(leg: 1),
                gridWidth: 1,
                gridHeight: 32
            )
        ) { error in
            XCTAssertEqual(
                error as? GeometryError,
                .invalidGrid(width: 1, height: 32)
            )
        }
    }

    func testNoBlackBorderAndFeetRemainIntact() throws {
        let width = 180
        let height = 240
        let image = try GeometryTestSupport.makeImage(width: width, height: height) { x, y in
            let nx = Double(x) / Double(width - 1)
            let ny = Double(y) / Double(height - 1)
            if ny >= 0.90, ny <= 0.97, (0.34 ... 0.50).contains(nx) || (0.50 ... 0.66).contains(nx) {
                return RGBA8(red: 220, green: 30, blue: 30)
            }
            if ny >= 0.55, ny <= 0.90, (0.36 ... 0.48).contains(nx) || (0.52 ... 0.64).contains(nx) {
                return RGBA8(red: 40, green: 160, blue: 60)
            }
            return RGBA8(red: 200, green: 210, blue: 220)
        }
        let analysis = LegsTestSupport.analysis(
            size: PixelSize(width: width, height: height)
        )
        let pipeline = GeometryPipeline(
            passes: [
                GeometryPassEntry(
                    phase: .legs,
                    pass: LegsWarpContributor()
                )
            ],
            gridDimension: 128
        )
        let field = try pipeline.makeField(
            analysis: analysis,
            parameters: LegsTestSupport.parameters(leg: 0.8, legLength: 1.10)
        )
        XCTAssertFalse(field.isZero())

        let output = try CPUGeometryWarp().warp(
            image,
            field: field,
            configuration: GeometryWarpConfiguration(
                quality: .export,
                allowsIdentityShortcut: false
            )
        )
        try GeometryTestSupport.assertNoBlackBorder(output, border: 1)

        let sourcePixels = try GeometryTestSupport.pixels(of: image)
        let outputPixels = try GeometryTestSupport.pixels(of: output)
        var sourceRed = 0
        var outputRed = 0
        for y in Int(0.84 * Double(height)) ..< Int(0.98 * Double(height)) {
            for x in 0 ..< width {
                let nx = Double(x) / Double(width - 1)
                guard (0.34 ... 0.66).contains(nx) else { continue }
                let sourcePixel = sourcePixels[x, y]
                if sourcePixel.red > 180, sourcePixel.green < 80 {
                    sourceRed += 1
                }
                let outputPixel = outputPixels[x, y]
                if outputPixel.red > 180, outputPixel.green < 80 {
                    outputRed += 1
                }
            }
        }
        XCTAssertGreaterThan(sourceRed, 100)
        XCTAssertGreaterThanOrEqual(outputRed, Int(Double(sourceRed) * 0.95))
    }

    func testPlanningPerformanceAtExportDensity() throws {
        let mask = try MockMaskFactory.solid(
            value: 255,
            size: LegsTestSupport.defaultSize
        )
        let analysis = LegsTestSupport.analysis(personMask: mask)
        let parameters = LegsTestSupport.parameters(leg: 0.8, legLength: 1.08)
        let sample = try GeometryPerformanceProbe.measure(
            operation: "legs.plan.1080p",
            backend: "legs.cpu",
            gridDimension: 64,
            pixelSize: LegsTestSupport.defaultSize,
            iterations: 8,
            warmUpIterations: 2
        ) {
            _ = try LegsWarpContributor().makePlan(
                analysis: analysis,
                parameters: parameters,
                gridDimension: 64
            )
        }
        print(sample.summary)
        if ProcessInfo.processInfo.environment["ST_LEGS_PERF_STRICT"] == "1" {
            XCTAssertLessThan(sample.p95Seconds, 0.5)
        }
    }
}
