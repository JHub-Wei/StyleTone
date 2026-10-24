import Foundation
import StyleToneCore

/// Turns `PortraitAnalysis` + `GeometryParameters` into a bounded leg
/// displacement plan.
///
/// The planner is pure and synchronous. It is the testable heart of the pass;
/// ``LegsWarpContributor`` only converts the resulting plan into a `WarpField`
/// contribution.
struct LegsWarpPlanner: Sendable {
    let configuration: LegsWarpConfiguration

    init(configuration: LegsWarpConfiguration = .standard) {
        self.configuration = configuration
    }

    /// Builds the plan for one mesh density.
    ///
    /// - Throws: ``GeometryError/invalidGrid(width:height:)`` when the mesh is
    ///   smaller than 2x2, or `CancellationError` when the current task is
    ///   cancelled while the grid is evaluated.
    func makePlan(
        analysis: PortraitAnalysis,
        parameters: GeometryParameters,
        gridWidth: Int,
        gridHeight: Int
    ) throws -> LegsWarpPlan {
        guard gridWidth >= 2, gridHeight >= 2 else {
            throw GeometryError.invalidGrid(width: gridWidth, height: gridHeight)
        }
        try Task.checkCancellation()

        let requestedSlim = sanitizedSlim(parameters.body.leg)
        let requestedLength = sanitizedLength(parameters.body.legLength)

        guard let body = analysis.body else {
            return .skipped(
                .noBody,
                warnings: [.noBody],
                width: gridWidth,
                height: gridHeight,
                slimStrength: 0,
                legLength: 1
            )
        }
        guard body.confidence >= configuration.minimumBodyConfidence,
              !analysis.warnings.contains(.lowConfidence)
        else {
            return .skipped(
                .lowConfidence,
                warnings: [.lowConfidence],
                width: gridWidth,
                height: gridHeight,
                slimStrength: 0,
                legLength: 1
            )
        }
        guard requestedSlim > 0.000_001 || requestedLength > 1.000_001 else {
            return .skipped(
                .neutralParameters,
                warnings: [.neutralParameters],
                width: gridWidth,
                height: gridHeight,
                slimStrength: 0,
                legLength: 1
            )
        }

        let strengthScale = analysis.warnings.contains(.occlusion)
            ? configuration.occlusionScale
            : 1

        let left: LegsPoseLeg
        let right: LegsPoseLeg
        switch makePose(body: body, imageSize: analysis.imageSize, mask: analysis.personMask) {
        case let .ready(poseLeft, poseRight):
            left = poseLeft
            right = poseRight
        case let .skipped(reason, warning):
            return .skipped(
                reason,
                warnings: [warning],
                width: gridWidth,
                height: gridHeight,
                slimStrength: requestedSlim * strengthScale,
                legLength: min(
                    1 + (requestedLength - 1) * strengthScale,
                    configuration.maximumLengthening
                )
            )
        }

        var warnings: [LegsWarpWarning] = []
        if strengthScale < 1 {
            append(.occlusionReduced, to: &warnings)
        }

        let usableMask = usablePersonMask(analysis.personMask, imageSize: analysis.imageSize)
        if usableMask == nil {
            append(.noPersonMask, to: &warnings)
        }

        let averageHipY = (left.hip.y + right.hip.y) / 2
        let anchorAnkleY = min(left.ankle.y, right.ankle.y)
        let anchorLegLength = max(anchorAnkleY - averageHipY, 1e-9)
        var effectiveLength = min(
            1 + (requestedLength - 1) * strengthScale,
            configuration.maximumLengthening
        )
        let requestedShift = max(0, (effectiveLength - 1) * anchorLegLength)
        if requestedShift > configuration.maximumVerticalDisplacement {
            effectiveLength = 1
                + configuration.maximumVerticalDisplacement / anchorLegLength
            append(.strengthLimited, to: &warnings)
        }
        if effectiveLength <= 1.000_001 {
            effectiveLength = 1
        }

        var effectiveSlim = LegsMath.clamp(requestedSlim * strengthScale, 0, 1)
        let largestHalfWidth = [left, right]
            .flatMap { $0.widthStations }
            .max() ?? configuration.minimumHalfWidth
        let requestedLateral = effectiveSlim * configuration.lateralReduction * largestHalfWidth
        if requestedLateral > configuration.maximumLateralDisplacement {
            append(.strengthLimited, to: &warnings)
        }

        guard effectiveSlim > 0.000_001 || effectiveLength > 1.000_001 else {
            append(.neutralParameters, to: &warnings)
            return .skipped(
                .neutralParameters,
                warnings: warnings,
                width: gridWidth,
                height: gridHeight,
                slimStrength: 0,
                legLength: 1
            )
        }
        if effectiveSlim <= 0.000_001 {
            effectiveSlim = 0
        }

        let faces = analysis.faces
            .map { $0.boundingBox.clamped() }
            .filter { $0.width > 0 && $0.height > 0 }
        let context = LegsPlanContext(
            configuration: configuration,
            legs: [left, right],
            slimStrength: effectiveSlim,
            legLengthScale: effectiveLength,
            faces: faces,
            mask: usableMask
        )

        var offsets = [SIMD2<Float>](
            repeating: SIMD2<Float>(0, 0),
            count: gridWidth * gridHeight
        )
        var peakDisplacement: Float = 0
        var deformedVertexCount = 0
        var didClampToLimit = false
        let contributionLimit = Float(configuration.maximumContribution)
        let widthDenominator = Double(max(gridWidth - 1, 1))
        let heightDenominator = Double(max(gridHeight - 1, 1))

        for y in 0 ..< gridHeight {
            if y % 8 == 0 {
                try Task.checkCancellation()
            }
            let normalizedY = Double(y) / heightDenominator
            let rowOffset = y * gridWidth
            for x in 0 ..< gridWidth {
                let normalizedX = Double(x) / widthDenominator
                let edgeWeight = context.frameEdgeWeight(x: normalizedX)
                let lateral = context.slimOffsetX(x: normalizedX, y: normalizedY)
                let vertical = context.verticalOffsetMagnitude(
                    x: normalizedX,
                    y: normalizedY
                )
                var value = SIMD2<Float>(
                    Float(lateral * edgeWeight),
                    Float(-vertical * edgeWeight)
                )
                if !value.x.isFinite || !value.y.isFinite {
                    value = .zero
                }

                let magnitude = (value.x * value.x + value.y * value.y).squareRoot()
                if contributionLimit <= 0 {
                    value = .zero
                    didClampToLimit = true
                } else if magnitude > contributionLimit {
                    value = value * (contributionLimit / magnitude)
                    didClampToLimit = true
                }

                offsets[rowOffset + x] = value
                let finalMagnitude = (value.x * value.x + value.y * value.y).squareRoot()
                if finalMagnitude > 0.000_001 {
                    deformedVertexCount += 1
                    peakDisplacement = max(peakDisplacement, finalMagnitude)
                }
            }
        }

        if deformedVertexCount == 0 {
            append(.noUsableRegion, to: &warnings)
            return .skipped(
                .noUsableRegion,
                warnings: warnings,
                width: gridWidth,
                height: gridHeight,
                slimStrength: effectiveSlim,
                legLength: effectiveLength
            )
        }

        return LegsWarpPlan(
            width: gridWidth,
            height: gridHeight,
            offsets: offsets,
            warnings: warnings,
            skipReason: nil,
            effectiveSlimStrength: effectiveSlim,
            effectiveLegLength: effectiveLength,
            peakDisplacement: peakDisplacement,
            deformedVertexCount: deformedVertexCount,
            didClampToLimit: didClampToLimit
        )
    }

