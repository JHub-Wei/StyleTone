import Foundation
import StyleToneCore

/// Pure planner behind ``BodyWarpContributor``.
///
/// The planner reads pose joints and the person mask, but never the image
/// pixels. All decisions are image-relative and deterministic, which makes the
/// pass testable without Vision or Metal.
struct BodyWarpPlanner {
    let configuration: BodyWarpConfiguration

    func makePlan(
        analysis: PortraitAnalysis,
        parameters: GeometryParameters,
        gridWidth: Int,
        gridHeight: Int
    ) throws -> BodyWarpPlan {
        guard gridWidth >= 2, gridHeight >= 2 else {
            throw GeometryError.invalidGrid(width: gridWidth, height: gridHeight)
        }
        let (vertexCount, overflow) = gridWidth.multipliedReportingOverflow(by: gridHeight)
        guard !overflow else {
            throw GeometryError.invalidGrid(width: gridWidth, height: gridHeight)
        }

        let armStrength = BodyWarpMath.clamp(parameters.body.arm, to: 0 ... 1)
        let waistStrength = BodyWarpMath.clamp(parameters.body.waist, to: 0 ... 1)
        guard armStrength > 0 || waistStrength > 0 else {
            return zeroPlan(
                width: gridWidth,
                height: gridHeight,
                vertexCount: vertexCount,
                warnings: []
            )
        }

        var warnings = BodyWarpWarningCollector()
        guard let body = analysis.body else {
            warnings.add(.noBody)
            return zeroPlan(
                width: gridWidth,
                height: gridHeight,
                vertexCount: vertexCount,
                warnings: warnings.ordered
            )
        }
        guard let personMask = analysis.personMask else {
            warnings.add(.noSegmentation)
            return zeroPlan(
                width: gridWidth,
                height: gridHeight,
                vertexCount: vertexCount,
                warnings: warnings.ordered
            )
        }
        guard let metricSpace = BodyWarpMetricSpace(imageSize: analysis.imageSize) else {
            warnings.add(.noSegmentation)
            return zeroPlan(
                width: gridWidth,
                height: gridHeight,
                vertexCount: vertexCount,
                warnings: warnings.ordered
            )
        }

        let mask = BodyWarpMask(personMask)
        let rawConfidence = Double(body.confidence)
        let confidence: Double
        if rawConfidence.isFinite {
            confidence = BodyWarpMath.clamp(rawConfidence, to: 0 ... 1)
        } else {
            confidence = 0
        }
        var confidenceScale = BodyWarpMath.smoothstep(
            Double(configuration.minimumBodyConfidence),
            Double(configuration.fullStrengthConfidence),
            confidence
        )
        var blocked = false

        if analysis.warnings.contains(.occlusion) {
            warnings.add(.occlusion)
            blocked = true
        }
        if confidence < Double(configuration.minimumBodyConfidence) {
            warnings.add(.lowConfidence)
            blocked = true
        } else if confidence < Double(configuration.fullStrengthConfidence) {
            warnings.add(.lowConfidence)
        }
        if analysis.warnings.contains(.lowConfidence) {
            warnings.add(.lowConfidence)
            confidenceScale *= 0.80
        }

        var multipleFaces = analysis.faces.count > 1
        if analysis.warnings.contains(.multipleFaces) {
            multipleFaces = true
        }
        let multipleBlobs = mask.hasMultiplePeople(
            probeSize: configuration.multiplePersonProbeSize,
            minimumAreaFraction: configuration.minimumMultiplePersonAreaFraction
        )
        let multiplePeople = multipleFaces || multipleBlobs
        if multiplePeople {
            warnings.add(.multiplePeople)
            switch configuration.multiplePersonPolicy {
            case .skip:
                blocked = true
            case .primaryBody:
                confidenceScale *= configuration.primaryBodyStrengthScale
            }
        }

        guard !blocked else {
            return zeroPlan(
                width: gridWidth,
                height: gridHeight,
                vertexCount: vertexCount,
                warnings: warnings.ordered
            )
        }
        guard configuration.maximumCombinedInset > 0 else {
            warnings.add(.strengthLimited)
            return zeroPlan(
                width: gridWidth,
                height: gridHeight,
                vertexCount: vertexCount,
                warnings: warnings.ordered
            )
        }

        let needArm = armStrength > 0
        let needWaist = waistStrength > 0
        let pose = BodyPoseGeometry(
            joints: body.joints,
            metricSpace: metricSpace,
            configuration: configuration
        )

        var selectedArms: [SelectedArm] = []
        var allArms: [BodyArmCapsule] = []
        for (region, status) in [
            (BodyWarpRegion.leftArm, pose.leftArm),
            (BodyWarpRegion.rightArm, pose.rightArm)
        ] {
            switch status {
            case let .available(arm):
                allArms.append(arm)
                if needArm {
                    selectedArms.append(SelectedArm(region: region, arm: arm))
                }
            case .missingJoints:
                if needArm {
                    warnings.add(.incompletePose)
                }
            case .degenerate:
                if needArm {
                    warnings.add(.degeneratePose)
                }
            }
        }

        if needArm {
            selectedArms = selectedArms.filter { selected in
                let coverage = mask.coverage(
                    at: selected.arm.coveragePoints(metricSpace: metricSpace)
                )
                if coverage < configuration.minimumRegionMaskCoverage {
                    warnings.add(.occlusion)
                    return false
                }
                return true
            }
        }

        var torsoFrame: BodyTorsoFrame?
        switch pose.torso {
        case let .available(frame):
            torsoFrame = frame
        case .missingJoints:
            if needWaist {
                warnings.add(.incompletePose)
            }
        case .degenerate:
            if needWaist {
                warnings.add(.degeneratePose)
            }
        }

        var waistShape: WaistShape?
        if needWaist, let frame = torsoFrame {
            let coverage = mask.coverage(
                at: frame.coveragePoints(metricSpace: metricSpace)
            )
            if coverage < configuration.minimumRegionMaskCoverage {
                warnings.add(.occlusion)
            } else if let measured = measureWaist(
                frame: frame,
                mask: mask,
                metricSpace: metricSpace
            ) {
                waistShape = measured
            } else {
                warnings.add(.weakSegmentation)
            }
        }

        if needArm, selectedArms.isEmpty, !warnings.contains(.incompletePose),
           !warnings.contains(.degeneratePose), !warnings.contains(.occlusion)
        {
            warnings.add(.weakSegmentation)
        }
        if needWaist, waistShape == nil, !warnings.contains(.incompletePose),
           !warnings.contains(.degeneratePose), !warnings.contains(.occlusion)
        {
            warnings.add(.weakSegmentation)
        }

        var offsets = [SIMD2<Float>](
            repeating: .zero,
            count: vertexCount
        )
        var appliedRegions: Set<BodyWarpRegion> = []
        var peakDisplacement = 0.0
        var didClampToLimit = false

        for y in 0 ..< gridHeight {
            let normalizedY = Double(y) / Double(gridHeight - 1)
            for x in 0 ..< gridWidth {
                let point = NormalizedPoint(
                    x: Double(x) / Double(gridWidth - 1),
                    y: normalizedY
                )
                let gate = mask.gate(
                    at: point,
                    lower: configuration.maskGateLower,
                    upper: configuration.maskGateUpper
                )
                guard gate > 0 else {
                    continue
                }

                let metricPoint = metricSpace.point(point)
                var displacement = SIMD2<Double>.zero

                if needArm {
                    for selected in selectedArms {
                        let armOffset = armDisplacement(
                            at: metricPoint,
                            arm: selected.arm,
                            gate: gate,
                            strength: armStrength,
                            confidenceScale: confidenceScale,
                            torsoFrame: torsoFrame
                        )
                        if BodyWarpMath.length(armOffset) > 1e-9 {
                            displacement += armOffset
                            appliedRegions.insert(selected.region)
                        }
                    }
                }

                if needWaist, let waistShape {
                    let waistOffset = waistDisplacement(
                        at: metricPoint,
                        shape: waistShape,
                        arms: allArms,
                        gate: gate,
                        strength: waistStrength,
                        confidenceScale: confidenceScale
                    )
                    if BodyWarpMath.length(waistOffset) > 1e-9 {
                        displacement += waistOffset
                        appliedRegions.insert(.waist)
                    }
                }

                let magnitude = BodyWarpMath.length(displacement)
                guard magnitude > 1e-9 else {
                    continue
                }
                if magnitude > configuration.maximumCombinedInset {
                    displacement = displacement * (configuration.maximumCombinedInset / magnitude)
                    didClampToLimit = true
                }
                let clampedMagnitude = min(magnitude, configuration.maximumCombinedInset)
                peakDisplacement = max(peakDisplacement, clampedMagnitude)
                offsets[y * gridWidth + x] = metricSpace.offset(from: displacement)
            }
        }

        if didClampToLimit {
            warnings.add(.strengthLimited)
        }
        if appliedRegions.isEmpty, !warnings.isEmpty {
            return BodyWarpPlan(
                width: gridWidth,
                height: gridHeight,
                offsets: offsets,
                warnings: warnings.ordered,
                appliedRegions: appliedRegions,
                peakDisplacement: peakDisplacement,
                didClampToLimit: didClampToLimit
            )
        }
        if appliedRegions.isEmpty {
            warnings.add(.weakSegmentation)
            return zeroPlan(
                width: gridWidth,
                height: gridHeight,
                vertexCount: vertexCount,
                warnings: warnings.ordered
            )
        }

        return BodyWarpPlan(
            width: gridWidth,
            height: gridHeight,
            offsets: offsets,
            warnings: warnings.ordered,
            appliedRegions: appliedRegions,
            peakDisplacement: peakDisplacement,
            didClampToLimit: didClampToLimit
        )
    }

