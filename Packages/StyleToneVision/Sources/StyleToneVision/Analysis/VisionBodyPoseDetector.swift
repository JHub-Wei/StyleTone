import CoreGraphics
import Foundation
import ImageIO
import StyleToneCore
import Vision

/// One human body pose pass over the analysis proxy.
struct BodyDetectionOutcome {
    let body: StyleToneCore.BodyObservation?
    let jointCount: Int
    let failed: Bool
}

/// Wraps `VNDetectHumanBodyPoseRequest` and maps Vision joints to
/// ``BodyJointKind``.
enum VisionBodyPoseDetector {
    static func detect(
        in cgImage: CGImage,
        configuration: VisionAnalysisConfiguration
    ) -> BodyDetectionOutcome {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation.up,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            return BodyDetectionOutcome(body: nil, jointCount: 0, failed: true)
        }

        let observations = request.results ?? []
        var best: StyleToneCore.BodyObservation?
        var bestScore: Float = -1
        var bestJointCount = 0

        for observation in observations {
            guard let detected = try? observation.recognizedPoints(.all) else { continue }
            var joints: [StyleToneCore.BodyJointKind: StyleToneCore.NormalizedPoint] = [:]
            var confidenceSum: Float = 0

            for (name, point) in detected {
                guard let kind = jointKind(for: name) else { continue }
                guard point.confidence >= configuration.minimumBodyConfidence else { continue }
                guard point.location.x.isFinite, point.location.y.isFinite else { continue }
                joints[kind] = VisionCoordinateMapper.topLeftPoint(
                    fromVisionNormalized: point.location
                )
                confidenceSum += point.confidence
            }

            guard joints.count >= configuration.minimumBodyJointCount else { continue }
            let averageConfidence = confidenceSum / Float(joints.count)
            let score = averageConfidence * Float(joints.count)
            if score > bestScore {
                bestScore = score
                bestJointCount = joints.count
                best = StyleToneCore.BodyObservation(
                    joints: joints,
                    confidence: averageConfidence
                )
            }
        }

        return BodyDetectionOutcome(body: best, jointCount: bestJointCount, failed: false)
    }

    private static func jointKind(
        for name: VNHumanBodyPoseObservation.JointName
    ) -> StyleToneCore.BodyJointKind? {
        switch name {
        case .neck: return .neck
        case .leftShoulder: return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftElbow: return .leftElbow
        case .rightElbow: return .rightElbow
        case .leftWrist: return .leftWrist
        case .rightWrist: return .rightWrist
        case .leftHip: return .leftHip
        case .rightHip: return .rightHip
        case .leftKnee: return .leftKnee
        case .rightKnee: return .rightKnee
        case .leftAnkle: return .leftAnkle
        case .rightAnkle: return .rightAnkle
        default: return nil
        }
    }
}