    // MARK: - Pose extraction and validation

    private enum LegsPoseResult {
        case ready(left: LegsPoseLeg, right: LegsPoseLeg)
        case skipped(reason: LegsWarpSkipReason, warning: LegsWarpWarning)
    }

    private func makePose(
        body: BodyObservation,
        imageSize: PixelSize,
        mask: MaskBuffer?
    ) -> LegsPoseResult {
        let required: [BodyJointKind] = [
            .leftHip, .leftKnee, .leftAnkle,
            .rightHip, .rightKnee, .rightAnkle
        ]
        var points: [BodyJointKind: SIMD2<Double>] = [:]
        for kind in required {
            guard let point = body.point(for: kind),
                  point.x.isFinite,
                  point.y.isFinite,
                  (-0.02 ... 1.02).contains(point.x),
                  (-0.02 ... 1.02).contains(point.y)
            else {
                return .skipped(reason: .incompletePose, warning: .incompletePose)
            }
            points[kind] = SIMD2<Double>(
                LegsMath.clamp(point.x, 0, 1),
                LegsMath.clamp(point.y, 0, 1)
            )
        }

        guard let leftHip = points[.leftHip],
              let leftKnee = points[.leftKnee],
              let leftAnkle = points[.leftAnkle],
              let rightHip = points[.rightHip],
              let rightKnee = points[.rightKnee],
              let rightAnkle = points[.rightAnkle]
        else {
            return .skipped(reason: .incompletePose, warning: .incompletePose)
        }

        var left = LegsPoseLeg(
            hip: leftHip,
            knee: leftKnee,
            ankle: leftAnkle,
            widthStations: []
        )
        var right = LegsPoseLeg(
            hip: rightHip,
            knee: rightKnee,
            ankle: rightAnkle,
            widthStations: []
        )
        if left.hip.x > right.hip.x {
            swap(&left, &right)
        }
        guard right.hip.x - left.hip.x >= configuration.minimumCentreSeparation else {
            return .skipped(reason: .degeneratePose, warning: .degeneratePose)
        }
        guard abs(left.hip.y - right.hip.y) <= configuration.maximumHipAsymmetry,
              abs(left.ankle.y - right.ankle.y) <= configuration.maximumAnkleAsymmetry
        else {
            return .skipped(reason: .degeneratePose, warning: .degeneratePose)
        }

        for leg in [left, right] {
            guard leg.length >= configuration.minimumLegLength,
                  leg.length <= configuration.maximumLegLength
            else {
                return .skipped(reason: .degeneratePose, warning: .degeneratePose)
            }
            guard leg.knee.y > leg.hip.y + 0.02,
                  leg.ankle.y > leg.knee.y + 0.02
            else {
                return .skipped(reason: .degeneratePose, warning: .degeneratePose)
            }
            guard leg.ankle.y <= 1 - configuration.minimumAnkleMargin,
                  leg.ankle.x >= configuration.minimumAnkleMargin,
                  leg.ankle.x <= 1 - configuration.minimumAnkleMargin,
                  leg.hip.x >= 0,
                  leg.hip.x <= 1
            else {
                return .skipped(
                    reason: .feetOutsideFrame,
                    warning: .feetOutsideFrame
                )
            }
        }

        let top = max(left.hip.y, right.hip.y)
        let bottom = min(left.ankle.y, right.ankle.y)
        guard bottom - top >= 0.10 else {
            return .skipped(reason: .degeneratePose, warning: .degeneratePose)
        }
        for index in 0 ... 4 {
            let y = LegsMath.lerp(top, bottom, Double(index) / 4)
            guard let leftCentre = left.centreX(atY: y),
                  let rightCentre = right.centreX(atY: y),
                  rightCentre - leftCentre >= configuration.minimumCentreSeparation
            else {
                return .skipped(reason: .degeneratePose, warning: .degeneratePose)
            }
        }

        let fallback = LegsMath.clamp(
            (right.hip.x - left.hip.x) * configuration.fallbackWidthFraction,
            configuration.minimumHalfWidth,
            configuration.maximumHalfWidth
        )
        let usableMask = usablePersonMask(mask, imageSize: imageSize)
        left.widthStations = LegsWidthEstimator.stations(
            for: left,
            otherLeg: right,
            mask: usableMask,
            imageSize: imageSize,
            fallback: fallback,
            configuration: configuration
        )
        right.widthStations = LegsWidthEstimator.stations(
            for: right,
            otherLeg: left,
            mask: usableMask,
            imageSize: imageSize,
            fallback: fallback,
            configuration: configuration
        )
        return .ready(left: left, right: right)
    }

