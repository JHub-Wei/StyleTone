import Foundation
import StyleToneCore
@testable import StyleToneGeometry

/// Deterministic synthetic faces and helpers for the WP-12 tests.
///
/// Coordinates are top-left normalized (y down), matching `PortraitAnalysis`,
/// `WarpField` and the renderer. Nothing here reads a real image.
enum FaceWarpTestSupport {
    static let imageSize = PixelSize(width: 1080, height: 1440)
    static let grid = 32

    static func face(
        box: NormalizedRect = NormalizedRect(
            x: 0.30,
            y: 0.20,
            width: 0.40,
            height: 0.40
        ),
        confidence: Float = 0.95,
        contourNudge: Double = 0,
        includeContour: Bool = true,
        includeEyes: Bool = true,
        includeLowerFeatures: Bool = true
    ) -> FaceObservation {
        let centerX = box.x + box.width * 0.5
        let eyeY = box.y + box.height * 0.36
        let eyeOffsetX = box.width * 0.18
        let mouthY = box.y + box.height * 0.70
        var landmarks: [FaceLandmarkKind: [NormalizedPoint]] = [:]

        if includeContour {
            landmarks[.faceContour] = ellipse(
                centerX: centerX,
                centerY: box.y + box.height * 0.5,
                radiusX: box.width * 0.5,
                radiusY: box.height * 0.5,
                count: 32
            ).map { point in
                guard contourNudge != 0, point.x > centerX else {
                    return point
                }
                return NormalizedPoint(
                    x: point.x + contourNudge * box.width,
                    y: point.y
                ).clamped()
            }
        }

        if includeEyes {
            let leftCenter = NormalizedPoint(
                x: centerX - eyeOffsetX,
                y: eyeY
            )
            let rightCenter = NormalizedPoint(
                x: centerX + eyeOffsetX,
                y: eyeY
            )
            landmarks[.leftEye] = ellipse(
                centerX: leftCenter.x,
                centerY: leftCenter.y,
                radiusX: box.width * 0.07,
                radiusY: box.height * 0.03,
                count: 8
            )
            landmarks[.rightEye] = ellipse(
                centerX: rightCenter.x,
                centerY: rightCenter.y,
                radiusX: box.width * 0.07,
                radiusY: box.height * 0.03,
                count: 8
            )
            landmarks[.leftPupil] = [leftCenter]
            landmarks[.rightPupil] = [rightCenter]
            landmarks[.leftEyebrow] = eyebrow(
                centerX: leftCenter.x,
                y: eyeY - box.height * 0.07,
                width: box.width * 0.12,
                count: 5
            )
            landmarks[.rightEyebrow] = eyebrow(
                centerX: rightCenter.x,
                y: eyeY - box.height * 0.07,
                width: box.width * 0.12,
                count: 5
            )
        }

        if includeLowerFeatures {
            landmarks[.nose] = [
                NormalizedPoint(x: centerX, y: eyeY + box.height * 0.16),
                NormalizedPoint(
                    x: centerX - box.width * 0.02,
                    y: eyeY + box.height * 0.22
                ),
                NormalizedPoint(
                    x: centerX + box.width * 0.02,
                    y: eyeY + box.height * 0.22
                )
            ]
            landmarks[.outerLips] = ellipse(
                centerX: centerX,
                centerY: mouthY,
                radiusX: box.width * 0.15,
                radiusY: box.height * 0.05,
                count: 12
            )
            landmarks[.innerLips] = ellipse(
                centerX: centerX,
                centerY: mouthY,
                radiusX: box.width * 0.09,
                radiusY: box.height * 0.025,
                count: 8
            )
        }

        return FaceObservation(
            boundingBox: box.clamped(),
            landmarks: landmarks,
            confidence: confidence
        )
    }

    static func analysis(_ faces: [FaceObservation]) -> PortraitAnalysis {
        PortraitAnalysis(
            imageSize: imageSize,
            faces: faces,
            body: nil,
            personMask: nil,
            skinMask: nil,
            backgroundEdgeMask: nil,
            warnings: []
        )
    }

