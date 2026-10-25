import Foundation
import StyleToneCore
import XCTest
@testable import StyleToneGeometry

final class FaceWarpContributorTests: XCTestCase {
    private let protectedKinds: [FaceLandmarkKind] = [
        .leftEye,
        .rightEye,
        .leftEyebrow,
        .rightEyebrow,
        .leftPupil,
        .rightPupil,
        .nose,
        .outerLips,
        .innerLips
    ]

    func testNoFaceIsNoOpWithWarning() throws {
        let plan = try FaceWarpTestSupport.plan([], slim: 1, jaw: 1)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.maximumDisplacement, 0)
        XCTAssertEqual(plan.deformedVertexCount, 0)
        XCTAssertEqual(plan.warnings, [.noFace])

        var field = try WarpField(width: 32, height: 32)
        try FaceWarpContributor().contribute(
            to: &field,
            analysis: FaceWarpTestSupport.analysis([]),
            parameters: GeometryParameters(
                face: FaceParameters(slim: 1, jaw: 1)
            )
        )
        XCTAssertTrue(field.isZero())
    }

    func testZeroStrengthSkipsPlanning() throws {
        let plan = try FaceWarpTestSupport.plan(
            [FaceWarpTestSupport.face()],
            slim: 0,
            jaw: 0
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.faces.isEmpty)
        XCTAssertTrue(plan.warnings.isEmpty)
        XCTAssertTrue(
            plan.offsets.allSatisfy { $0 == SIMD2<Float>(0, 0) }
        )
    }

    func testFullStrengthPreservesEveryFacialFeature() throws {
        let face = FaceWarpTestSupport.face()
        let plan = try FaceWarpTestSupport.plan([face], slim: 1, jaw: 1)
        let field = try FaceWarpTestSupport.field(from: plan)
        var checked = 0

        for kind in protectedKinds {
            for point in face.points(for: kind) {
                let normalized = SIMD2<Float>(
                    Float(point.x),
                    Float(point.y)
                )
                let offset = field.bilinearOffset(at: normalized)
                XCTAssertLessThan(
                    FaceWarpTestSupport.magnitude(offset),
                    1e-7,
                    "\(kind.rawValue) must not move"
                )
                let source = MeshWarpSampler.sourcePosition(
                    for: normalized,
                    field: field
                )
                XCTAssertEqual(
                    source.x,
                    normalized.x,
                    accuracy: 1e-6,
                    "\(kind.rawValue) x"
                )
                XCTAssertEqual(
                    source.y,
                    normalized.y,
                    accuracy: 1e-6,
                    "\(kind.rawValue) y"
                )
                checked += 1
            }
        }

        XCTAssertGreaterThan(checked, 40)
        XCTAssertGreaterThan(plan.maximumDisplacement, 0.01)
    }

    func testHairlineAndForeheadArePinned() throws {
        let face = FaceWarpTestSupport.face()
        let plan = try FaceWarpTestSupport.plan([face], slim: 1, jaw: 1)
        let field = try FaceWarpTestSupport.field(from: plan)
        let metrics = try XCTUnwrap(plan.faces.first)
        let box = face.boundingBox

        let foreheadY = Float(box.y + box.height * 0.02)
        for fraction in [Float(-0.7), 0, 0.7] {
            let point = SIMD2<Float>(
                metrics.centerX + fraction * metrics.halfWidth,
                foreheadY
            )
            XCTAssertEqual(
                field.bilinearOffset(at: point),
                SIMD2<Float>(0, 0),
                "forehead at x fraction \(fraction)"
            )
        }

        let topY = Float(box.y)
        for index in 0 ..< plan.gridWidth {
            let point = SIMD2<Float>(
                Float(index) / Float(plan.gridWidth - 1),
                topY
            )
            XCTAssertEqual(field.bilinearOffset(at: point), SIMD2<Float>(0, 0))
        }
    }

    func testCheeksMoveInwardAndSymmetrically() throws {
        let face = FaceWarpTestSupport.face()
        let plan = try FaceWarpTestSupport.plan([face], slim: 1, jaw: 0)
        let field = try FaceWarpTestSupport.field(from: plan)
        let metrics = try XCTUnwrap(plan.faces.first)
        let y = metrics.eyeY + (metrics.chinY - metrics.eyeY) * 0.5
        let leftPoint = FaceWarpTestSupport.point(
            metrics,
            halfWidthFraction: 0.8,
            verticalFraction: 0.5,
            side: -1
        )
        let rightPoint = FaceWarpTestSupport.point(
            metrics,
            halfWidthFraction: 0.8,
            verticalFraction: 0.5,
            side: 1
        )

        let left = field.bilinearOffset(at: leftPoint)
        let right = field.bilinearOffset(at: rightPoint)

        XCTAssertGreaterThan(left.x, 0.004, "left cheek moves right")
        XCTAssertLessThan(right.x, -0.004, "right cheek moves left")
        XCTAssertEqual(left.x, -right.x, accuracy: 1e-6)
        XCTAssertEqual(left.y, 0, accuracy: 1e-7)
        XCTAssertEqual(right.y, 0, accuracy: 1e-7)

        let centre = field.bilinearOffset(
            at: SIMD2<Float>(metrics.centerX, y)
        )
        XCTAssertEqual(
            FaceWarpTestSupport.magnitude(centre),
            0,
            accuracy: 1e-7
        )
    }

    func testSlimAndJawBandsDiffer() throws {
        let face = FaceWarpTestSupport.face()
        let slimPlan = try FaceWarpTestSupport.plan([face], slim: 1, jaw: 0)
        let slimField = try FaceWarpTestSupport.field(from: slimPlan)
        let slimMetrics = try XCTUnwrap(slimPlan.faces.first)
        let slimCheek = FaceWarpTestSupport.magnitude(
            slimField.bilinearOffset(
                at: FaceWarpTestSupport.point(
                    slimMetrics,
                    halfWidthFraction: 0.8,
                    verticalFraction: 0.5,
                    side: -1
                )
            )
        )
        let slimLower = FaceWarpTestSupport.magnitude(
            slimField.bilinearOffset(
                at: FaceWarpTestSupport.point(
                    slimMetrics,
                    halfWidthFraction: 0.8,
                    verticalFraction: 0.85,
                    side: -1
                )
            )
        )
        XCTAssertGreaterThan(
            slimCheek,
            slimLower,
            "slim should peak in the cheek band"
        )

        let jawPlan = try FaceWarpTestSupport.plan([face], slim: 0, jaw: 1)
        let jawField = try FaceWarpTestSupport.field(from: jawPlan)
        let jawMetrics = try XCTUnwrap(jawPlan.faces.first)
        let jawCheek = FaceWarpTestSupport.magnitude(
            jawField.bilinearOffset(
                at: FaceWarpTestSupport.point(
                    jawMetrics,
                    halfWidthFraction: 0.8,
                    verticalFraction: 0.5,
                    side: -1
                )
            )
        )
        let jawLower = FaceWarpTestSupport.magnitude(
            jawField.bilinearOffset(
                at: FaceWarpTestSupport.point(
                    jawMetrics,
                    halfWidthFraction: 0.8,
                    verticalFraction: 0.85,
                    side: -1
                )
            )
        )
        XCTAssertGreaterThan(
            jawLower,
            jawCheek * 3,
            "jaw should peak near the jaw line"
        )
    }

    func testDisplacementIsMonotonicAndCapped() throws {
        let face = FaceWarpTestSupport.face()
        let magnitudes = try [0.25, 0.5, 1.0].map { strength in
            try FaceWarpTestSupport.plan([face], slim: strength, jaw: 0)
                .maximumDisplacement
        }
        XCTAssertLessThan(magnitudes[0], magnitudes[1])
        XCTAssertLessThan(magnitudes[1], magnitudes[2])

        let fullPlan = try FaceWarpTestSupport.plan([face], slim: 1, jaw: 1)
        let metrics = try XCTUnwrap(fullPlan.faces.first)
        let faceWidth = metrics.halfWidth * 2
        let expectedCap = min(
            FaceWarpConfiguration.standard
                .maximumCombinedDisplacementFraction * faceWidth,
            FaceWarpConfiguration.standard.maximumAbsoluteDisplacement
        )
        XCTAssertLessThanOrEqual(
            fullPlan.maximumDisplacement,
            expectedCap + 1e-6
        )
        XCTAssertGreaterThan(fullPlan.maximumDisplacement, 0.02)

        let tinyCap = FaceWarpConfiguration(
            maximumCombinedDisplacementFraction: 1,
            maximumAbsoluteDisplacement: 0.001
        )
        let cappedPlan = try FaceWarpTestSupport.plan(
            [face],
            slim: 1,
            jaw: 1,
            configuration: tinyCap
        )
        XCTAssertLessThanOrEqual(cappedPlan.maximumDisplacement, 0.001 + 1e-7)

        let clampedParameters = try FaceWarpTestSupport.plan(
            [face],
            slim: 5,
            jaw: 5
        )
        XCTAssertEqual(
            clampedParameters.maximumDisplacement,
            fullPlan.maximumDisplacement,
            accuracy: 1e-7
        )
    }

    func testAsymmetricContourStillProducesSymmetricField() throws {
        let face = FaceWarpTestSupport.face(contourNudge: 0.045)
        let plan = try FaceWarpTestSupport.plan(
            [face],
            slim: 1,
            jaw: 1,
            grid: 32
        )
        let field = try FaceWarpTestSupport.field(from: plan)
        let metrics = try XCTUnwrap(plan.faces.first)
        XCTAssertEqual(metrics.centerX, 0.5, accuracy: 1e-6)

        for y in 0 ..< plan.gridHeight {
            for x in 0 ..< (plan.gridWidth / 2) {
                let left = field.offsets[y * plan.gridWidth + x]
                let right = field.offsets[
                    y * plan.gridWidth + (plan.gridWidth - 1 - x)
                ]
                XCTAssertEqual(left.x, -right.x, accuracy: 2e-6)
                XCTAssertEqual(left.y, right.y, accuracy: 2e-6)
            }
        }
    }

    func testMultipleFacesProcessedLargestFirst() throws {
        let faces = FaceWarpTestSupport.twoFaces()
        let plan = try FaceWarpTestSupport.plan(faces, slim: 1, jaw: 0)
        let field = try FaceWarpTestSupport.field(from: plan)

        XCTAssertEqual(plan.faces.count, 2)
        XCTAssertGreaterThan(
            plan.faces[0].areaFraction,
            plan.faces[1].areaFraction
        )
        XCTAssertTrue(
            plan.warnings.contains { warning in
                if case .multipleFaces(let count) = warning {
                    return count == 2
                }
                return false
            }
        )
        XCTAssertGreaterThan(plan.deformedVertexCount, 0)

        for metrics in plan.faces {
            let point = FaceWarpTestSupport.point(
                metrics,
                halfWidthFraction: 0.8,
                verticalFraction: 0.5,
                side: -1
            )
            let offset = field.bilinearOffset(at: point)
            XCTAssertGreaterThan(
                offset.x,
                0.002,
                "face \(metrics.faceIndex) should be slimmed"
            )
        }
    }

    func testFaceCountLimitKeepsLargestFaces() throws {
        let faces = FaceWarpTestSupport.fiveFaces()
        let configuration = FaceWarpConfiguration(maximumFaceCount: 2)
        let plan = try FaceWarpTestSupport.plan(
            faces,
            slim: 1,
            jaw: 0,
            configuration: configuration
        )

        XCTAssertEqual(plan.faces.count, 2)
        XCTAssertTrue(
            plan.warnings.contains { warning in
                if case .faceCountLimited(let detected, let processed) = warning {
                    return detected == 5 && processed == 2
                }
                return false
            }
        )
        let expectedAreas = faces
            .map { $0.boundingBox.width * $0.boundingBox.height }
            .sorted(by: >)
        XCTAssertEqual(
            plan.faces[0].areaFraction,
            Float(expectedAreas[0]),
            accuracy: 1e-6
        )
        XCTAssertEqual(
            plan.faces[1].areaFraction,
            Float(expectedAreas[1]),
            accuracy: 1e-6
        )
    }

    func testLowConfidenceAndTinyFacesProduceWarnings() throws {
        let lowConfidence = FaceWarpTestSupport.face(confidence: 0.05)
        let tiny = FaceWarpTestSupport.face(
            box: NormalizedRect(
                x: 0.45,
                y: 0.45,
                width: 0.02,
                height: 0.02
            )
        )
        let plan = try FaceWarpTestSupport.plan(
            [lowConfidence, tiny],
            slim: 1
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(
            plan.warnings.contains { warning in
                if case .lowConfidence(let index, _) = warning {
                    return index == 0
                }
                return false
            }
        )
        XCTAssertTrue(
            plan.warnings.contains { warning in
                if case .faceTooSmall(let index, _) = warning {
                    return index == 1
                }
                return false
            }
        )
        XCTAssertTrue(plan.warnings.contains(.noUsableFace))
    }

    func testMissingLandmarksSkippedWithWarning() throws {
        for face in [
            FaceWarpTestSupport.face(includeEyes: false),
            FaceWarpTestSupport.face(includeLowerFeatures: false)
        ] {
            let plan = try FaceWarpTestSupport.plan([face], slim: 1)
            XCTAssertTrue(plan.isEmpty)
            XCTAssertTrue(
                plan.warnings.contains { warning in
                    if case .insufficientLandmarks(let index) = warning {
                        return index == 0
                    }
                    return false
                }
            )
            XCTAssertTrue(plan.warnings.contains(.noUsableFace))
        }
    }

    func testMissingContourFallsBackToBoundingBox() throws {
        let face = FaceWarpTestSupport.face(includeContour: false)
        let plan = try FaceWarpTestSupport.plan([face], slim: 1)
        let field = try FaceWarpTestSupport.field(from: plan)
        let metrics = try XCTUnwrap(plan.faces.first)

        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(metrics.isContourEstimated)
        XCTAssertEqual(metrics.halfWidth, 0.2, accuracy: 1e-6)
        XCTAssertTrue(
            plan.warnings.contains { warning in
                if case .missingFaceContour(let index) = warning {
                    return index == 0
                }
                return false
            }
        )
        let offset = field.bilinearOffset(
            at: FaceWarpTestSupport.point(
                metrics,
                halfWidthFraction: 0.8,
                verticalFraction: 0.5,
                side: -1
            )
        )
        XCTAssertGreaterThan(offset.x, 0.002)
    }

    func testPlanApplicationRejectsDensityMismatch() throws {
        let plan = try FaceWarpTestSupport.plan(
            [FaceWarpTestSupport.face()],
            slim: 1
        )
        var matching = try WarpField(width: 32, height: 32)
        try plan.applying(to: &matching)
        XCTAssertEqual(
            matching.maxMagnitude,
            plan.maximumDisplacement,
            accuracy: 1e-7
        )

        var mismatched = try WarpField(width: 16, height: 16)
        do {
            try plan.applying(to: &mismatched)
            XCTFail("expected a density mismatch")
        } catch {
            XCTAssertEqual(
                error as? GeometryError,
                .invalidGrid(width: 32, height: 32)
            )
        }
        XCTAssertTrue(mismatched.isZero())
    }

    func testPipelinePinsBorderAndAppliesContribution() throws {
        let contributor = FaceWarpContributor()
        let face = FaceWarpTestSupport.face()
        let analysis = FaceWarpTestSupport.analysis([face])
        let parameters = FaceParameters(slim: 1, jaw: 0)
        let plan = try contributor.plan(
            for: analysis,
            parameters: parameters,
            gridDimension: 32
        )
        let pipeline = GeometryPipeline(
            passes: [GeometryPassEntry(phase: .face, pass: contributor)],
            gridDimension: 32
        )
        let field = try pipeline.makeField(
            analysis: analysis,
            parameters: GeometryParameters(face: parameters)
        )

        XCTAssertGreaterThan(field.maxMagnitude, 0.005)
        XCTAssertLessThanOrEqual(
            field.maxMagnitude,
            plan.maximumDisplacement + 1e-6
        )
        for index in 0 ..< 32 {
            XCTAssertEqual(field.offsets[index], SIMD2<Float>(0, 0))
            XCTAssertEqual(
                field.offsets[(31 * 32) + index],
                SIMD2<Float>(0, 0)
            )
            XCTAssertEqual(
                field.offsets[index * 32],
                SIMD2<Float>(0, 0)
            )
            XCTAssertEqual(
                field.offsets[(index * 32) + 31],
                SIMD2<Float>(0, 0)
            )
        }
    }

    func testEngineNeutralIdentityAndWarpedFrame() async throws {
        let image = try GeometryTestSupport.gradientWithBorder(
            width: 64,
            height: 80
        )
        let analysis = PortraitAnalysis(
            imageSize: image.pixelSize,
            faces: [FaceWarpTestSupport.face()],
            body: nil,
            personMask: nil,
            skinMask: nil,
            backgroundEdgeMask: nil,
            warnings: []
        )
        let engine = GeometryRenderingEngine(
            passes: [
                GeometryPassEntry(
                    phase: .face,
                    pass: FaceWarpContributor()
                )
            ],
            configuration: .preview,
            backend: CPUGeometryWarp()
        )

        let neutral = try await engine.warp(
            image,
            analysis: analysis,
            parameters: .neutral,
            body: .neutral,
            backgroundProtection: false
        )
        XCTAssertTrue(neutral.cgImage === image.cgImage)

        let warped = try await engine.warp(
            image,
            analysis: analysis,
            parameters: FaceParameters(slim: 1, jaw: 1),
            body: .neutral,
            backgroundProtection: false
        )
        XCTAssertEqual(warped.pixelSize, image.pixelSize)
        XCTAssertFalse(warped.cgImage === image.cgImage)
        try GeometryTestSupport.assertNoBlackBorder(warped)
    }
}
