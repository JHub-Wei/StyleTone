import Foundation
import StyleToneCore
@testable import StyleToneGeometry

enum LegsTestSupport {
    static let defaultSize = PixelSize(width: 1080, height: 1440)

    static func bodyObservation(
        hipY: Double = 0.55,
        kneeY: Double = 0.72,
        ankleY: Double = 0.90,
        leftHipX: Double = 0.42,
        rightHipX: Double = 0.58,
        leftKneeX: Double? = nil,
        rightKneeX: Double? = nil,
        leftAnkleX: Double? = nil,
        rightAnkleX: Double? = nil,
        omitted: Set<BodyJointKind> = [],
        confidence: Float = 0.9
    ) -> BodyObservation {
        var joints: [BodyJointKind: NormalizedPoint] = [:]
        let values: [(BodyJointKind, Double, Double)] = [
            (.leftHip, leftHipX, hipY),
            (.rightHip, rightHipX, hipY),
            (.leftKnee, leftKneeX ?? leftHipX, kneeY),
            (.rightKnee, rightKneeX ?? rightHipX, kneeY),
            (.leftAnkle, leftAnkleX ?? leftHipX, ankleY),
            (.rightAnkle, rightAnkleX ?? rightHipX, ankleY)
        ]
        for (kind, x, y) in values where !omitted.contains(kind) {
            joints[kind] = NormalizedPoint(x: x, y: y)
        }
        return BodyObservation(joints: joints, confidence: confidence)
    }

    static func face(
        boundingBox: NormalizedRect = NormalizedRect(
            x: 0.35,
            y: 0.15,
            width: 0.30,
            height: 0.30
        )
    ) -> FaceObservation {
        FaceObservation(
            boundingBox: boundingBox,
            landmarks: [:],
            confidence: 0.95
        )
    }

    static func analysis(
        body: BodyObservation? = LegsTestSupport.bodyObservation(),
        faces: [FaceObservation] = [],
        personMask: MaskBuffer? = nil,
        warnings: [AnalysisWarning] = [],
        size: PixelSize = defaultSize
    ) -> PortraitAnalysis {
        PortraitAnalysis(
            imageSize: size,
            faces: faces,
            body: body,
            personMask: personMask,
            skinMask: nil,
            backgroundEdgeMask: nil,
            warnings: warnings
        )
    }

    static func parameters(
        leg: Double = 0,
        legLength: Double = 1.0
    ) -> GeometryParameters {
        GeometryParameters(
            body: BodyParameters(leg: leg, legLength: legLength)
        )
    }

    static func field(from plan: LegsWarpPlan) throws -> WarpField {
        try WarpField(
            width: plan.width,
            height: plan.height,
            offsets: plan.offsets
        )
    }

    static func offset(
        _ plan: LegsWarpPlan,
        x: Double,
        y: Double
    ) throws -> SIMD2<Float> {
        try field(from: plan).bilinearOffset(
            at: SIMD2<Float>(Float(x), Float(y))
        )
    }

    static func sourceY(
        _ plan: LegsWarpPlan,
        x: Double,
        y: Double
    ) throws -> Double {
        let source = MeshWarpSampler.sourcePosition(
            for: SIMD2<Float>(Float(x), Float(y)),
            field: try field(from: plan)
        )
        return Double(source.y)
    }
}
