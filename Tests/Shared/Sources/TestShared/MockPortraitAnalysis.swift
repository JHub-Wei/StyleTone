import Foundation
import GoldenSupport
import StyleToneCore

/// Deterministic `PortraitAnalysis` fixtures for tests that should not depend
/// on Vision.
///
/// Coordinates are normalized to `0...1` with a **top-left origin** (y grows
/// downwards). Vision emits bottom-left normalized coordinates; WP-05 converts
/// before producing a `PortraitAnalysis`, so mocks and production agree only
/// if that conversion is applied. This convention is documented here because
/// the Core contract does not fix an origin.
public enum MockPortraitAnalysisFactory {
    public static let defaultSize = PixelSize(width: 1080, height: 1440)
    public static let defaultFaceRect = NormalizedRect(
        x: 0.30,
        y: 0.16,
        width: 0.40,
        height: 0.30
    )

    /// An analysis with no faces, no body and all masks `nil`.
    public static func empty(size: PixelSize = defaultSize) -> PortraitAnalysis {
        PortraitAnalysis.empty(imageSize: size)
    }

    /// Builds a portrait analysis with `faceCount` faces, an optional body and
    /// optional full-size masks.
    public static func portrait(
        size: PixelSize = defaultSize,
        faceCount: Int = 1,
        includesBody: Bool = true,
        includesMasks: Bool = true,
        confidence: Float = 0.95,
        warnings: [AnalysisWarning] = []
    ) throws -> PortraitAnalysis {
        guard (0...3).contains(faceCount) else {
            throw GoldenSupportError.invalidConfiguration(
                reason: "mock portrait supports 0...3 faces"
            )
        }

        var faces: [FaceObservation] = []
        for index in 0..<faceCount {
            faces.append(
                faceObservation(
                    boundingBox: faceRect(index: index, count: faceCount),
                    confidence: confidence
                )
            )
        }

        let personMask: MaskBuffer?
        let skinMask: MaskBuffer?
        let backgroundEdgeMask: MaskBuffer?
        if includesMasks {
            personMask = try MockMaskFactory.ellipse(
                size: size,
                rect: NormalizedRect(x: 0.08, y: 0.05, width: 0.84, height: 0.92),
                feather: 0.08
            )
            skinMask = try MockMaskFactory.ellipse(
                size: size,
                rect: faceRect(index: 0, count: max(faceCount, 1)),
                feather: 0.05
            )
            backgroundEdgeMask = try MockMaskFactory.border(size: size, thickness: 6)
        } else {
            personMask = nil
            skinMask = nil
            backgroundEdgeMask = nil
        }

        var resolvedWarnings = warnings
        if faces.isEmpty, !resolvedWarnings.contains(.noFace) {
            resolvedWarnings.append(.noFace)
        }
        if faces.count > 1, !resolvedWarnings.contains(.multipleFaces) {
            resolvedWarnings.append(.multipleFaces)
        }
        if !includesBody, !resolvedWarnings.contains(.noBody) {
            resolvedWarnings.append(.noBody)
        }

        return PortraitAnalysis(
            imageSize: size,
            faces: faces,
            body: includesBody ? bodyObservation(confidence: confidence) : nil,
            personMask: personMask,
            skinMask: skinMask,
            backgroundEdgeMask: backgroundEdgeMask,
            warnings: resolvedWarnings
        )
    }