    private func usablePersonMask(
        _ mask: MaskBuffer?,
        imageSize: PixelSize
    ) -> MaskBuffer? {
        guard let mask,
              mask.width == imageSize.width,
              mask.height == imageSize.height
        else {
            return nil
        }
        return mask
    }

    private func sanitizedSlim(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return LegsMath.clamp(value, 0, 1)
    }

    private func sanitizedLength(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return LegsMath.clamp(value, 1, configuration.maximumLengthening)
    }

    private func append(
        _ warning: LegsWarpWarning,
        to warnings: inout [LegsWarpWarning]
    ) {
        if !warnings.contains(warning) {
            warnings.append(warning)
        }
    }
}

/// Geometry context for one plan; all methods are pure reads.
private struct LegsPlanContext {
    let configuration: LegsWarpConfiguration
    let legs: [LegsPoseLeg]
    let slimStrength: Double
    let legLengthScale: Double
    let faces: [NormalizedRect]
    let mask: MaskBuffer?

    let hipY: Double
    let ankleY: Double
    let legLength: Double
    let maximumShift: Double
    let gamma: Double
    let averageShinLength: Double
    let hipSpan: (left: Double, right: Double)

    init(
        configuration: LegsWarpConfiguration,
        legs: [LegsPoseLeg],
        slimStrength: Double,
        legLengthScale: Double,
        faces: [NormalizedRect],
        mask: MaskBuffer?
    ) {
        self.configuration = configuration
        self.legs = legs
        self.slimStrength = slimStrength
        self.legLengthScale = legLengthScale
        self.faces = faces
        self.mask = mask

        let count = Double(max(legs.count, 1))
        hipY = legs.map(\.hip.y).reduce(0, +) / count
        // Use the higher of the two ankles as the fixed anchor. Both feet then
        // sit at or below the anchor, so neither shoe is pulled upward when the
        // pose is slightly asymmetric.
        ankleY = legs.map(\.ankle.y).min() ?? hipY
        legLength = max(ankleY - hipY, 1e-9)
        maximumShift = max(0, (legLengthScale - 1) * legLength)
        if legLengthScale > 1.000_001 {
            gamma = configuration.nonlinearity
                * (1 - 1 / legLengthScale) / legLengthScale
        } else {
            gamma = 0
        }
        averageShinLength = legs.map(\.shinLength).reduce(0, +) / count
        hipSpan = (
            left: legs.map { $0.hip.x - $0.halfWidth(atY: $0.hip.y) }.min() ?? 0,
            right: legs.map { $0.hip.x + $0.halfWidth(atY: $0.hip.y) }.max() ?? 1
        )
    }

