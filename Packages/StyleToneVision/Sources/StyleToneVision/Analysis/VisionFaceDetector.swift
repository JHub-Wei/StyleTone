import CoreGraphics
import Foundation
import ImageIO
import StyleToneCore
import Vision

/// One face-landmark pass over the analysis proxy.
struct FaceDetectionOutcome {
    let faces: [StyleToneCore.FaceObservation]
    /// Vision's capture-quality score for the largest accepted face, if any.
    let primaryCaptureQuality: Float?
    let failed: Bool
}

/// Wraps `VNDetectFaceLandmarksRequest` and converts its observations into the
/// Core landmark model.
enum VisionFaceDetector {
    static func detect(
        in cgImage: CGImage,
        configuration: VisionAnalysisConfiguration
    ) -> FaceDetectionOutcome {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation.up,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            return FaceDetectionOutcome(faces: [], primaryCaptureQuality: nil, failed: true)
        }

        let observations = (request.results ?? []).sorted { lhs, rhs in
            let lhsArea = lhs.boundingBox.width * lhs.boundingBox.height
            let rhsArea = rhs.boundingBox.width * rhs.boundingBox.height
            if lhsArea == rhsArea {
                return lhs.confidence > rhs.confidence
            }
            return lhsArea > rhsArea
        }

        let minimumArea = configuration.minimumFaceAreaFraction
        var faces: [StyleToneCore.FaceObservation] = []
        faces.reserveCapacity(min(observations.count, configuration.maximumFaceCount))
        var primaryCaptureQuality: Float?

        for observation in observations {
            guard faces.count < configuration.maximumFaceCount else { break }
            guard observation.confidence >= configuration.minimumFaceConfidence else { continue }
            let area = Double(observation.boundingBox.width * observation.boundingBox.height)
            guard area >= minimumArea else { continue }

            let boundingBox = VisionCoordinateMapper.topLeftRect(
                fromVisionNormalized: observation.boundingBox
            )
            guard boundingBox.width > 0, boundingBox.height > 0 else { continue }

            let landmarks = makeLandmarks(
                from: observation.landmarks,
                visionBoundingBox: observation.boundingBox
            )
            let face = StyleToneCore.FaceObservation(
                boundingBox: boundingBox,
                landmarks: landmarks,
                confidence: observation.confidence
            )
            if primaryCaptureQuality == nil {
                primaryCaptureQuality = observation.faceCaptureQuality
            }
            faces.append(face)
        }

        return FaceDetectionOutcome(
            faces: faces,
            primaryCaptureQuality: primaryCaptureQuality,
            failed: false
        )
    }

    private static func makeLandmarks(
        from landmarks: VNFaceLandmarks2D?,
        visionBoundingBox: CGRect
    ) -> [StyleToneCore.FaceLandmarkKind: [StyleToneCore.NormalizedPoint]] {
        guard let landmarks else { return [:] }
        var result: [StyleToneCore.FaceLandmarkKind: [StyleToneCore.NormalizedPoint]] = [:]
        result.reserveCapacity(StyleToneCore.FaceLandmarkKind.allCases.count)

        for kind in StyleToneCore.FaceLandmarkKind.allCases {
            guard let region = region(for: kind, in: landmarks) else { continue }
            let points = region.normalizedPoints
            guard !points.isEmpty else { continue }
            var converted: [StyleToneCore.NormalizedPoint] = []
            converted.reserveCapacity(points.count)
            for point in points {
                guard point.x.isFinite, point.y.isFinite else { continue }
                converted.append(
                    VisionCoordinateMapper.topLeftPoint(
                        landmark: point,
                        inVisionFaceBoundingBox: visionBoundingBox
                    )
                )
            }
            if !converted.isEmpty {
                result[kind] = converted
            }
        }
        return result
    }

    private static func region(
        for kind: StyleToneCore.FaceLandmarkKind,
        in landmarks: VNFaceLandmarks2D
    ) -> VNFaceLandmarkRegion2D? {
        switch kind {
        case .faceContour: return landmarks.faceContour
        case .leftEye: return landmarks.leftEye
        case .rightEye: return landmarks.rightEye
        case .leftEyebrow: return landmarks.leftEyebrow
        case .rightEyebrow: return landmarks.rightEyebrow
        case .nose: return landmarks.nose
        case .outerLips: return landmarks.outerLips
        case .innerLips: return landmarks.innerLips
        case .leftPupil: return landmarks.leftPupil
        case .rightPupil: return landmarks.rightPupil
        }
    }
}
