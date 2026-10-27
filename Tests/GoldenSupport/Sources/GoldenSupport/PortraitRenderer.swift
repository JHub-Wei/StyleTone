import Foundation
import StyleToneCore

/// Deterministic synthetic portrait renderer for the WP-25 golden corpus.
///
/// The renderer draws a cartoon studio portrait (background, one to three
/// people, clothing, facial features, occlusion) and returns both the pixels and
/// the ground truth the quality metrics need:
///
/// - person / skin / background-structure masks,
/// - face landmarks and body joints for the real geometry passes,
/// - straight background lines (door frames, tile seams, window rails) that the
///   background metric checks after warping.
///
/// It never decodes a photograph or touches the filesystem. Every output byte is
/// a pure function of the `PortraitSampleSpec`.
public enum PortraitRenderer {
    /// Renders one corpus sample.
    ///
    /// - Throws: ``GoldenSupportError`` when the sample description is invalid.
    public static func render(_ spec: PortraitSampleSpec) throws -> PortraitScene {
        try spec.validate()
        let palette = PortraitPalette(spec: spec)
        var canvas = PortraitCanvas(
            width: spec.width,
            height: spec.height,
            background: palette.wallTop
        )
        let backgroundLines = drawBackground(&canvas, spec: spec, palette: palette)

        var layouts: [SubjectLayout] = []
        var geometries: [PortraitSubjectGeometry] = []
        var blemishes: [Blemish] = []
        var highlights: [SIMD2<Double>] = []

        let drawOrder = orderedSubjects(spec)
        for subject in drawOrder {
            let layout = makeLayout(subject: subject, sample: spec)
            layouts.append(layout)
            let geometry = drawSubject(
                layout: layout,
                sample: spec,
                palette: palette,
                canvas: &canvas,
                blemishes: &blemishes,
                highlights: &highlights
            )
            geometries.append(geometry)
        }

        applyLighting(&canvas, spec: spec)
        applyTexture(
            &canvas,
            spec: spec,
            blemishes: blemishes,
            highlights: highlights
        )

        let personMask = try canvas.personMask()
        let skinMask = try canvas.skinMask()
        let rawStructure = try canvas.structureMask()
        let protectedZone = try MaskOperations.dilated(personMask, radius: 2)
        var structure = MaskOperations.bytes(rawStructure)
        let protectedBytes = MaskOperations.bytes(protectedZone)
        for index in 0 ..< structure.count where protectedBytes[index] > 0 {
            structure[index] = 0
        }
        let edgeMask = try MaskOperations.make(
            width: spec.width,
            height: spec.height,
            values: structure
        )

        let primaryLayout = layouts.first { $0.subject.role == .primary } ?? layouts.last
        let faces: [FaceObservation] = geometries.map { geometry in
            FaceObservation(
                boundingBox: geometry.faceBox,
                landmarks: geometry.faceLandmarks,
                confidence: geometry.role == .primary ? 0.94 : 0.86
            )
        }
        var body: BodyObservation?
        if spec.framing != .headshot, let primaryLayout {
            body = BodyObservation(
                joints: primaryLayout.normalizedJoints(size: spec.pixelSize),
                confidence: 0.9
            )
        }
        var warnings: [AnalysisWarning] = []
        if faces.count > 1 { warnings.append(.multipleFaces) }
        if spec.hasOcclusion { warnings.append(.occlusion) }
        if spec.lighting == .lowKey { warnings.append(.lowLight) }
        if body == nil { warnings.append(.noBody) }

        let analysis = PortraitAnalysis(
            imageSize: spec.pixelSize,
            faces: faces,
            body: body,
            personMask: personMask,
            skinMask: skinMask,
            backgroundEdgeMask: edgeMask,
            warnings: warnings
        )
        let primaryFaceBox = geometries.first { $0.role == .primary }?.faceBox
        let groundTruth = PortraitGroundTruth(
            imageSize: spec.pixelSize,
            personMask: personMask,
            skinMask: skinMask,
            backgroundEdgeMask: edgeMask,
            lines: backgroundLines,
            subjects: geometries,
            primaryFaceBox: primaryFaceBox
        )
        let pixels = try canvas.pixelBuffer()
        return PortraitScene(
            spec: spec,
            pixels: pixels,
            analysis: analysis,
            groundTruth: groundTruth
        )
    }

    /// Base sRGB colours used for the six Fitzpatrick bands.
    public static func baseSkinColor(for tone: SkinToneBand) -> RGB8 {
        switch tone {
        case .i: return RGB8(red: 255, green: 224, blue: 208)
        case .ii: return RGB8(red: 241, green: 194, blue: 165)
        case .iii: return RGB8(red: 224, green: 172, blue: 130)
        case .iv: return RGB8(red: 198, green: 134, blue: 89)
        case .v: return RGB8(red: 141, green: 85, blue: 54)
        case .vi: return RGB8(red: 75, green: 46, blue: 33)
        }
    }
}

// MARK: - Private drawing model

private struct Blemish {
    let centerX: Double
    let centerY: Double
    let radius: Double
    let depth: Double
}

private struct BodyProportions {
    let shoulder: Double
    let waist: Double
    let hip: Double
    let vertical: Double
    let headScale: Double

    static func make(_ type: PortraitBodyType) -> BodyProportions {
        switch type {
        case .slim:
            return BodyProportions(shoulder: 0.92, waist: 0.68, hip: 0.82, vertical: 1, headScale: 1)
        case .average:
            return BodyProportions(shoulder: 1, waist: 0.78, hip: 0.9, vertical: 1, headScale: 1)
        case .curvy:
            return BodyProportions(shoulder: 0.98, waist: 0.72, hip: 1.02, vertical: 1, headScale: 1)
        case .plus:
            return BodyProportions(shoulder: 1.08, waist: 0.98, hip: 1.12, vertical: 0.98, headScale: 1)
        case .tall:
            return BodyProportions(shoulder: 0.94, waist: 0.72, hip: 0.86, vertical: 1.06, headScale: 0.94)
        case .petite:
            return BodyProportions(shoulder: 0.96, waist: 0.82, hip: 0.92, vertical: 0.94, headScale: 1.04)
        }
    }
}

private struct SubjectLayout {
    let subject: PortraitSubjectSpec
    let centerX: Double
    let headCenterY: Double
    let headHeight: Double
    let headWidth: Double
    let headRadiusX: Double
    let headRadiusY: Double
    let shoulderY: Double
    let waistY: Double
    let hipY: Double
    let kneeY: Double
    let ankleY: Double
    let shoulderHalf: Double
    let waistHalf: Double
    let hipHalf: Double
    let armRadius: Double
    let legRadius: Double
    let eyeY: Double
    let eyeDX: Double
    let noseBaseY: Double
    let lipY: Double
    let leftShoulder: SIMD2<Double>
    let rightShoulder: SIMD2<Double>
    let leftElbow: SIMD2<Double>
    let rightElbow: SIMD2<Double>
    let leftWrist: SIMD2<Double>
    let rightWrist: SIMD2<Double>
    var leftHip: SIMD2<Double>
    var rightHip: SIMD2<Double>
    var leftKnee: SIMD2<Double>
    var rightKnee: SIMD2<Double>
    var leftAnkle: SIMD2<Double>
    var rightAnkle: SIMD2<Double>
    let faceBox: NormalizedRect
    let personBox: NormalizedRect
    let size: PixelSize

    var faceCenter: SIMD2<Double> {
        SIMD2<Double>(centerX, headCenterY)
    }

    var chinY: Double {
        headCenterY + headRadiusY
    }

    var eyeCenters: (left: SIMD2<Double>, right: SIMD2<Double>) {
        (
            SIMD2<Double>(centerX - eyeDX, eyeY),
            SIMD2<Double>(centerX + eyeDX, eyeY)
        )
    }

    func normalized(_ point: SIMD2<Double>) -> NormalizedPoint {
        NormalizedPoint(
            x: min(max(point.x / Double(size.width), 0), 1),
            y: min(max(point.y / Double(size.height), 0), 1)
        )
    }