    static func plan(
        _ faces: [FaceObservation],
        slim: Double = 1,
        jaw: Double = 0,
        grid: Int = 32,
        configuration: FaceWarpConfiguration = .standard
    ) throws -> FaceWarpPlan {
        try FaceWarpContributor(configuration: configuration).plan(
            for: analysis(faces),
            parameters: FaceParameters(slim: slim, jaw: jaw),
            gridDimension: grid
        )
    }

    static func field(from plan: FaceWarpPlan) throws -> WarpField {
        var field = try WarpField(width: plan.gridWidth, height: plan.gridHeight)
        try plan.applying(to: &field)
        return field
    }

    static func magnitude(_ offset: SIMD2<Float>) -> Float {
        (offset.x * offset.x + offset.y * offset.y).squareRoot()
    }

    static func point(
        _ metrics: FaceWarpFaceMetrics,
        halfWidthFraction: Float,
        verticalFraction: Float,
        side: Float
    ) -> SIMD2<Float> {
        SIMD2<Float>(
            metrics.centerX + side * metrics.halfWidth * halfWidthFraction,
            metrics.eyeY + (metrics.chinY - metrics.eyeY) * verticalFraction
        )
    }

    /// Two well-separated faces; the left one is larger.
    static func twoFaces() -> [FaceObservation] {
        [
            face(
                box: NormalizedRect(
                    x: 0.06,
                    y: 0.20,
                    width: 0.32,
                    height: 0.36
                )
            ),
            face(
                box: NormalizedRect(
                    x: 0.58,
                    y: 0.24,
                    width: 0.24,
                    height: 0.28
                )
            )
        ]
    }

    /// Three well-separated faces for contribution performance coverage.
    static func threeFaces() -> [FaceObservation] {
        [
            face(
                box: NormalizedRect(
                    x: 0.06,
                    y: 0.22,
                    width: 0.24,
                    height: 0.30
                )
            ),
            face(
                box: NormalizedRect(
                    x: 0.38,
                    y: 0.18,
                    width: 0.26,
                    height: 0.32
                )
            ),
            face(
                box: NormalizedRect(
                    x: 0.70,
                    y: 0.24,
                    width: 0.22,
                    height: 0.28
                )
            )
        ]
    }

    /// Five faces with strictly decreasing areas.
    static func fiveFaces() -> [FaceObservation] {
        [
            face(
                box: NormalizedRect(
                    x: 0.03,
                    y: 0.20,
                    width: 0.14,
                    height: 0.20
                )
            ),
            face(
                box: NormalizedRect(
                    x: 0.20,
                    y: 0.20,
                    width: 0.12,
                    height: 0.18
                )
            ),
            face(
                box: NormalizedRect(
                    x: 0.35,
                    y: 0.20,
                    width: 0.10,
                    height: 0.16
                )
            ),
            face(
                box: NormalizedRect(
                    x: 0.48,
                    y: 0.20,
                    width: 0.08,
                    height: 0.14
                )
            ),
            face(
                box: NormalizedRect(
                    x: 0.60,
                    y: 0.20,
                    width: 0.06,
                    height: 0.12
                )
            )
        ]
    }

    private static func ellipse(
        centerX: Double,
        centerY: Double,
        radiusX: Double,
        radiusY: Double,
        count: Int
    ) -> [NormalizedPoint] {
        (0 ..< count).map { index in
            let angle = Double(index) / Double(count) * 2 * Double.pi
            return NormalizedPoint(
                x: centerX + cos(angle) * radiusX,
                y: centerY + sin(angle) * radiusY
            ).clamped()
        }
    }

    private static func eyebrow(
        centerX: Double,
        y: Double,
        width: Double,
        count: Int
    ) -> [NormalizedPoint] {
        (0 ..< count).map { index in
            let fraction = Double(index) / Double(count - 1) - 0.5
            return NormalizedPoint(
                x: centerX + fraction * width,
                y: y + abs(fraction) * width * 0.1
            ).clamped()
        }
    }
}