    /// Generates a face observation with all ten landmark kinds populated.
    public static func faceObservation(
        boundingBox: NormalizedRect = defaultFaceRect,
        confidence: Float = 0.95
    ) -> FaceObservation {
        let centerX = boundingBox.x + boundingBox.width / 2
        let centerY = boundingBox.y + boundingBox.height / 2
        let eyeY = boundingBox.y + boundingBox.height * 0.40
        let eyeOffsetX = boundingBox.width * 0.19
        let faceRadiusX = boundingBox.width / 2
        let faceRadiusY = boundingBox.height / 2

        var landmarks: [FaceLandmarkKind: [NormalizedPoint]] = [:]
        landmarks[.faceContour] = ellipsePoints(
            centerX: centerX,
            centerY: centerY,
            radiusX: faceRadiusX,
            radiusY: faceRadiusY,
            count: 16,
            startAngle: 0
        )
        landmarks[.leftEye] = ellipsePoints(
            centerX: centerX - eyeOffsetX,
            centerY: eyeY,
            radiusX: boundingBox.width * 0.09,
            radiusY: boundingBox.height * 0.045,
            count: 8,
            startAngle: 0
        )
        landmarks[.rightEye] = ellipsePoints(
            centerX: centerX + eyeOffsetX,
            centerY: eyeY,
            radiusX: boundingBox.width * 0.09,
            radiusY: boundingBox.height * 0.045,
            count: 8,
            startAngle: 0
        )
        landmarks[.leftEyebrow] = (0..<5).map { index in
            NormalizedPoint(
                x: centerX - eyeOffsetX + Double(index - 2) * boundingBox.width * 0.04,
                y: eyeY - boundingBox.height * 0.09
            ).clamped()
        }
        landmarks[.rightEyebrow] = (0..<5).map { index in
            NormalizedPoint(
                x: centerX + eyeOffsetX + Double(index - 2) * boundingBox.width * 0.04,
                y: eyeY - boundingBox.height * 0.09
            ).clamped()
        }
        landmarks[.nose] = [
            NormalizedPoint(x: centerX, y: centerY).clamped(),
            NormalizedPoint(x: centerX, y: centerY + boundingBox.height * 0.12).clamped()
        ]
        landmarks[.outerLips] = ellipsePoints(
            centerX: centerX,
            centerY: boundingBox.y + boundingBox.height * 0.74,
            radiusX: boundingBox.width * 0.18,
            radiusY: boundingBox.height * 0.07,
            count: 8,
            startAngle: 0
        )
        landmarks[.innerLips] = ellipsePoints(
            centerX: centerX,
            centerY: boundingBox.y + boundingBox.height * 0.74,
            radiusX: boundingBox.width * 0.12,
            radiusY: boundingBox.height * 0.035,
            count: 6,
            startAngle: 0
        )
        landmarks[.leftPupil] = [
            NormalizedPoint(x: centerX - eyeOffsetX, y: eyeY).clamped()
        ]
        landmarks[.rightPupil] = [
            NormalizedPoint(x: centerX + eyeOffsetX, y: eyeY).clamped()
        ]

        return FaceObservation(
            boundingBox: boundingBox.clamped(),
            landmarks: landmarks,
            confidence: confidence
        )
    }

    /// A plausible standing body with all thirteen joints.
    public static func bodyObservation(confidence: Float = 0.9) -> BodyObservation {
        BodyObservation(
            joints: [
                .neck: NormalizedPoint(x: 0.50, y: 0.22),
                .leftShoulder: NormalizedPoint(x: 0.38, y: 0.26),
                .rightShoulder: NormalizedPoint(x: 0.62, y: 0.26),
                .leftElbow: NormalizedPoint(x: 0.32, y: 0.42),
                .rightElbow: NormalizedPoint(x: 0.68, y: 0.42),
                .leftWrist: NormalizedPoint(x: 0.30, y: 0.58),
                .rightWrist: NormalizedPoint(x: 0.70, y: 0.58),
                .leftHip: NormalizedPoint(x: 0.42, y: 0.55),
                .rightHip: NormalizedPoint(x: 0.58, y: 0.55),
                .leftKnee: NormalizedPoint(x: 0.42, y: 0.75),
                .rightKnee: NormalizedPoint(x: 0.58, y: 0.75),
                .leftAnkle: NormalizedPoint(x: 0.42, y: 0.95),
                .rightAnkle: NormalizedPoint(x: 0.58, y: 0.95)
            ],
            confidence: confidence
        )
    }

    private static func faceRect(index: Int, count: Int) -> NormalizedRect {
        switch count {
        case 0:
            return defaultFaceRect
        case 1:
            return defaultFaceRect
        case 2:
            return NormalizedRect(
                x: index == 0 ? 0.10 : 0.54,
                y: 0.18,
                width: 0.34,
                height: 0.28
            )
        default:
            let x = 0.08 + Double(index) * 0.31
            return NormalizedRect(x: x, y: 0.18, width: 0.26, height: 0.24)
        }
    }