    func normalizedJoints(size: PixelSize) -> [BodyJointKind: NormalizedPoint] {
        var joints: [BodyJointKind: NormalizedPoint] = [:]
        let points: [BodyJointKind: SIMD2<Double>] = [
            .neck: SIMD2<Double>(centerX, shoulderY - headHeight * 0.08),
            .leftShoulder: leftShoulder,
            .rightShoulder: rightShoulder,
            .leftElbow: leftElbow,
            .rightElbow: rightElbow,
            .leftWrist: leftWrist,
            .rightWrist: rightWrist,
            .leftHip: leftHip,
            .rightHip: rightHip,
            .leftKnee: leftKnee,
            .rightKnee: rightKnee,
            .leftAnkle: leftAnkle,
            .rightAnkle: rightAnkle
        ]
        for (kind, point) in points {
            joints[kind] = NormalizedPoint(
                x: min(max(point.x / Double(size.width), 0), 1),
                y: min(max(point.y / Double(size.height), 0), 1)
            )
        }
        return joints
    }

    func faceObservations() -> [FaceLandmarkKind: [NormalizedPoint]] {
        var landmarks: [FaceLandmarkKind: [NormalizedPoint]] = [:]
        let leftEye = SIMD2<Double>(centerX - eyeDX, eyeY)
        let rightEye = SIMD2<Double>(centerX + eyeDX, eyeY)
        landmarks[.leftEye] = circlePoints(center: leftEye, radius: headRadiusX * 0.10)
        landmarks[.rightEye] = circlePoints(center: rightEye, radius: headRadiusX * 0.10)
        landmarks[.leftPupil] = circlePoints(center: leftEye, radius: headRadiusX * 0.035)
        landmarks[.rightPupil] = circlePoints(center: rightEye, radius: headRadiusX * 0.035)
        landmarks[.leftEyebrow] = linePoints(
            from: SIMD2<Double>(leftEye.x - headRadiusX * 0.16, eyeY - headHeight * 0.10),
            to: SIMD2<Double>(leftEye.x + headRadiusX * 0.16, eyeY - headHeight * 0.11),
            count: 4
        )
        landmarks[.rightEyebrow] = linePoints(
            from: SIMD2<Double>(rightEye.x - headRadiusX * 0.16, eyeY - headHeight * 0.11),
            to: SIMD2<Double>(rightEye.x + headRadiusX * 0.16, eyeY - headHeight * 0.10),
            count: 4
        )
        landmarks[.nose] = [
            SIMD2<Double>(centerX, headCenterY + headHeight * 0.02),
            SIMD2<Double>(centerX - headRadiusX * 0.10, noseBaseY),
            SIMD2<Double>(centerX + headRadiusX * 0.10, noseBaseY)
        ].map(normalized)
        landmarks[.outerLips] = ellipsePoints(
            center: SIMD2<Double>(centerX, lipY),
            radiusX: headRadiusX * 0.22,
            radiusY: headHeight * 0.07,
            count: 8,
            startAngle: 0,
            endAngle: 360
        ).map(normalized)
        landmarks[.innerLips] = ellipsePoints(
            center: SIMD2<Double>(centerX, lipY),
            radiusX: headRadiusX * 0.13,
            radiusY: headHeight * 0.035,
            count: 6,
            startAngle: 0,
            endAngle: 360
        ).map(normalized)
        landmarks[.faceContour] = ellipsePoints(
            center: SIMD2<Double>(centerX, headCenterY),
            radiusX: headRadiusX * 0.96,
            radiusY: headRadiusY * 0.97,
            count: 16,
            startAngle: -30,
            endAngle: 210
        ).map(normalized)
        return landmarks
    }

    private func circlePoints(center: SIMD2<Double>, radius: Double) -> [NormalizedPoint] {
        ellipsePoints(
            center: center,
            radiusX: radius,
            radiusY: radius,
            count: 4,
            startAngle: 0,
            endAngle: 360
        ).map(normalized)
    }

    private func linePoints(
        from start: SIMD2<Double>,
        to end: SIMD2<Double>,
        count: Int
    ) -> [NormalizedPoint] {
        guard count > 1 else { return [normalized(start)] }
        var points: [NormalizedPoint] = []
        for index in 0 ..< count {
            let t = Double(index) / Double(count - 1)
            let point = SIMD2<Double>(
                start.x + (end.x - start.x) * t,
                start.y + (end.y - start.y) * t
            )
            points.append(normalized(point))
        }
        return points
    }

    private func ellipsePoints(
        center: SIMD2<Double>,
        radiusX: Double,
        radiusY: Double,
        count: Int,
        startAngle: Double,
        endAngle: Double
    ) -> [SIMD2<Double>] {
        guard count > 1 else { return [center] }
        var points: [SIMD2<Double>] = []
        for index in 0 ..< count {
            let t = Double(index) / Double(count - 1)
            let angle = (startAngle + (endAngle - startAngle) * t) * Double.pi / 180
            points.append(
                SIMD2<Double>(
                    center.x + cos(angle) * radiusX,
                    center.y + sin(angle) * radiusY
                )
            )
        }
        return points
    }
}

// MARK: - Layout

private func makeLayout(subject: PortraitSubjectSpec, sample: PortraitSampleSpec) -> SubjectLayout {
    let width = Double(sample.width)
    let height = Double(sample.height)
    let proportions = BodyProportions.make(subject.bodyType)
    let baseHeadFraction: Double
    switch sample.framing {
    case .headshot: baseHeadFraction = 0.36
    case .halfBody: baseHeadFraction = 0.235
    case .fullBody: baseHeadFraction = 0.165
    }
    let headHeight = height * baseHeadFraction * subject.scale * proportions.headScale
    let headWidth = headHeight * 0.78
    let headRadiusX = headWidth * 0.5
    let headRadiusY = headHeight * 0.60
    let vertical = proportions.vertical

    let headCenterY: Double
    if sample.framing == .fullBody {
        headCenterY = max(
            height * 0.06,
            height * 0.92 - 4.75 * headHeight * vertical
        )
    } else {
        let base: Double = sample.framing == .headshot ? 0.30 : 0.19
        headCenterY = height * (base + (1 - subject.scale) * 0.02)
    }
    let centerX = width * (0.5 + subject.xOffset)

    let shoulderY = headCenterY + headHeight * 0.85
    let waistY = headCenterY + headHeight * 1.75 * vertical
    let hipY = headCenterY + headHeight * 2.10 * vertical
    let kneeY = headCenterY + headHeight * 3.45 * vertical
    let ankleY = headCenterY + headHeight * 4.75 * vertical

    let shoulderHalf = headHeight * 0.95 * proportions.shoulder
    let waistHalf = headHeight * 0.62 * proportions.waist
    let hipHalf = headHeight * 0.78 * proportions.hip
    let armRadius = headHeight * 0.15
    let legRadius = headHeight * 0.17

    let eyeY = headCenterY - headHeight * 0.06
    let eyeDX = headRadiusX * 0.33
    let noseBaseY = headCenterY + headHeight * 0.22
    let lipY = headCenterY + headHeight * 0.38

    var leftElbow = SIMD2<Double>(
        centerX - shoulderHalf - headHeight * 0.16,
        shoulderY + headHeight * 0.82
    )
    var rightElbow = SIMD2<Double>(
        centerX + shoulderHalf + headHeight * 0.16,
        shoulderY + headHeight * 0.82
    )
    var leftWrist = SIMD2<Double>(
        centerX - shoulderHalf - headHeight * 0.04,
        hipY + headHeight * 0.10
    )
    var rightWrist = SIMD2<Double>(
        centerX + shoulderHalf + headHeight * 0.04,
        hipY + headHeight * 0.10
    )

    switch subject.occlusion {
    case .handAtChin:
        rightElbow = SIMD2<Double>(
            centerX + shoulderHalf * 0.92,
            shoulderY + headHeight * 0.55
        )
        rightWrist = SIMD2<Double>(
            centerX + headRadiusX * 0.55,
            headCenterY + headHeight * 0.55
        )
    case .armAcrossTorso:
        rightElbow = SIMD2<Double>(
            centerX + waistHalf * 0.25,
            shoulderY + headHeight * 0.95
        )
        rightWrist = SIMD2<Double>(
            centerX - hipHalf * 0.65,
            waistY + headHeight * 0.05
        )
    case .objectInFront:
        rightElbow = SIMD2<Double>(
            centerX + shoulderHalf * 0.95,
            shoulderY + headHeight * 0.85
        )
        rightWrist = SIMD2<Double>(
            centerX + waistHalf * 0.55,
            waistY - headHeight * 0.05
        )
    default:
        break
    }

    let leftShoulder = SIMD2<Double>(centerX - shoulderHalf, shoulderY)
    let rightShoulder = SIMD2<Double>(centerX + shoulderHalf, shoulderY)

    let leftHip = SIMD2<Double>(centerX - hipHalf * 0.42, hipY)
    let rightHip = SIMD2<Double>(centerX + hipHalf * 0.42, hipY)
    let leftKnee = SIMD2<Double>(centerX - hipHalf * 0.40, kneeY)
    let rightKnee = SIMD2<Double>(centerX + hipHalf * 0.40, kneeY)
    let leftAnkle = SIMD2<Double>(centerX - hipHalf * 0.38, ankleY)
    let rightAnkle = SIMD2<Double>(centerX + hipHalf * 0.38, ankleY)

    let faceBox = NormalizedRect(
        x: (centerX - headRadiusX) / width,
        y: (headCenterY - headRadiusY) / height,
        width: (headRadiusX * 2) / width,
        height: (headRadiusY * 2) / height
    ).clamped()

    let minX = min(
        min(leftShoulder.x, rightShoulder.x) - armRadius,
        min(leftHip.x, rightHip.x) - legRadius
    )
    let maxX = max(
        max(leftShoulder.x, rightShoulder.x) + armRadius,
        max(leftHip.x, rightHip.x) + legRadius
    )
    let minY = headCenterY - headRadiusY * 1.35
    let maxY = min(height, max(ankleY, hipY) + headHeight * 0.25)
    let personBox = NormalizedRect(
        x: minX / width,
        y: minY / height,
        width: (maxX - minX) / width,
        height: (maxY - minY) / height
    ).clamped()

    return SubjectLayout(
        subject: subject,
        centerX: centerX,
        headCenterY: headCenterY,
        headHeight: headHeight,
        headWidth: headWidth,
        headRadiusX: headRadiusX,
        headRadiusY: headRadiusY,
        shoulderY: shoulderY,
        waistY: waistY,
        hipY: hipY,
        kneeY: kneeY,
        ankleY: ankleY,
        shoulderHalf: shoulderHalf,
        waistHalf: waistHalf,
        hipHalf: hipHalf,
        armRadius: armRadius,
        legRadius: legRadius,
        eyeY: eyeY,
        eyeDX: eyeDX,
        noseBaseY: noseBaseY,
        lipY: lipY,
        leftShoulder: leftShoulder,
        rightShoulder: rightShoulder,
        leftElbow: leftElbow,
        rightElbow: rightElbow,
        leftWrist: leftWrist,
        rightWrist: rightWrist,
        leftHip: leftHip,
        rightHip: rightHip,
        leftKnee: leftKnee,
        rightKnee: rightKnee,
        leftAnkle: leftAnkle,
        rightAnkle: rightAnkle,
        faceBox: faceBox,
        personBox: personBox,
        size: sample.pixelSize
    )
}