    /// Inward lateral displacement at one vertex.
    func slimOffsetX(x: Double, y: Double) -> Double {
        guard slimStrength > 0 else { return 0 }
        var result = 0.0
        for leg in legs {
            guard let centre = leg.centreX(atY: y) else { continue }
            let halfWidth = leg.effectiveHalfWidth(
                atY: y,
                configuration: configuration
            )
            guard halfWidth > 0 else { continue }

            let topRamp = max(
                0.02,
                min(0.06, configuration.hipRampFraction * leg.length)
            )
            let topWeight = LegsMath.smoothstep((y - leg.hip.y) / topRamp)
            guard topWeight > 0 else { continue }

            let footGuard = max(
                0.001,
                min(configuration.footGuardHeight, 0.20 * leg.shinLength)
            )
            let bottomRamp = max(
                0.02,
                min(0.08, configuration.ankleRampFraction * leg.length)
            )
            let bottomWeight = LegsMath.smoothstep(
                (leg.ankle.y - footGuard - y) / bottomRamp
            )
            guard bottomWeight > 0 else { continue }

            var weight = topWeight * bottomWeight
            if let mask {
                weight *= maskValue(mask, x: x, y: y)
            }
            guard weight > 0 else { continue }

            let normalizedDistance = abs(x - centre) / halfWidth
            let bell = LegsMath.lateralBell(
                normalizedDistance,
                feather: configuration.lateralFeather
            )
            guard bell > 0 else { continue }

            let amplitude = slimStrength * min(
                configuration.lateralReduction * halfWidth,
                configuration.maximumLateralDisplacement
            )
            result += (x >= centre ? -1.0 : 1.0) * amplitude * bell * weight
        }
        return result
    }

