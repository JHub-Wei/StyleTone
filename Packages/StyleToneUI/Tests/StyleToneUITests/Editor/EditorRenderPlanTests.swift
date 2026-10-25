import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneUI

final class EditorRenderPlanTests: XCTestCase {
    func testNeutralStyleAndEditsAreNoOp() throws {
        let analysis = try EditorTestFactory.analysis()
        let plan = EditorRenderPlan.make(
            style: MockStyleProfileFactory.natural(),
            analysis: analysis,
            edits: .initial
        )

        XCTAssertTrue(plan.isNoOp)
        XCTAssertTrue(plan.effective.isNeutral)
        XCTAssertFalse(plan.shouldRetouch)
        XCTAssertFalse(plan.shouldWarp)
        XCTAssertFalse(plan.shouldApplyTone)
        XCTAssertFalse(plan.shouldRemoveBlemishes)
    }

    func testZeroStrengthIsNoOpEvenWithNonNeutralStyle() throws {
        let analysis = try EditorTestFactory.analysis()
        let edits = EditorEditState(strength: 0)
        let plan = EditorRenderPlan.make(
            style: MockStyleProfileFactory.standard(),
            analysis: analysis,
            edits: edits
        )

        XCTAssertTrue(plan.isNoOp)
        XCTAssertEqual(plan.strength, 0)
        XCTAssertTrue(plan.effective.isNeutral)
    }

    func testStyleAndManualOffsetsAreAdditiveAndScaledByStrength() throws {
        let analysis = try EditorTestFactory.analysis()
        var edits = EditorEditState.initial
        edits.adjustments.faceSlim = 0.20

        let full = EditorRenderPlan.make(
            style: MockStyleProfileFactory.standard(),
            analysis: analysis,
            edits: edits
        )
        XCTAssertEqual(full.effective.face.slim, 0.45, accuracy: 0.0001)

        edits.setStrength(0.5)
        let half = EditorRenderPlan.make(
            style: MockStyleProfileFactory.standard(),
            analysis: analysis,
            edits: edits
        )
        XCTAssertEqual(half.effective.face.slim, 0.225, accuracy: 0.0001)
    }

    func testNegativeToneOffsetsAreNotClampedToZero() throws {
        let analysis = try EditorTestFactory.analysis()
        var edits = EditorEditState.initial
        edits.adjustments.exposure = -0.40
        edits.adjustments.contrast = -0.20

        let plan = EditorRenderPlan.make(
            style: MockStyleProfileFactory.natural(),
            analysis: analysis,
            edits: edits
        )

        XCTAssertEqual(plan.effective.tone.exposure, -0.40, accuracy: 0.0001)
        XCTAssertEqual(plan.effective.tone.contrast, -0.20, accuracy: 0.0001)
        XCTAssertTrue(plan.shouldApplyTone)
    }

    func testLegLengthZeroMeansUntouchedAndOneIsNeutral() throws {
        let analysis = try EditorTestFactory.analysis()
        var edits = EditorEditState.initial
        edits.adjustments.legLength = 0

        let untouched = EditorRenderPlan.make(
            style: MockStyleProfileFactory.natural(),
            analysis: analysis,
            edits: edits
        )
        XCTAssertEqual(untouched.effective.body.legLength, 1.0, accuracy: 0.0001)

        edits.adjustments.legLength = 1.05
        let lengthened = EditorRenderPlan.make(
            style: MockStyleProfileFactory.natural(),
            analysis: analysis,
            edits: edits
        )
        XCTAssertEqual(lengthened.effective.body.legLength, 1.05, accuracy: 0.0001)
        XCTAssertTrue(lengthened.shouldWarp)
    }

    func testMissingFaceNeutralisesFaceAndSkin() throws {
        let analysis = try EditorTestFactory.analysis(faceCount: 0, includesBody: true)
        var edits = EditorEditState.initial
        edits.adjustments.faceSlim = 0.6
        edits.adjustments.smoothing = 0.4

        let plan = EditorRenderPlan.make(
            style: MockStyleProfileFactory.standard(),
            analysis: analysis,
            edits: edits
        )

        XCTAssertEqual(plan.effective.face, .neutral)
        XCTAssertEqual(plan.effective.skin, .neutral)
        XCTAssertFalse(plan.shouldRetouch)
    }

    func testMissingBodyNeutralisesBody() throws {
        let analysis = try EditorTestFactory.analysis(faceCount: 1, includesBody: false)
        var edits = EditorEditState.initial
        edits.adjustments.waist = 0.5

        let plan = EditorRenderPlan.make(
            style: MockStyleProfileFactory.standard(),
            analysis: analysis,
            edits: edits
        )

        XCTAssertEqual(plan.effective.body, .neutral)
    }

    func testBlemishPointsAreIgnoredAtZeroStrength() throws {
        let analysis = try EditorTestFactory.analysis()
        let point = BlemishPoint(point: NormalizedPoint(x: 0.4, y: 0.4), radius: 0.02)
        let edits = EditorEditState(strength: 0, blemishPoints: [point])

        let plan = EditorRenderPlan.make(
            style: MockStyleProfileFactory.natural(),
            analysis: analysis,
            edits: edits
        )

        XCTAssertFalse(plan.shouldRemoveBlemishes)
        XCTAssertTrue(plan.isNoOp)
    }

    func testBlemishPointsSurviveAtPositiveStrength() throws {
        let analysis = try EditorTestFactory.analysis()
        let point = BlemishPoint(point: NormalizedPoint(x: 0.4, y: 0.4), radius: 0.02)
        let edits = EditorEditState(blemishPoints: [point])

        let plan = EditorRenderPlan.make(
            style: MockStyleProfileFactory.natural(),
            analysis: analysis,
            edits: edits
        )

        XCTAssertTrue(plan.shouldRemoveBlemishes)
        XCTAssertFalse(plan.isNoOp)
        XCTAssertEqual(plan.blemishPoints.count, 1)
    }

    func testBackgroundProtectionIsPreserved() throws {
        let analysis = try EditorTestFactory.analysis()
        var edits = EditorEditState.initial
        edits.adjustments.faceSlim = 0.5
        edits.backgroundProtection = false

        let plan = EditorRenderPlan.make(
            style: MockStyleProfileFactory.natural(),
            analysis: analysis,
            edits: edits
        )

        XCTAssertFalse(plan.backgroundProtection)
        XCTAssertTrue(plan.shouldWarp)
    }

    func testEffectiveValuesStayInsideContractRanges() throws {
        let analysis = try EditorTestFactory.analysis()
        var edits = EditorEditState.initial
        edits.adjustments.faceSlim = 1
        edits.adjustments.jaw = 1
        edits.adjustments.smoothing = 1
        edits.adjustments.legLength = 1.15
        edits.adjustments.exposure = 1
        edits.setStrength(1.5)

        let plan = EditorRenderPlan.make(
            style: MockStyleProfileFactory.extreme(),
            analysis: analysis,
            edits: edits
        )

        XCTAssertLessThanOrEqual(plan.effective.face.slim, 1)
        XCTAssertLessThanOrEqual(plan.effective.skin.smoothing, 1)
        XCTAssertLessThanOrEqual(plan.effective.body.legLength, 1.15)
        XCTAssertLessThanOrEqual(plan.effective.tone.exposure, 1)
        XCTAssertGreaterThanOrEqual(plan.effective.tone.exposure, -1)
    }
}