private func orderedSubjects(_ sample: PortraitSampleSpec) -> [PortraitSubjectSpec] {
    func priority(_ role: PortraitSubjectRole) -> Int {
        switch role {
        case .extra: return 0
        case .partner: return 1
        case .primary: return 2
        }
    }
    return sample.subjects.enumerated()
        .sorted { lhs, rhs in
            let leftPriority = priority(lhs.element.role)
            let rightPriority = priority(rhs.element.role)
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
}

// MARK: - Subject drawing

private func drawSubject(
    layout: SubjectLayout,
    sample: PortraitSampleSpec,
    palette: PortraitPalette,
    canvas: inout PortraitCanvas,
    blemishes: inout [Blemish],
    highlights: inout [SIMD2<Double>]
) -> PortraitSubjectGeometry {
    let subject = layout.subject
    let skin = PortraitRenderer.baseSkinColor(for: subject.skinTone)
    let hair = palette.hairColor(seed: subject.seed)
    let outfit = palette.outfitColor(seed: subject.seed)
    let outfitDark = outfit.blended(with: .black, amount: 0.22)
    let hairStyle = Int(subject.seed % 4)

    drawHairBack(
        layout: layout,
        style: hairStyle,
        color: hair,
        canvas: &canvas
    )
    drawLegs(
        layout: layout,
        skin: skin,
        outfit: outfit,
        outfitDark: outfitDark,
        seed: subject.seed,
        canvas: &canvas
    )
    drawTorso(
        layout: layout,
        skin: skin,
        outfit: outfit,
        outfitDark: outfitDark,
        seed: subject.seed,
        canvas: &canvas
    )
    drawArms(
        layout: layout,
        subject: subject,
        skin: skin,
        outfit: outfit,
        canvas: &canvas
    )
    drawNeck(layout: layout, skin: skin, canvas: &canvas)
    drawHead(layout: layout, skin: skin, hair: hair, canvas: &canvas)
    drawHairFront(
        layout: layout,
        style: hairStyle,
        color: hair,
        canvas: &canvas
    )
    drawFace(layout: layout, skin: skin, hair: hair, palette: palette, canvas: &canvas)
    drawOcclusion(
        layout: layout,
        subject: subject,
        skin: skin,
        outfit: outfit,
        hair: hair,
        canvas: &canvas
    )

    addBlemishes(layout: layout, subject: subject, into: &blemishes)
    highlights.append(SIMD2<Double>(layout.centerX, layout.headCenterY - layout.headHeight * 0.28))
    highlights.append(SIMD2<Double>(layout.centerX + layout.headRadiusX * 0.25, layout.noseBaseY))

    let landmarks = layout.faceObservations()
    let joints = layout.normalizedJoints(size: layout.size)
    return PortraitSubjectGeometry(
        role: subject.role,
        skinTone: subject.skinTone,
        bodyType: subject.bodyType,
        occlusion: subject.occlusion,
        faceBox: layout.faceBox,
        faceCenter: layout.normalized(layout.faceCenter),
        personBox: layout.personBox,
        faceLandmarks: landmarks,
        bodyJoints: joints,
        isFrontmost: subject.role == .primary
    )
}

private func drawHairBack(
    layout: SubjectLayout,
    style: Int,
    color: RGB8,
    canvas: inout PortraitCanvas
) {
    let cx = layout.centerX
    let cy = layout.headCenterY
    let rx = layout.headRadiusX
    let ry = layout.headRadiusY
    switch style {
    case 0:
        break
    case 1:
        canvas.fillEllipse(
            centerX: cx,
            centerY: cy + ry * 0.20,
            radiusX: rx * 1.10,
            radiusY: ry * 1.05,
            color: color.blended(with: .black, amount: 0.08),
            marksPerson: true
        )
    case 2:
        canvas.fillEllipse(
            centerX: cx,
            centerY: cy + ry * 0.55,
            radiusX: rx * 1.22,
            radiusY: ry * 1.60,
            color: color.blended(with: .black, amount: 0.05),
            marksPerson: true
        )
    default:
        canvas.fillEllipse(
            centerX: cx + rx * 0.95,
            centerY: cy + ry * 0.55,
            radiusX: rx * 0.45,
            radiusY: ry * 1.10,
            color: color.blended(with: .black, amount: 0.10),
            marksPerson: true
        )
    }
}

private func drawLegs(
    layout: SubjectLayout,
    skin: RGB8,
    outfit: RGB8,
    outfitDark: RGB8,
    seed: UInt64,
    canvas: inout PortraitCanvas
) {
    let mode = Int(seed % 3)
    let hipRadius = layout.legRadius * 1.05
    let kneeRadius = layout.legRadius * 0.82
    let ankleRadius = layout.legRadius * 0.62

    func drawLegChain(
        hip: SIMD2<Double>,
        knee: SIMD2<Double>,
        ankle: SIMD2<Double>,
        color: RGB8,
        marksSkin: Bool
    ) {
        canvas.fillCapsule(
            fromX: hip.x, fromY: hip.y, toX: knee.x, toY: knee.y,
            radius: hipRadius,
            color: color,
            marksPerson: true,
            marksSkin: marksSkin
        )
        canvas.fillCapsule(
            fromX: knee.x, fromY: knee.y, toX: ankle.x, toY: ankle.y,
            radius: ankleRadius,
            color: color,
            marksPerson: true,
            marksSkin: marksSkin
        )
    }

    switch mode {
    case 0:
        drawLegChain(
            hip: layout.leftHip, knee: layout.leftKnee, ankle: layout.leftAnkle,
            color: outfitDark, marksSkin: false
        )
        drawLegChain(
            hip: layout.rightHip, knee: layout.rightKnee, ankle: layout.rightAnkle,
            color: outfitDark, marksSkin: false
        )
    case 1:
        drawLegChain(
            hip: layout.leftHip, knee: layout.leftKnee, ankle: layout.leftAnkle,
            color: skin, marksSkin: true
        )
        drawLegChain(
            hip: layout.rightHip, knee: layout.rightKnee, ankle: layout.rightAnkle,
            color: skin, marksSkin: true
        )
        canvas.fillRect(
            x: Int(layout.centerX - layout.hipHalf * 1.02),
            y: Int(layout.hipY - layout.headHeight * 0.10),
            width: Int(layout.hipHalf * 2.04),
            height: Int((layout.kneeY - layout.hipY) * 0.48),
            color: outfit,
            marksPerson: true,
            marksSkin: false
        )
    default:
        drawLegChain(
            hip: layout.leftHip, knee: layout.leftKnee, ankle: layout.leftAnkle,
            color: skin, marksSkin: true
        )
        drawLegChain(
            hip: layout.rightHip, knee: layout.rightKnee, ankle: layout.rightAnkle,
            color: skin, marksSkin: true
        )
        let skirtBottom = layout.hipY + (layout.kneeY - layout.hipY) * 0.45
        let points: [SIMD2<Double>] = [
            SIMD2<Double>(layout.centerX - layout.waistHalf, layout.waistY),
            SIMD2<Double>(layout.centerX + layout.waistHalf, layout.waistY),
            SIMD2<Double>(layout.centerX + layout.hipHalf * 1.15, skirtBottom),
            SIMD2<Double>(layout.centerX - layout.hipHalf * 1.15, skirtBottom)
        ]
        canvas.fillPolygon(points: points, color: outfit, marksPerson: true)
    }

    for ankle in [layout.leftAnkle, layout.rightAnkle] {
        canvas.fillEllipse(
            centerX: ankle.x,
            centerY: ankle.y + layout.legRadius * 0.10,
            radiusX: layout.legRadius * 0.85,
            radiusY: layout.legRadius * 0.38,
            color: outfitDark.blended(with: .black, amount: 0.25),
            marksPerson: true
        )
    }
}

private func drawTorso(
    layout: SubjectLayout,
    skin: RGB8,
    outfit: RGB8,
    outfitDark: RGB8,
    seed: UInt64,
    canvas: inout PortraitCanvas
) {
    let points: [SIMD2<Double>] = [
        SIMD2<Double>(layout.centerX - layout.shoulderHalf, layout.shoulderY),
        SIMD2<Double>(layout.centerX + layout.shoulderHalf, layout.shoulderY),
        SIMD2<Double>(layout.centerX + layout.waistHalf, layout.waistY),
        SIMD2<Double>(layout.centerX + layout.hipHalf, layout.hipY),
        SIMD2<Double>(layout.centerX - layout.hipHalf, layout.hipY),
        SIMD2<Double>(layout.centerX - layout.waistHalf, layout.waistY)
    ]
    canvas.fillPolygon(points: points, color: outfit, marksPerson: true)

    // Neckline: a small skin triangle turns the torso shape into clothing.
    let collarY = layout.shoulderY + layout.headHeight * 0.12
    let collarPoints: [SIMD2<Double>] = [
        SIMD2<Double>(layout.centerX - layout.headRadiusX * 0.42, layout.shoulderY),
        SIMD2<Double>(layout.centerX + layout.headRadiusX * 0.42, layout.shoulderY),
        SIMD2<Double>(layout.centerX, collarY + layout.headHeight * 0.10)
    ]
    canvas.fillPolygon(points: collarPoints, color: skin, marksPerson: true, marksSkin: true)

    // Collar trim and belt stay clothing.
    canvas.fillCapsule(
        fromX: layout.centerX - layout.headRadiusX * 0.46,
        fromY: layout.shoulderY + layout.headHeight * 0.02,
        toX: layout.centerX + layout.headRadiusX * 0.46,
        toY: layout.shoulderY + layout.headHeight * 0.02,
        radius: layout.headHeight * 0.035,
        color: outfitDark,
        marksPerson: true
    )
    canvas.fillRect(
        x: Int(layout.centerX - layout.waistHalf * 1.02),
        y: Int(layout.waistY + layout.headHeight * 0.10),
        width: Int(layout.waistHalf * 2.04),
        height: Int(layout.headHeight * 0.10),
        color: outfitDark,
        marksPerson: true
    )

    // A few garment seams add high-frequency content without creating
    // background-looking structure inside the subject.
    if seed % 3 == 0 {
        var y = layout.shoulderY + layout.headHeight * 0.35
        while y < layout.hipY - layout.headHeight * 0.15 {
            canvas.fillCapsule(
                fromX: layout.centerX - layout.waistHalf * 0.85,
                fromY: y,
                toX: layout.centerX + layout.waistHalf * 0.85,
                toY: y,
                radius: max(0.6, layout.headHeight * 0.018),
                color: outfitDark.blended(with: outfit, amount: 0.5),
                marksPerson: true
            )
            y += layout.headHeight * 0.16
        }
    }
}

private func drawArms(
    layout: SubjectLayout,
    subject: PortraitSubjectSpec,
    skin: RGB8,
    outfit: RGB8,
    canvas: inout PortraitCanvas
) {
    let sleeveMode: Int
    switch subject.occlusion {
    case .looseSleeves:
        sleeveMode = 1
    default:
        sleeveMode = Int(subject.seed % 3)
    }
    let hands: [SIMD2<Double>] = [layout.leftWrist, layout.rightWrist]

    func drawArm(
        shoulder: SIMD2<Double>,
        elbow: SIMD2<Double>,
        wrist: SIMD2<Double>,
        drawsOverTorso: Bool
    ) {
        _ = drawsOverTorso
        if sleeveMode == 1 {
            canvas.fillCapsule(
                fromX: shoulder.x, fromY: shoulder.y, toX: elbow.x, toY: elbow.y,
                radius: layout.armRadius * 1.10,
                color: outfit,
                marksPerson: true
            )
            canvas.fillCapsule(
                fromX: elbow.x, fromY: elbow.y, toX: wrist.x, toY: wrist.y,
                radius: layout.armRadius * 0.98,
                color: outfit,
                marksPerson: true
            )
        } else {
            canvas.fillCapsule(
                fromX: shoulder.x, fromY: shoulder.y, toX: elbow.x, toY: elbow.y,
                radius: layout.armRadius,
                color: skin,
                marksPerson: true,
                marksSkin: true
            )
            canvas.fillCapsule(
                fromX: elbow.x, fromY: elbow.y, toX: wrist.x, toY: wrist.y,
                radius: layout.armRadius * 0.85,
                color: skin,
                marksPerson: true,
                marksSkin: true
            )
            if sleeveMode == 0 {
                let sleeveEnd = SIMD2<Double>(
                    shoulder.x + (elbow.x - shoulder.x) * 0.38,
                    shoulder.y + (elbow.y - shoulder.y) * 0.38
                )
                canvas.fillCapsule(
                    fromX: shoulder.x, fromY: shoulder.y, toX: sleeveEnd.x, toY: sleeveEnd.y,
                    radius: layout.armRadius * 1.12,
                    color: outfit,
                    marksPerson: true
                )
            }
        }
    }

    drawArm(
        shoulder: layout.leftShoulder,
        elbow: layout.leftElbow,
        wrist: layout.leftWrist,
        drawsOverTorso: false
    )
    drawArm(
        shoulder: layout.rightShoulder,
        elbow: layout.rightElbow,
        wrist: layout.rightWrist,
        drawsOverTorso: subject.occlusion == .armAcrossTorso
    )

    for hand in hands {
        canvas.fillEllipse(
            centerX: hand.x,
            centerY: hand.y,
            radiusX: layout.armRadius * 0.85,
            radiusY: layout.armRadius * 0.95,
            color: skin,
            marksPerson: true,
            marksSkin: true
        )
    }
}

private func drawNeck(layout: SubjectLayout, skin: RGB8, canvas: inout PortraitCanvas) {
    canvas.fillCapsule(
        fromX: layout.centerX,
        fromY: layout.chinY - layout.headHeight * 0.10,
        toX: layout.centerX,
        toY: layout.shoulderY + layout.headHeight * 0.05,
        radius: layout.headRadiusX * 0.34,
        color: skin,
        marksPerson: true,
        marksSkin: true
    )
    canvas.fillEllipse(
        centerX: layout.centerX,
        centerY: layout.shoulderY - layout.headHeight * 0.02,
        radiusX: layout.headRadiusX * 0.55,
        radiusY: layout.headHeight * 0.10,
        color: skin.blended(with: .black, amount: 0.12),
        marksPerson: true,
        marksSkin: true
    )
}

private func drawHead(
    layout: SubjectLayout,
    skin: RGB8,
    hair: RGB8,
    canvas: inout PortraitCanvas
) {
    // Ears first so the head ellipse overlaps their inner edge.
    for direction in [-1.0, 1.0] {
        canvas.fillEllipse(
            centerX: layout.centerX + direction * layout.headRadiusX * 0.98,
            centerY: layout.headCenterY + layout.headRadiusY * 0.08,
            radiusX: layout.headRadiusX * 0.16,
            radiusY: layout.headRadiusY * 0.22,
            color: skin.blended(with: .black, amount: 0.06),
            marksPerson: true,
            marksSkin: true
        )
    }
    canvas.fillEllipse(
        centerX: layout.centerX,
        centerY: layout.headCenterY,
        radiusX: layout.headRadiusX,
        radiusY: layout.headRadiusY,
        color: skin,
        marksPerson: true,
        marksSkin: true
    )
    // Jaw and cheek shading remain skin.
    canvas.fillEllipse(
        centerX: layout.centerX,
        centerY: layout.headCenterY + layout.headRadiusY * 0.52,
        radiusX: layout.headRadiusX * 0.70,
        radiusY: layout.headRadiusY * 0.34,
        color: skin.blended(with: .black, amount: 0.10),
        marksPerson: true,
        marksSkin: true
    )
    canvas.fillEllipse(
        centerX: layout.centerX - layout.headRadiusX * 0.48,
        centerY: layout.headCenterY + layout.headRadiusY * 0.20,
        radiusX: layout.headRadiusX * 0.24,
        radiusY: layout.headRadiusY * 0.16,
        color: skin.blended(with: hair, amount: 0.05),
        marksPerson: true,
        marksSkin: true
    )
}

private func drawHairFront(
    layout: SubjectLayout,
    style: Int,
    color: RGB8,
    canvas: inout PortraitCanvas
) {
    var capPoints: [SIMD2<Double>] = []
    let lowerY = layout.headCenterY - layout.headHeight * 0.20
    capPoints.append(SIMD2<Double>(layout.centerX - layout.headRadiusX * 1.04, lowerY))
    for index in 0 ... 12 {
        let angle = Double.pi + Double(index) / 12.0 * Double.pi
        capPoints.append(
            SIMD2<Double>(
                layout.centerX + cos(angle) * layout.headRadiusX * 1.04,
                layout.headCenterY + sin(angle) * layout.headRadiusY * 1.02
            )
        )
    }
    capPoints.append(SIMD2<Double>(layout.centerX + layout.headRadiusX * 1.04, lowerY))
    capPoints.append(SIMD2<Double>(layout.centerX + layout.headRadiusX * 0.80, lowerY - layout.headHeight * 0.03))
    capPoints.append(SIMD2<Double>(layout.centerX + layout.headRadiusX * 0.25, lowerY + layout.headHeight * 0.02))
    capPoints.append(SIMD2<Double>(layout.centerX - layout.headRadiusX * 0.35, lowerY - layout.headHeight * 0.01))
    capPoints.append(SIMD2<Double>(layout.centerX - layout.headRadiusX * 0.82, lowerY - layout.headHeight * 0.04))
    canvas.fillPolygon(points: capPoints, color: color, marksPerson: true)

    // Side locks frame the face.
    for direction in [-1.0, 1.0] {
        let lockLength: Double
        switch style {
        case 2: lockLength = 1.05
        case 1: lockLength = 0.65
        default: lockLength = 0.30
        }
        canvas.fillCapsule(
            fromX: layout.centerX + direction * layout.headRadiusX * 0.92,
            fromY: layout.headCenterY - layout.headRadiusY * 0.25,
            toX: layout.centerX + direction * layout.headRadiusX * 1.02,
            toY: layout.headCenterY + layout.headRadiusY * lockLength,
            radius: layout.headRadiusX * 0.16,
            color: color.blended(with: .black, amount: 0.04),
            marksPerson: true
        )
    }
}

private func drawFace(
    layout: SubjectLayout,
    skin: RGB8,
    hair: RGB8,
    palette: PortraitPalette,
    canvas: inout PortraitCanvas
) {
    let eyes = layout.eyeCenters
    let browColor = hair.blended(with: .black, amount: 0.30)
    let irisColor = palette.eyeColor(seed: layout.subject.seed)

    for eye in [eyes.left, eyes.right] {
        canvas.fillEllipse(
            centerX: eye.x,
            centerY: eye.y,
            radiusX: layout.headRadiusX * 0.115,
            radiusY: layout.headRadiusY * 0.080,
            color: RGB8(red: 246, green: 242, blue: 236),
            marksPerson: true
        )
        canvas.fillEllipse(
            centerX: eye.x,
            centerY: eye.y,
            radiusX: layout.headRadiusX * 0.055,
            radiusY: layout.headRadiusY * 0.058,
            color: irisColor,
            marksPerson: true
        )
        canvas.fillEllipse(
            centerX: eye.x,
            centerY: eye.y,
            radiusX: layout.headRadiusX * 0.026,
            radiusY: layout.headRadiusY * 0.030,
            color: .black,
            marksPerson: true
        )
        canvas.fillEllipse(
            centerX: eye.x - layout.headRadiusX * 0.020,
            centerY: eye.y - layout.headRadiusY * 0.022,
            radiusX: layout.headRadiusX * 0.010,
            radiusY: layout.headRadiusY * 0.012,
            color: .white,
            marksPerson: true
        )
    }

    // Eyebrows.
    for eye in [eyes.left, eyes.right] {
        canvas.fillCapsule(
            fromX: eye.x - layout.headRadiusX * 0.16,
            fromY: eye.y - layout.headHeight * 0.10,
            toX: eye.x + layout.headRadiusX * 0.16,
            toY: eye.y - layout.headHeight * 0.11,
            radius: layout.headHeight * 0.016,
            color: browColor,
            marksPerson: true
        )
    }

    // Nose shading and nostrils.
    let noseTop = SIMD2<Double>(layout.centerX, layout.headCenterY + layout.headHeight * 0.02)
    let noseLeft = SIMD2<Double>(layout.centerX - layout.headRadiusX * 0.10, layout.noseBaseY)
    let noseRight = SIMD2<Double>(layout.centerX + layout.headRadiusX * 0.10, layout.noseBaseY)
    canvas.fillPolygon(
        points: [noseTop, noseLeft, noseRight],
        color: skin.blended(with: .black, amount: 0.12),
        marksPerson: true,
        marksSkin: true
    )
    for direction in [-1.0, 1.0] {
        canvas.fillEllipse(
            centerX: layout.centerX + direction * layout.headRadiusX * 0.075,
            centerY: layout.noseBaseY,
            radiusX: layout.headRadiusX * 0.022,
            radiusY: layout.headRadiusY * 0.018,
            color: skin.blended(with: .black, amount: 0.38),
            marksPerson: true
        )
    }

    // Lips.
    canvas.fillEllipse(
        centerX: layout.centerX,
        centerY: layout.lipY,
        radiusX: layout.headRadiusX * 0.23,
        radiusY: layout.headHeight * 0.075,
        color: palette.lipColor(seed: layout.subject.seed),
        marksPerson: true
    )
    canvas.fillCapsule(
        fromX: layout.centerX - layout.headRadiusX * 0.20,
        fromY: layout.lipY,
        toX: layout.centerX + layout.headRadiusX * 0.20,
        toY: layout.lipY,
        radius: layout.headHeight * 0.012,
        color: RGB8(red: 84, green: 46, blue: 46),
        marksPerson: true
    )
}

private func drawOcclusion(
    layout: SubjectLayout,
    subject: PortraitSubjectSpec,
    skin: RGB8,
    outfit: RGB8,
    hair: RGB8,
    canvas: inout PortraitCanvas
) {
    switch subject.occlusion {
    case .none:
        break
    case .hairOverFace:
        let points: [SIMD2<Double>] = [
            SIMD2<Double>(layout.centerX + layout.headRadiusX * 0.10, layout.headCenterY - layout.headRadiusY * 0.95),
            SIMD2<Double>(layout.centerX + layout.headRadiusX * 1.02, layout.headCenterY - layout.headRadiusY * 0.20),
            SIMD2<Double>(layout.centerX + layout.headRadiusX * 0.72, layout.headCenterY + layout.headRadiusY * 0.78),
            SIMD2<Double>(layout.centerX + layout.headRadiusX * 0.30, layout.headCenterY + layout.headRadiusY * 0.42),
            SIMD2<Double>(layout.centerX - layout.headRadiusX * 0.02, layout.headCenterY - layout.headRadiusY * 0.10)
        ]
        canvas.fillPolygon(points: points, color: hair, marksPerson: true)
    case .handAtChin:
        canvas.fillCapsule(
            fromX: layout.rightElbow.x, fromY: layout.rightElbow.y,
            toX: layout.rightWrist.x, toY: layout.rightWrist.y,
            radius: layout.armRadius * 0.85,
            color: skin,
            marksPerson: true,
            marksSkin: true
        )
        canvas.fillEllipse(
            centerX: layout.rightWrist.x,
            centerY: layout.rightWrist.y,
            radiusX: layout.armRadius * 0.95,
            radiusY: layout.armRadius * 1.05,
            color: skin,
            marksPerson: true,
            marksSkin: true
        )
    case .armAcrossTorso:
        break
    case .objectInFront:
        let phoneWidth = layout.headWidth * 0.26
        let phoneHeight = layout.headHeight * 0.46
        let phoneX = layout.centerX + layout.waistHalf * 0.10
        let phoneY = layout.waistY - layout.headHeight * 0.42
        canvas.fillRect(
            x: Int(phoneX - phoneWidth * 0.5),
            y: Int(phoneY - phoneHeight * 0.5),
            width: Int(phoneWidth),
            height: Int(phoneHeight),
            color: RGB8(red: 28, green: 30, blue: 34),
            marksPerson: true
        )
        canvas.fillRect(
            x: Int(phoneX - phoneWidth * 0.36),
            y: Int(phoneY - phoneHeight * 0.40),
            width: Int(phoneWidth * 0.72),
            height: Int(phoneHeight * 0.80),
            color: RGB8(red: 70, green: 107, blue: 122),
            marksPerson: true
        )
        canvas.fillEllipse(
            centerX: layout.rightWrist.x,
            centerY: layout.rightWrist.y,
            radiusX: layout.armRadius * 0.95,
            radiusY: layout.armRadius * 1.0,
            color: skin,
            marksPerson: true,
            marksSkin: true
        )
    case .scarf:
        let top = layout.chinY - layout.headHeight * 0.02
        let bottom = layout.shoulderY + layout.headHeight * 0.22
        let points: [SIMD2<Double>] = [
            SIMD2<Double>(layout.centerX - layout.headRadiusX * 0.95, top),
            SIMD2<Double>(layout.centerX + layout.headRadiusX * 0.95, top),
            SIMD2<Double>(layout.centerX + layout.headRadiusX * 0.72, bottom),
            SIMD2<Double>(layout.centerX - layout.headRadiusX * 0.72, bottom)
        ]
        canvas.fillPolygon(points: points, color: outfit, marksPerson: true)
        canvas.fillCapsule(
            fromX: layout.centerX - layout.headRadiusX * 0.75,
            fromY: top + (bottom - top) * 0.30,
            toX: layout.centerX + layout.headRadiusX * 0.75,
            toY: top + (bottom - top) * 0.30,
            radius: layout.headHeight * 0.02,
            color: outfit.blended(with: .white, amount: 0.18),
            marksPerson: true
        )
    case .looseSleeves:
        break
    }
}

private func addBlemishes(
    layout: SubjectLayout,
    subject: PortraitSubjectSpec,
    into blemishes: inout [Blemish]
) {
    guard subject.role == .primary else { return }
    let count = 2 + Int(subject.seed % 3)
    for index in 0..<count {
        let angle = (Double(index) * 2.399963 + 0.4) * Double.pi
        let radial = 0.25 + 0.35 * hashUnit(seed: subject.seed, index: index)
        let x = layout.centerX + cos(angle) * layout.headRadiusX * radial
        let y = layout.headCenterY + sin(angle) * layout.headRadiusY * radial * 0.8
        blemishes.append(
            Blemish(
                centerX: x,
                centerY: y,
                radius: layout.headHeight * (0.025 + 0.02 * hashUnit(seed: subject.seed, index: index + 9)),
                depth: 10 + 14 * hashUnit(seed: subject.seed, index: index + 17)
            )
        )
    }
}

// MARK: - Background

private func drawBackground(
    _ canvas: inout PortraitCanvas,
    spec: PortraitSampleSpec,
    palette: PortraitPalette
) -> [PortraitGroundTruthLine] {
    let width = Double(spec.width)
    let height = Double(spec.height)
    var lines: [PortraitGroundTruthLine] = []

    // Wall gradient.
    for y in 0 ..< spec.height {
        let t = Double(y) / max(1, Double(spec.height - 1))
        let color = palette.wallTop.blended(with: palette.wallBottom, amount: t * 0.55)
        canvas.fillRect(x: 0, y: y, width: spec.width, height: 1, color: color)
    }

    func floor(horizon: Double) {
        let startY = max(0, min(spec.height, Int(horizon * height)))
        canvas.fillRect(
            x: 0,
            y: startY,
            width: spec.width,
            height: spec.height - startY,
            color: palette.floorA
        )
    }

    func tileGrid(horizon: Double, verticals: [Double], horizontals: [Double]) {
        let lefts = [0.0] + verticals + [1.0]
        var rowIndex = 0
        for row in 0 ..< (horizontals.count + 1) {
            let top = row == 0 ? horizon : horizontals[row - 1]
            let bottom = row == horizontals.count ? 1.0 : horizontals[row]
            let shade = palette.floorA.blended(
                with: palette.floorB,
                amount: rowIndex % 2 == 0 ? 0.10 : 0.32
            )
            var columnIndex = 0
            for column in 0 ..< (lefts.count - 1) {
                let left = lefts[column]
                let right = lefts[column + 1]
                let cellShade = shade.blended(
                    with: palette.floorB,
                    amount: columnIndex % 2 == 0 ? 0.06 : 0.18
                )
                canvas.fillRect(
                    x: Int(left * width),
                    y: Int(top * height),
                    width: max(1, Int((right - left) * width)),
                    height: max(1, Int((bottom - top) * height)),
                    color: cellShade
                )
                columnIndex += 1
            }
            rowIndex += 1
        }
    }

    switch spec.background {
    case .doorFrame:
        floor(horizon: 0.66)
        canvas.fillRect(
            x: Int(0.17 * width),
            y: Int(0.07 * height),
            width: Int(0.66 * width),
            height: Int(0.59 * height),
            color: palette.door
        )
        lines.append(verticalLine(&canvas, spec: spec, x: 0.14, start: 0.02, end: 0.66, label: "door.left", color: palette.line, thickness: 0.012))
        lines.append(verticalLine(&canvas, spec: spec, x: 0.86, start: 0.02, end: 0.66, label: "door.right", color: palette.line, thickness: 0.012))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.06, start: 0.14, end: 0.86, label: "door.lintel", color: palette.line, thickness: 0.012))
        lines.append(verticalLine(&canvas, spec: spec, x: 0.20, start: 0.07, end: 0.66, label: "door.panel.left", color: palette.line, thickness: 0.008))
        lines.append(verticalLine(&canvas, spec: spec, x: 0.80, start: 0.07, end: 0.66, label: "door.panel.right", color: palette.line, thickness: 0.008))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.36, start: 0.20, end: 0.80, label: "door.panel.top", color: palette.line, thickness: 0.008))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.62, start: 0.20, end: 0.80, label: "door.panel.bottom", color: palette.line, thickness: 0.008))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.66, start: 0, end: 1, label: "floor.horizon", color: palette.line, thickness: 0.010))
    case .floorTiles:
        floor(horizon: 0.58)
        let verticals = [0.10, 0.30, 0.50, 0.70, 0.90]
        let horizontals = [0.68, 0.78, 0.88, 0.96]
        tileGrid(horizon: 0.58, verticals: verticals, horizontals: horizontals)
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.58, start: 0, end: 1, label: "floor.horizon", color: palette.line, thickness: 0.010))
        for (index, x) in verticals.enumerated() {
            lines.append(verticalLine(&canvas, spec: spec, x: x, start: 0.58, end: 1, label: "tile.v\(index)", color: palette.line, thickness: 0.008))
        }
        for (index, y) in horizontals.enumerated() {
            lines.append(horizontalLine(&canvas, spec: spec, y: y, start: 0, end: 1, label: "tile.h\(index)", color: palette.line, thickness: 0.008))
        }
    case .doorFrameAndTiles:
        floor(horizon: 0.60)
        canvas.fillRect(
            x: Int(0.12 * width),
            y: Int(0.02 * height),
            width: Int(0.76 * width),
            height: Int(0.58 * height),
            color: palette.door
        )
        let verticals = [0.34, 0.50, 0.66]
        let horizontals = [0.74, 0.86, 0.96]
        tileGrid(horizon: 0.60, verticals: verticals, horizontals: horizontals)
        lines.append(verticalLine(&canvas, spec: spec, x: 0.12, start: 0.02, end: 0.60, label: "door.left", color: palette.line, thickness: 0.012))
        lines.append(verticalLine(&canvas, spec: spec, x: 0.88, start: 0.02, end: 0.60, label: "door.right", color: palette.line, thickness: 0.012))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.06, start: 0.12, end: 0.88, label: "door.lintel", color: palette.line, thickness: 0.012))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.60, start: 0, end: 1, label: "floor.horizon", color: palette.line, thickness: 0.010))
        for (index, x) in verticals.enumerated() {
            lines.append(verticalLine(&canvas, spec: spec, x: x, start: 0.60, end: 1, label: "tile.v\(index)", color: palette.line, thickness: 0.008))
        }
        for (index, y) in horizontals.enumerated() {
            lines.append(horizontalLine(&canvas, spec: spec, y: y, start: 0, end: 1, label: "tile.h\(index)", color: palette.line, thickness: 0.008))
        }
    case .window:
        floor(horizon: 0.72)
        canvas.fillRect(
            x: Int(0.05 * width),
            y: Int(0.05 * height),
            width: Int(0.40 * width),
            height: Int(0.33 * height),
            color: palette.window
        )
        lines.append(verticalLine(&canvas, spec: spec, x: 0.05, start: 0.05, end: 0.38, label: "window.left", color: palette.line, thickness: 0.012))
        lines.append(verticalLine(&canvas, spec: spec, x: 0.25, start: 0.05, end: 0.38, label: "window.mullion", color: palette.line, thickness: 0.010))
        lines.append(verticalLine(&canvas, spec: spec, x: 0.45, start: 0.05, end: 0.38, label: "window.right", color: palette.line, thickness: 0.012))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.05, start: 0.05, end: 0.45, label: "window.top", color: palette.line, thickness: 0.012))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.20, start: 0.05, end: 0.45, label: "window.sash", color: palette.line, thickness: 0.010))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.38, start: 0.05, end: 0.45, label: "window.bottom", color: palette.line, thickness: 0.012))
        lines.append(verticalLine(&canvas, spec: spec, x: 0.92, start: 0, end: 1, label: "wall.corner", color: palette.line, thickness: 0.010))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.72, start: 0, end: 1, label: "floor.horizon", color: palette.line, thickness: 0.010))
    case .tableEdge:
        canvas.fillRect(
            x: 0,
            y: Int(0.50 * height),
            width: spec.width,
            height: Int(0.12 * height),
            color: palette.table
        )
        floor(horizon: 0.84)
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.50, start: 0, end: 1, label: "table.top", color: palette.line, thickness: 0.012))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.62, start: 0, end: 1, label: "table.bottom", color: palette.line, thickness: 0.010))
        lines.append(verticalLine(&canvas, spec: spec, x: 0.90, start: 0, end: 0.50, label: "wall.corner", color: palette.line, thickness: 0.010))
        lines.append(horizontalLine(&canvas, spec: spec, y: 0.84, start: 0, end: 1, label: "floor.horizon", color: palette.line, thickness: 0.010))
    case .plain:
        // A soft wall gradient and a vignette; intentionally no straight lines.
        for y in 0 ..< spec.height {
            let t = Double(y) / max(1, Double(spec.height - 1))
            let color = palette.wallTop.blended(
                with: palette.wallBottom.blended(with: .black, amount: 0.25),
                amount: 0.25 + t * 0.55
            )
            canvas.fillRect(x: 0, y: y, width: spec.width, height: 1, color: color)
        }
    }
    return lines
}