    /// Upward content displacement magnitude at one vertex.
    func verticalOffsetMagnitude(x: Double, y: Double) -> Double {
        guard legLengthScale > 1.000_001 else { return 0 }
        let shift = verticalShift(atY: y)
        guard shift > 0 else { return 0 }

        var weight = horizontalWeight(x: x, y: y)
        guard weight > 0 else { return 0 }
        weight *= faceWeight(x: x, y: y)
        guard weight > 0 else { return 0 }
        if let mask {
            weight *= maskValue(mask, x: x, y: y)
        }
        return shift * weight
    }

    /// Vertical offset magnitude before the horizontal/face/mask gates.
    private func verticalShift(atY y: Double) -> Double {
        guard legLengthScale > 1.000_001, legLength > 1e-9 else { return 0 }
        guard y < ankleY else { return 0 }

        let footGuard = max(
            0.001,
            min(configuration.footGuardHeight, 0.20 * averageShinLength)
        )
        let footWeight = LegsMath.smoothstep((ankleY - y) / footGuard)
        guard footWeight > 0 else { return 0 }

        let q = (ankleY - y) / legLength
        let scale = legLengthScale
        let base: Double
        if q <= scale {
            base = legLength * (
                q - (q / scale + gamma * q * (scale - q))
            )
        } else {
            let blend = max(configuration.torsoBlendHeight, 0.03)
            let t = (q - scale) * legLength / blend
            guard t < 1 else { return 0 }
            base = maximumShift * (2 * t * t * t - 3 * t * t + 1)
        }
        guard base.isFinite, base > 0 else { return 0 }
        return min(base, configuration.maximumVerticalDisplacement) * footWeight
    }

    /// Union of the two leg silhouettes; above the hip the hip span is used so
    /// the waist blends as one region.
    private func horizontalSpan(atY y: Double) -> (left: Double, right: Double) {
        guard y > hipY, y < ankleY else {
            return hipSpan
        }
        var left = Double.infinity
        var right = -Double.infinity
        for leg in legs {
            guard let centre = leg.centreX(atY: y) else { continue }
            let halfWidth = leg.effectiveHalfWidth(
                atY: y,
                configuration: configuration
            )
            left = min(left, centre - halfWidth)
            right = max(right, centre + halfWidth)
        }
        guard left.isFinite, right.isFinite, left < right else {
            return hipSpan
        }
        return (left, right)
    }

    private func horizontalWeight(x: Double, y: Double) -> Double {
        let span = horizontalSpan(atY: y)
        if x >= span.left, x <= span.right {
            return 1
        }
        let distance = x < span.left ? span.left - x : x - span.right
        guard distance < configuration.edgeMargin else { return 0 }
        return LegsMath.smoothstep(1 - distance / configuration.edgeMargin)
    }

    /// Hard-zero guard over every detected face, with a short falloff.
    private func faceWeight(x: Double, y: Double) -> Double {
        guard !faces.isEmpty else { return 1 }
        var weight = 1.0
        let clearance = max(configuration.faceClearance, 1e-6)
        let point = SIMD2<Double>(x, y)
        for face in faces {
            let distance = LegsMath.distance(from: point, to: face)
            guard distance > 0 else { return 0 }
            weight = min(
                weight,
                LegsMath.smoothstep(distance / clearance)
            )
        }
        return weight
    }

    /// Zero at the left/right frame border, one `edgeMargin` inside.
    func frameEdgeWeight(x: Double) -> Double {
        let distance = min(max(x, 0), max(1 - x, 0))
        return LegsMath.smoothstep(
            distance / max(configuration.edgeMargin, 1e-6)
        )
    }

    private func maskValue(_ mask: MaskBuffer, x: Double, y: Double) -> Double {
        let pixelX = min(
            max(Int(x * Double(mask.width)), 0),
            mask.width - 1
        )
        let pixelY = min(
            max(Int(y * Double(mask.height)), 0),
            mask.height - 1
        )
        guard let value = mask.value(x: pixelX, y: pixelY) else {
            return 1
        }
        return Double(value) / 255
    }
}