    private func measureWaist(
        frame: BodyTorsoFrame,
        mask: BodyWarpMask,
        metricSpace: BodyWarpMetricSpace
    ) -> WaistShape? {
        let maximumHalfWidth = configuration.maximumWaistToShoulderSpan * frame.shoulderSpan
        guard maximumHalfWidth >= configuration.minimumWaistHalfWidth else {
            return nil
        }

        var leftDistances: [Double] = []
        var rightDistances: [Double] = []
        for offset in [-0.06, 0.0, 0.06] {
            let t = BodyWarpMath.clamp(
                configuration.waistCenterFraction + offset,
                to: 0.25 ... 0.85
            )
            guard let left = scanWaistEdge(
                t: t,
                direction: -1,
                frame: frame,
                mask: mask,
                metricSpace: metricSpace,
                maximumHalfWidth: maximumHalfWidth
            ), let right = scanWaistEdge(
                t: t,
                direction: 1,
                frame: frame,
                mask: mask,
                metricSpace: metricSpace,
                maximumHalfWidth: maximumHalfWidth
            ) else {
                return nil
            }
            leftDistances.append(left)
            rightDistances.append(right)
        }

        guard let left = BodyWarpMath.median(leftDistances),
              let right = BodyWarpMath.median(rightDistances)
        else {
            return nil
        }

        let cappedLeft = left >= maximumHalfWidth * 0.98
        let cappedRight = right >= maximumHalfWidth * 0.98
        guard !(cappedLeft && cappedRight) else {
            return nil
        }

        let halfWidth: Double
        if cappedLeft {
            halfWidth = right
        } else if cappedRight {
            halfWidth = left
        } else {
            halfWidth = (left + right) * 0.5
        }
        guard halfWidth >= configuration.minimumWaistHalfWidth,
              halfWidth <= maximumHalfWidth
        else {
            return nil
        }

        return WaistShape(
            frame: frame,
            halfWidth: halfWidth,
            centerT: configuration.waistCenterFraction
        )
    }