private func verticalLine(
    _ canvas: inout PortraitCanvas,
    spec: PortraitSampleSpec,
    x: Double,
    start: Double,
    end: Double,
    label: String,
    color: RGB8,
    thickness: Double
) -> PortraitGroundTruthLine {
    let width = Double(spec.width)
    let height = Double(spec.height)
    canvas.strokeVerticalLine(
        x: x * width,
        startY: start * height,
        endY: end * height,
        thickness: max(1, thickness * width),
        color: color,
        marksStructure: true
    )
    return PortraitGroundTruthLine(
        orientation: .vertical,
        position: x,
        start: start,
        end: end,
        label: label
    )
}

private func horizontalLine(
    _ canvas: inout PortraitCanvas,
    spec: PortraitSampleSpec,
    y: Double,
    start: Double,
    end: Double,
    label: String,
    color: RGB8,
    thickness: Double
) -> PortraitGroundTruthLine {
    let width = Double(spec.width)
    let height = Double(spec.height)
    canvas.strokeHorizontalLine(
        y: y * height,
        startX: start * width,
        endX: end * width,
        thickness: max(1, thickness * height),
        color: color,
        marksStructure: true
    )
    return PortraitGroundTruthLine(
        orientation: .horizontal,
        position: y,
        start: start,
        end: end,
        label: label
    )
}