    private static func ellipsePoints(
        centerX: Double,
        centerY: Double,
        radiusX: Double,
        radiusY: Double,
        count: Int,
        startAngle: Double
    ) -> [NormalizedPoint] {
        (0..<count).map { index in
            let angle = startAngle + Double(index) / Double(count) * 2 * Double.pi
            return NormalizedPoint(
                x: centerX + cos(angle) * radiusX,
                y: centerY + sin(angle) * radiusY
            ).clamped()
        }
    }
}

/// Mask fixtures for analysis, retouch and geometry tests.
public enum MockMaskFactory {
    /// A mask where every byte is `value`.
    public static func solid(value: UInt8, size: PixelSize) throws -> MaskBuffer {
        try MaskBuffer(
            width: size.width,
            height: size.height,
            bytes: Data(repeating: value, count: size.width * size.height)
        )
    }

    /// A soft-edged ellipse mask in normalized, top-left coordinates.
    public static func ellipse(
        size: PixelSize,
        rect: NormalizedRect = NormalizedRect(x: 0.15, y: 0.1, width: 0.7, height: 0.8),
        feather: Double = 0.1
    ) throws -> MaskBuffer {
        guard size.width > 0, size.height > 0 else {
            throw GoldenSupportError.invalidDimensions(width: size.width, height: size.height)
        }
        let clamped = rect.clamped()
        let centerX = (clamped.x + clamped.width / 2) * Double(size.width)
        let centerY = (clamped.y + clamped.height / 2) * Double(size.height)
        let radiusX = max(clamped.width * Double(size.width) / 2, 1)
        let radiusY = max(clamped.height * Double(size.height) / 2, 1)
        let featherWidth = min(max(feather, 0), 1)

        var bytes = [UInt8](repeating: 0, count: size.width * size.height)
        for y in 0..<size.height {
            let normalizedY = (Double(y) + 0.5 - centerY) / radiusY
            for x in 0..<size.width {
                let normalizedX = (Double(x) + 0.5 - centerX) / radiusX
                let distance = (normalizedX * normalizedX + normalizedY * normalizedY).squareRoot()
                let value: Double
                if distance <= 1 - featherWidth {
                    value = 255
                } else if distance >= 1 {
                    value = 0
                } else {
                    value = (1 - distance) / featherWidth * 255
                }
                bytes[y * size.width + x] = UInt8(min(max(value.rounded(), 0), 255))
            }
        }
        return try MaskBuffer(width: size.width, height: size.height, bytes: Data(bytes))
    }

    /// A hard-edged rectangle mask in normalized, top-left coordinates.
    public static func rectangle(
        size: PixelSize,
        rect: NormalizedRect,
        value: UInt8 = 255
    ) throws -> MaskBuffer {
        let clamped = rect.clamped()
        let minX = Int((clamped.x * Double(size.width)).rounded(.down))
        let minY = Int((clamped.y * Double(size.height)).rounded(.down))
        let maxX = Int(((clamped.x + clamped.width) * Double(size.width)).rounded(.up))
        let maxY = Int(((clamped.y + clamped.height) * Double(size.height)).rounded(.up))
        var bytes = [UInt8](repeating: 0, count: size.width * size.height)
        let startX = max(0, minX)
        let startY = max(0, minY)
        let endX = min(size.width, maxX)
        let endY = min(size.height, maxY)
        guard startX < endX, startY < endY else {
            return try MaskBuffer(width: size.width, height: size.height, bytes: Data(bytes))
        }
        for y in startY..<endY {
            for x in startX..<endX {
                bytes[y * size.width + x] = value
            }
        }
        return try MaskBuffer(width: size.width, height: size.height, bytes: Data(bytes))
    }

    /// A mask with `thickness` opaque pixels along the image border.
    public static func border(size: PixelSize, thickness: Int = 4) throws -> MaskBuffer {
        let inset = max(1, thickness)
        var bytes = [UInt8](repeating: 0, count: size.width * size.height)
        for y in 0..<size.height {
            for x in 0..<size.width {
                let onBorder = x < inset || y < inset
                    || x >= size.width - inset
                    || y >= size.height - inset
                bytes[y * size.width + x] = onBorder ? 255 : 0
            }
        }
        return try MaskBuffer(width: size.width, height: size.height, bytes: Data(bytes))
    }
}