    private func scanWaistEdge(
        t: Double,
        direction: Double,
        frame: BodyTorsoFrame,
        mask: BodyWarpMask,
        metricSpace: BodyWarpMetricSpace,
        maximumHalfWidth: Double
    ) -> Double? {
        let center = frame.centerPoint(at: t)
        let centerAlpha = mask.alpha(at: metricSpace.normalized(center))
        guard centerAlpha >= configuration.minimumContourMaskAlpha else {
            return nil
        }

        let step = 0.0015
        var distance = step
        var lastInside = 0.0
        while distance <= maximumHalfWidth {
            let point = center + frame.normal * (direction * distance)
            let alpha = mask.alpha(at: metricSpace.normalized(point))
            if alpha >= configuration.minimumContourMaskAlpha {
                lastInside = distance
            } else {
                return lastInside
            }
            distance += step
        }
        return lastInside
    }

    private func armDisplacement(
        at point: SIMD2<Double>,
        arm: BodyArmCapsule,
        gate: Double,
        strength: Double,
        confidenceScale: Double,
        torsoFrame: BodyTorsoFrame?
    ) -> SIMD2<Double> {
        let sample = arm.nearest(to: point)
        guard sample.distance < arm.supportRadius else {
            return .zero
        }

        let normalizedDistance = sample.distance / arm.supportRadius
        let radial = (1 - normalizedDistance * normalizedDistance)
        let radialWeight = radial * radial
        let shoulderWeight = BodyWarpMath.smoothstep(
            0,
            arm.shoulderGuardLength,
            sample.along
        )
        let wristStart = arm.totalLength - arm.handGuardLength
        let handWeight = 1 - BodyWarpMath.smoothstep(
            wristStart,
            arm.totalLength,
            sample.along
        )
        guard shoulderWeight > 0, handWeight > 0 else {
            return .zero
        }

        var torsoProtection = 1.0
        if let torsoFrame {
            let projection = torsoFrame.projection(of: point)
            let halfWidth = torsoFrame.protectionHalfWidth(at: projection.t)
            let verticalIn = BodyWarpMath.smoothstep(-0.12, -0.02, projection.t)
            let verticalOut = BodyWarpMath.smoothstep(1.02, 1.12, projection.t)
            let vertical = verticalIn * (1 - verticalOut)
            let lateral = BodyWarpMath.smoothstep(
                halfWidth * 0.92,
                halfWidth * 1.18,
                abs(projection.lateral)
            )
            torsoProtection = 1 - vertical * (1 - lateral)
        }

        let magnitudeCap = min(
            configuration.maximumArmInset,
            arm.radius * configuration.armInsetFractionOfRadius
        )
        var inset = magnitudeCap * strength * confidenceScale
        inset *= radialWeight * shoulderWeight * handWeight
        inset *= gate * torsoProtection
        inset = min(inset, sample.distance * 0.42)
        guard inset > 1e-9 else {
            return .zero
        }
        return BodyWarpMath.normalized(sample.closest - point) * inset
    }