// MARK: - Lighting and texture

private func applyLighting(_ canvas: inout PortraitCanvas, spec: PortraitSampleSpec) {
    let width = Double(spec.width)
    let height = Double(spec.height)
    for y in 0 ..< spec.height {
        let normalizedY = (Double(y) + 0.5) / height
        for x in 0 ..< spec.width {
            let normalizedX = (Double(x) + 0.5) / width
            var redGain = 1.0
            var greenGain = 1.0
            var blueGain = 1.0
            switch spec.lighting {
            case .softKey:
                let gain = 0.93 + 0.08 * (1 - normalizedX)
                redGain = gain
                greenGain = gain
                blueGain = gain
            case .sideKey:
                let gain = 0.82 + 0.26 * (1 - normalizedX)
                redGain = gain * 1.02
                greenGain = gain
                blueGain = gain * 0.98
            case .backlit:
                let gain = 0.80 + 0.16 * (1 - normalizedY)
                redGain = gain
                greenGain = gain
                blueGain = gain * 1.02
            case .lowKey:
                let gain = 0.68 + 0.10 * (1 - normalizedX)
                redGain = gain
                greenGain = gain
                blueGain = gain
            case .highKey:
                let gain = 0.98 + 0.06 * (1 - normalizedX)
                redGain = gain
                greenGain = gain
                blueGain = gain
            case .mixed:
                let gain = 0.90 + 0.14 * (1 - normalizedX)
                redGain = gain * 1.04
                greenGain = gain
                blueGain = gain * 0.98
            }
            canvas.updateColor(x: x, y: y) { color in
                RGB8(
                    red: clampedByte(Double(color.red) * redGain),
                    green: clampedByte(Double(color.green) * greenGain),
                    blue: clampedByte(Double(color.blue) * blueGain)
                )
            }
        }
    }
}

