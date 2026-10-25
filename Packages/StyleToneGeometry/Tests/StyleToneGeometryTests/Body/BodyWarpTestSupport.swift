import Foundation
import StyleToneCore
@testable import StyleToneGeometry

enum BodyWarpTestSupport {
    static let imageSize = PixelSize(width: 1000, height: 1500)

    static func joints(
        missing: Set<BodyJointKind> = []
    ) -> [BodyJointKind: NormalizedPoint] {
        let all: [BodyJointKind: NormalizedPoint] = [
            .neck: NormalizedPoint(x: 0.50, y: 0.19),
            .leftShoulder: NormalizedPoint(x: 0.37, y: 0.27),
            .rightShoulder: NormalizedPoint(x: 0.63, y: 0.27),
            .leftElbow: NormalizedPoint(x: 0.33, y: 0.43),
            .rightElbow: NormalizedPoint(x: 0.67, y: 0.43),
            .leftWrist: NormalizedPoint(x: 0.35, y: 0.57),
            .rightWrist: NormalizedPoint(x: 0.65, y: 0.57),
            .leftHip: NormalizedPoint(x: 0.445, y: 0.59),
            .rightHip: NormalizedPoint(x: 0.555, y: 0.59),
            .leftKnee: NormalizedPoint(x: 0.44, y: 0.76),
            .rightKnee: NormalizedPoint(x: 0.56, y: 0.76),
            .leftAnkle: NormalizedPoint(x: 0.45, y: 0.93),
            .rightAnkle: NormalizedPoint(x: 0.55, y: 0.93)
        ]
        var filtered = all
        for kind in missing {
            filtered[kind] = nil
        }
        return filtered
    }

    static func body(
        confidence: Float = 0.90,
        missing: Set<BodyJointKind> = []
    ) -> BodyObservation {
        BodyObservation(joints: joints(missing: missing), confidence: confidence)
    }

    static func analysis(
        includeBody: Bool = true,
        bodyConfidence: Float = 0.90,
        missingJoints: Set<BodyJointKind> = [],
        personMask: MaskBuffer?,
        warnings: [AnalysisWarning] = [],
        faces: [FaceObservation] = []
    ) -> PortraitAnalysis {
        PortraitAnalysis(
            imageSize: imageSize,
            faces: faces,
            body: includeBody ? body(confidence: bodyConfidence, missing: missingJoints) : nil,
            personMask: personMask,
            skinMask: nil,
            backgroundEdgeMask: nil,
            warnings: warnings
        )
    }

    static func parameters(arm: Double = 1, waist: Double = 1) -> GeometryParameters {
        GeometryParameters(
            face: .neutral,
            body: BodyParameters(arm: arm, waist: waist),
            backgroundProtection: true
        )
    }

    static func face(x: Double) -> FaceObservation {
        FaceObservation(
            boundingBox: NormalizedRect(x: x, y: 0.08, width: 0.20, height: 0.18),
            landmarks: [:],
            confidence: 0.95
        )
    }

    static func field(for plan: BodyWarpPlan) throws -> WarpField {
        try WarpField(
            width: plan.width,
            height: plan.height,
            offsets: plan.offsets
        )
    }

    /// Converts a normalized warp offset back to short-side image units.
    static func metricOffset(_ offset: SIMD2<Float>) -> SIMD2<Double> {
        let shortSide = Double(min(imageSize.width, imageSize.height))
        return SIMD2<Double>(
            Double(offset.x) * Double(imageSize.width) / shortSide,
            Double(offset.y) * Double(imageSize.height) / shortSide
        )
    }