    private func waistDisplacement(
        at point: SIMD2<Double>,
        shape: WaistShape,
        arms: [BodyArmCapsule],
        gate: Double,
        strength: Double,
        confidenceScale: Double
    ) -> SIMD2<Double> {
        let frame = shape.frame
        let projection = frame.projection(of: point)
        let lateralDistance = abs(projection.lateral)
        guard lateralDistance > 1e-9 else {
            return .zero
        }

        let sigma = max(0.02, configuration.waistBandSigmaFraction * frame.length)
        let axialDelta = (projection.t - shape.centerT) / sigma
        let axialWeight = exp(-0.5 * axialDelta * axialDelta)
        guard axialWeight > 1e-6 else {
            return .zero
        }

        let radius = lateralDistance / shape.halfWidth
        let rise = BodyWarpMath.smoothstep(0.15, 0.62, radius)
        let fall = 1 - BodyWarpMath.smoothstep(
            1.00,
            configuration.waistSupportToHalfWidth,
            radius
        )
        let radialWeight = rise * fall
        guard radialWeight > 1e-9 else {
            return .zero
        }

        var armProtection = 1.0
        for arm in arms {
            let distance = arm.nearest(to: point).distance
            let start = arm.supportRadius * 0.65
            let end = arm.supportRadius * 1.15
            armProtection = min(
                armProtection,
                BodyWarpMath.smoothstep(start, end, distance)
            )
        }
        guard armProtection > 0 else {
            return .zero
        }

        var inset = configuration.maximumWaistInset * strength * confidenceScale
        inset *= axialWeight * radialWeight
        inset *= gate * armProtection
        inset = min(inset, lateralDistance * 0.42)
        guard inset > 1e-9 else {
            return .zero
        }

        let inwardSign = projection.lateral > 0 ? -1.0 : 1.0
        return frame.normal * (inwardSign * inset)
    }

    private func zeroPlan(
        width: Int,
        height: Int,
        vertexCount: Int,
        warnings: [BodyWarpWarning]
    ) -> BodyWarpPlan {
        BodyWarpPlan(
            width: width,
            height: height,
            offsets: [SIMD2<Float>](repeating: .zero, count: vertexCount),
            warnings: warnings,
            appliedRegions: [],
            peakDisplacement: 0,
            didClampToLimit: false
        )
    }
}

private struct SelectedArm {
    let region: BodyWarpRegion
    let arm: BodyArmCapsule
}

private struct WaistShape {
    let frame: BodyTorsoFrame
    let halfWidth: Double
    let centerT: Double
}

private struct BodyWarpWarningCollector {
    private var seen: Set<BodyWarpWarning> = []
    private var values: [BodyWarpWarning] = []

    mutating func add(_ warning: BodyWarpWarning) {
        if seen.insert(warning).inserted {
            values.append(warning)
        }
    }

    func contains(_ warning: BodyWarpWarning) -> Bool {
        seen.contains(warning)
    }

    var isEmpty: Bool {
        values.isEmpty
    }

    var ordered: [BodyWarpWarning] {
        values
    }
}