private func applyTexture(
    _ canvas: inout PortraitCanvas,
    spec: PortraitSampleSpec,
    blemishes: [Blemish],
    highlights: [SIMD2<Double>]
) {
    for y in 0 ..< spec.height {
        let yy = Double(y) + 0.5
        for x in 0 ..< spec.width {
            let xx = Double(x) + 0.5
            if canvas.isSkin(x: x, y: y) {
                let lowA = 0.020 * sin(2 * Double.pi * xx / 37 + 0.7) * sin(2 * Double.pi * yy / 41 + 1.3)
                let lowB = 0.012 * sin(2 * Double.pi * xx / 19 - 0.2) * cos(2 * Double.pi * yy / 23 + 0.9)
                let low = lowA + lowB
                let noise = hashSigned(x: x, y: y, seed: spec.seed)
                let poreA = 0.65 * noise
                let poreB = 0.35 * sin(2 * Double.pi * xx / 3.2) * sin(2 * Double.pi * yy / 3.7)
                let pore = poreA + poreB
                let baseLuma = canvas.color(x: x, y: y)?.luma ?? 128
                let amplitude = 1.8 + 2.0 * (1 - baseLuma / 255)
                var delta = (low * 255 + 2.4 * pore) * amplitude / 2.4
                for blemish in blemishes {
                    let dx = xx - blemish.centerX
                    let dy = yy - blemish.centerY
                    let distance = (dx * dx + dy * dy).squareRoot()
                    if distance < blemish.radius {
                        let falloff = 1 - distance / blemish.radius
                        delta -= blemish.depth * falloff * falloff
                    }
                }
                var highlightDelta = 0.0
                for highlight in highlights {
                    let dx = xx - highlight.x
                    let dy = yy - highlight.y
                    let sigma = max(2, Double(spec.width) * 0.02)
                    let distance = (dx * dx + dy * dy) / (2 * sigma * sigma)
                    highlightDelta += 5.5 * exp(-distance)
                }
                let finalDelta = delta + highlightDelta
                canvas.updateColor(x: x, y: y) { color in
                    RGB8(
                        red: clampedByte(Double(color.red) + finalDelta * 1.05),
                        green: clampedByte(Double(color.green) + finalDelta * 0.95),
                        blue: clampedByte(Double(color.blue) + finalDelta * 0.85)
                    )
                }
            } else if canvas.isPerson(x: x, y: y) {
                let grain = 1.8 * hashSigned(x: x, y: y, seed: spec.seed &+ 11)
                canvas.updateColor(x: x, y: y) { color in
                    RGB8(
                        red: clampedByte(Double(color.red) + grain),
                        green: clampedByte(Double(color.green) + grain),
                        blue: clampedByte(Double(color.blue) + grain)
                    )
                }
            } else {
                let grain = 2.2 * hashSigned(x: x, y: y, seed: spec.seed &+ 29)
                canvas.updateColor(x: x, y: y) { color in
                    RGB8(
                        red: clampedByte(Double(color.red) + grain),
                        green: clampedByte(Double(color.green) + grain * 0.9),
                        blue: clampedByte(Double(color.blue) + grain * 0.8)
                    )
                }
            }
        }
    }
}