    /// Synthetic single-person silhouette at 160×240.
    static func makeMask(twoPeople: Bool = false) throws -> MaskBuffer {
        let width = 160
        let height = 240
        var bytes = [UInt8](repeating: 0, count: width * height)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let point = NormalizedPoint(
                    x: (Double(x) + 0.5) / Double(width),
                    y: (Double(y) + 0.5) / Double(height)
                )
                let inside = twoPeople
                    ? isInsideTwoPersonMask(point)
                    : isInsideSinglePersonMask(point)
                if inside {
                    bytes[y * width + x] = 255
                }
            }
        }

        return try MaskBuffer(width: width, height: height, bytes: Data(bytes))
    }

    private static func isInsideSinglePersonMask(_ point: NormalizedPoint) -> Bool {
        let headX = (point.x - 0.50) / 0.075
        let headY = (point.y - 0.145) / 0.055
        if headX * headX + headY * headY <= 1 {
            return true
        }

        if let halfWidth = torsoHalfWidth(at: point.y),
           abs(point.x - 0.50) <= halfWidth
        {
            return true
        }

        let armSegments = [
            (NormalizedPoint(x: 0.37, y: 0.27), NormalizedPoint(x: 0.33, y: 0.43), 0.032),
            (NormalizedPoint(x: 0.33, y: 0.43), NormalizedPoint(x: 0.35, y: 0.57), 0.030),
            (NormalizedPoint(x: 0.63, y: 0.27), NormalizedPoint(x: 0.67, y: 0.43), 0.032),
            (NormalizedPoint(x: 0.67, y: 0.43), NormalizedPoint(x: 0.65, y: 0.57), 0.030)
        ]
        for (start, end, radius) in armSegments {
            if distance(from: point, toSegment: start, end) <= radius {
                return true
            }
        }

        if point.distance(to: NormalizedPoint(x: 0.35, y: 0.57)) <= 0.035
            || point.distance(to: NormalizedPoint(x: 0.65, y: 0.57)) <= 0.035
        {
            return true
        }

        let legSegments = [
            (NormalizedPoint(x: 0.445, y: 0.59), NormalizedPoint(x: 0.44, y: 0.76), 0.048),
            (NormalizedPoint(x: 0.44, y: 0.76), NormalizedPoint(x: 0.45, y: 0.93), 0.040),
            (NormalizedPoint(x: 0.555, y: 0.59), NormalizedPoint(x: 0.56, y: 0.76), 0.048),
            (NormalizedPoint(x: 0.56, y: 0.76), NormalizedPoint(x: 0.55, y: 0.93), 0.040)
        ]
        return legSegments.contains { segment in
            distance(from: point, toSegment: segment.0, segment.1) <= segment.2
        }
    }

    private static func isInsideTwoPersonMask(_ point: NormalizedPoint) -> Bool {
        for center in [0.30, 0.70] {
            if abs(point.x - center) <= 0.075, point.y >= 0.16, point.y <= 0.90 {
                return true
            }
            let headX = (point.x - center) / 0.060
            let headY = (point.y - 0.12) / 0.055
            if headX * headX + headY * headY <= 1 {
                return true
            }
            let legTop = NormalizedPoint(x: center, y: 0.55)
            let legBottom = NormalizedPoint(x: center, y: 0.92)
            if distance(from: point, toSegment: legTop, legBottom) <= 0.045 {
                return true
            }
        }
        return false
    }

    private static func torsoHalfWidth(at y: Double) -> Double? {
        let controls: [(y: Double, halfWidth: Double)] = [
            (0.20, 0.130),
            (0.30, 0.112),
            (0.40, 0.092),
            (0.46, 0.080),
            (0.55, 0.086),
            (0.61, 0.092)
        ]
        guard let first = controls.first, let last = controls.last,
              y >= first.y, y <= last.y
        else {
            return nil
        }
        for index in 0 ..< (controls.count - 1) {
            let lower = controls[index]
            let upper = controls[index + 1]
            if y >= lower.y, y <= upper.y {
                let t = (y - lower.y) / (upper.y - lower.y)
                return lower.halfWidth + (upper.halfWidth - lower.halfWidth) * t
            }
        }
        return last.halfWidth
    }

    private static func distance(
        from point: NormalizedPoint,
        toSegment start: NormalizedPoint,
        _ end: NormalizedPoint
    ) -> Double {
        let vx = end.x - start.x
        let vy = end.y - start.y
        let lengthSquared = vx * vx + vy * vy
        guard lengthSquared > 0 else {
            return point.distance(to: start)
        }
        let projection = ((point.x - start.x) * vx + (point.y - start.y) * vy) / lengthSquared
        let t = min(max(projection, 0), 1)
        return point.distance(
            to: NormalizedPoint(x: start.x + vx * t, y: start.y + vy * t)
        )
    }
}
