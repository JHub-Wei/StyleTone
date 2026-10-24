import Foundation

public enum FaceLandmarkKind: String, Sendable, Codable, CaseIterable {
    case faceContour
    case leftEye
    case rightEye
    case leftEyebrow
    case rightEyebrow
    case nose
    case outerLips
    case innerLips
    case leftPupil
    case rightPupil
}

public enum BodyJointKind: String, Sendable, Codable, CaseIterable {
    case neck
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

public struct FaceObservation: Sendable {
    public let boundingBox: NormalizedRect
    public let landmarks: [FaceLandmarkKind: [NormalizedPoint]]
    public let confidence: Float

    public init(
        boundingBox: NormalizedRect,
        landmarks: [FaceLandmarkKind: [NormalizedPoint]],
        confidence: Float
    ) {
        self.boundingBox = boundingBox
        self.landmarks = landmarks
        self.confidence = min(max(confidence, 0), 1)
    }

    public func points(for kind: FaceLandmarkKind) -> [NormalizedPoint] {
        landmarks[kind] ?? []
    }
}

public struct BodyObservation: Sendable {
    public let joints: [BodyJointKind: NormalizedPoint]
    public let confidence: Float

    public init(joints: [BodyJointKind: NormalizedPoint], confidence: Float) {
        self.joints = joints
        self.confidence = min(max(confidence, 0), 1)
    }

    public func point(for joint: BodyJointKind) -> NormalizedPoint? {
        joints[joint]
    }
}

public enum AnalysisWarning: String, Sendable, Codable, CaseIterable {
    case noFace
    case multipleFaces
    case noBody
    case occlusion
    case lowLight
    case lowConfidence
}

/// Output of the portrait analysis pipeline. Pixel dimensions refer to the
/// image that produced this analysis; masks use the same dimensions.
public struct PortraitAnalysis: Sendable {
    public let imageSize: PixelSize
    public let faces: [FaceObservation]
    public let body: BodyObservation?
    public let personMask: MaskBuffer?
    public let skinMask: MaskBuffer?
    public let backgroundEdgeMask: MaskBuffer?
    public let warnings: [AnalysisWarning]

    public init(
        imageSize: PixelSize,
        faces: [FaceObservation],
        body: BodyObservation?,
        personMask: MaskBuffer?,
        skinMask: MaskBuffer?,
        backgroundEdgeMask: MaskBuffer?,
        warnings: [AnalysisWarning]
    ) {
        self.imageSize = imageSize
        self.faces = faces
        self.body = body
        self.personMask = personMask
        self.skinMask = skinMask
        self.backgroundEdgeMask = backgroundEdgeMask
        self.warnings = warnings
    }

    public var hasFace: Bool { !faces.isEmpty }
    public var hasBody: Bool { body != nil }

    public var primaryFace: FaceObservation? {
        faces.max { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height
                < rhs.boundingBox.width * rhs.boundingBox.height
        }
    }

    public static func empty(imageSize: PixelSize) -> PortraitAnalysis {
        PortraitAnalysis(
            imageSize: imageSize,
            faces: [],
            body: nil,
            personMask: nil,
            skinMask: nil,
            backgroundEdgeMask: nil,
            warnings: [.noFace, .noBody]
        )
    }
}