// MARK: - Palette and deterministic helpers

private struct PortraitPalette {
    let wallTop: RGB8
    let wallBottom: RGB8
    let floorA: RGB8
    let floorB: RGB8
    let door: RGB8
    let table: RGB8
    let window: RGB8
    let line: RGB8
    let hairColors: [RGB8]
    let outfitColors: [RGB8]
    let eyeColors: [RGB8]
    let lipColors: [RGB8]

    init(spec: PortraitSampleSpec) {
        let walls = [
            RGB8(red: 203, green: 187, blue: 168),
            RGB8(red: 216, green: 207, blue: 196),
            RGB8(red: 185, green: 175, blue: 163),
            RGB8(red: 227, green: 214, blue: 198),
            RGB8(red: 169, green: 179, blue: 184),
            RGB8(red: 196, green: 177, blue: 165)
        ]
        let index = Int(spec.seed % UInt64(walls.count))
        wallTop = walls[index]
        wallBottom = walls[(index + 2) % walls.count]
        floorA = [
            RGB8(red: 154, green: 128, blue: 106),
            RGB8(red: 176, green: 146, blue: 119),
            RGB8(red: 126, green: 106, blue: 88)
        ][Int(spec.seed % 3)]
        floorB = floorA.blended(with: .black, amount: 0.18)
        door = [
            RGB8(red: 122, green: 92, blue: 69),
            RGB8(red: 107, green: 77, blue: 58),
            RGB8(red: 138, green: 111, blue: 86)
        ][Int((spec.seed / 3) % 3)]
        table = RGB8(red: 142, green: 112, blue: 84)
        window = RGB8(red: 188, green: 210, blue: 218)
        line = [
            RGB8(red: 48, green: 42, blue: 38),
            RGB8(red: 58, green: 48, blue: 41),
            RGB8(red: 40, green: 46, blue: 50)
        ][Int((spec.seed / 7) % 3)]
        hairColors = [
            RGB8(red: 34, green: 26, blue: 22),
            RGB8(red: 62, green: 43, blue: 30),
            RGB8(red: 24, green: 22, blue: 24),
            RGB8(red: 110, green: 78, blue: 48),
            RGB8(red: 84, green: 82, blue: 80)
        ]
        outfitColors = [
            RGB8(red: 46, green: 84, blue: 96),
            RGB8(red: 44, green: 54, blue: 92),
            RGB8(red: 128, green: 66, blue: 52),
            RGB8(red: 74, green: 88, blue: 58),
            RGB8(red: 96, green: 48, blue: 66),
            RGB8(red: 168, green: 146, blue: 88),
            RGB8(red: 104, green: 104, blue: 110),
            RGB8(red: 208, green: 204, blue: 196)
        ]
        eyeColors = [
            RGB8(red: 76, green: 54, blue: 38),
            RGB8(red: 54, green: 74, blue: 62),
            RGB8(red: 48, green: 62, blue: 86),
            RGB8(red: 90, green: 66, blue: 44)
        ]
        lipColors = [
            RGB8(red: 168, green: 104, blue: 96),
            RGB8(red: 148, green: 86, blue: 82),
            RGB8(red: 184, green: 120, blue: 108),
            RGB8(red: 132, green: 76, blue: 74)
        ]
    }

    func hairColor(seed: UInt64) -> RGB8 {
        hairColors[Int(seed % UInt64(hairColors.count))]
    }

    func outfitColor(seed: UInt64) -> RGB8 {
        outfitColors[Int((seed / 5) % UInt64(outfitColors.count))]
    }

    func eyeColor(seed: UInt64) -> RGB8 {
        eyeColors[Int((seed / 3) % UInt64(eyeColors.count))]
    }

    func lipColor(seed: UInt64) -> RGB8 {
        lipColors[Int((seed / 11) % UInt64(lipColors.count))]
    }
}

private func clampedByte(_ value: Double) -> UInt8 {
    guard value.isFinite else { return 0 }
    return UInt8(min(max(value.rounded(), 0), 255))
}

private func hashSigned(x: Int, y: Int, seed: UInt64) -> Double {
    var value = UInt64(
        bitPattern: Int64(x) &* 374_761_393 &+ Int64(y) &* 668_265_263
    )
    value ^= seed &* 2_246_822_519_749_945_189
    value = (value ^ (value >> 13)) &* 1_274_126_177
    value ^= value >> 16
    return Double(value & 0xFFFF) / 32_767.5 - 1
}

private func hashUnit(seed: UInt64, index: Int) -> Double {
    var value = seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    value ^= value >> 31
    return Double(value & 0xFFFF) / 65_535.0
}
