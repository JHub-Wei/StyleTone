import Foundation
import StyleToneCore

enum BodyArmStatus {
    case available(BodyArmCapsule)
    case missingJoints
    case degenerate
}

enum BodyTorsoStatus {
    case available(BodyTorsoFrame)
    case missingJoints
    case degenerate
}

struct BodyArmSample {
    let distance: Double
    let along: Double
    let closest: SIMD2<Double>
}

/// A shoulder-elbow-wrist polyline with the influence envelope used by the arm
/// contribution.
struct BodyArmCapsule {
    let shoulder: SIMD2<Double>
    let elbow: SIMD2<Double>
    let wrist: SIMD2<Double>
    let upperLength: Double
    let lowerLength: Double
    let totalLength: Double
    let radius: Double
    let supportRadius: Double
    let shoulderGuardLength: Double
    let handGuardLength: Double

    init?(
        shoulder: SIMD2<Double>,
        elbow: SIMD2<Double>,
        wrist: SIMD2<Double>,
        shoulderSpan: Double,
        configuration: BodyWarpConfiguration
    ) {
        let upper = BodyWarpMath.length(elbow - shoulder)
        let lower = BodyWarpMath.length(wrist - elbow)
        let total = upper + lower
        let chord = BodyWarpMath.length(wrist - shoulder)
        let minimumSegment = max(0.012, shoulderSpan * 0.04)
        guard upper >= minimumSegment,
              lower >= minimumSegment,
              total >= chord * 0.95,
              chord > 0
        else {
            return nil
        }

        let estimatedRadius = shoulderSpan * configuration.armRadiusToShoulderSpan
        let clampedRadius = BodyWarpMath.clamp(
            estimatedRadius,
            to: configuration.minimumArmRadius ... configuration.maximumArmRadius
        )
        self.shoulder = shoulder
        self.elbow = elbow
        self.wrist = wrist
        upperLength = upper
        lowerLength = lower
        totalLength = total
        radius = clampedRadius
        supportRadius = clampedRadius * configuration.armSupportToRadius
        shoulderGuardLength = upper * configuration.shoulderGuardFraction
        handGuardLength = lower * configuration.handGuardFraction
    }

    /// Nearest point on the two-segment polyline.
    func nearest(to point: SIMD2<Double>) -> BodyArmSample {
        var best = BodyArmSample(
            distance: .infinity,
            along: 0,
            closest: shoulder
        )
        for (start, end, base) in [
            (shoulder, elbow, 0.0),
            (elbow, wrist, upperLength)
        ] {
            let segment = end - start
            let segmentLengthSquared = BodyWarpMath.dot(segment, segment)
            guard segmentLengthSquared > 1e-12 else {
                continue
            }
            let projection = BodyWarpMath.dot(point - start, segment) / segmentLengthSquared
            let t = BodyWarpMath.clamp(projection, to: 0 ... 1)
            let closest = start + segment * t
            let distance = BodyWarpMath.length(point - closest)
            if distance < best.distance {
                best = BodyArmSample(
                    distance: distance,
                    along: base + t * segmentLengthSquared.squareRoot(),
                    closest: closest
                )
            }
        }
        return best
    }

    /// Point at a fraction of total polyline length.
    func point(atFraction fraction: Double) -> SIMD2<Double> {
        let clampedFraction = BodyWarpMath.clamp(fraction, to: 0 ... 1)
        let target = clampedFraction * totalLength
        if target <= upperLength {
            let t = upperLength > 0 ? target / upperLength : 0
            return shoulder + (elbow - shoulder) * t
        }
        let t = lowerLength > 0 ? (target - upperLength) / lowerLength : 1
        return elbow + (wrist - elbow) * t
    }

    func coveragePoints(metricSpace: BodyWarpMetricSpace) -> [NormalizedPoint] {
        [0.18, 0.34, 0.50, 0.65, 0.80, 0.88].map {
            metricSpace.normalized(point(atFraction: $0))
        }
    }
}

/// Shoulder-centre to hip-centre frame used by the waist band and to keep arm
/// influence out of the torso.
struct BodyTorsoFrame {
    let leftShoulder: SIMD2<Double>
    let rightShoulder: SIMD2<Double>
    let leftHip: SIMD2<Double>
    let rightHip: SIMD2<Double>
    let shoulderCenter: SIMD2<Double>
    let hipCenter: SIMD2<Double>
    let axis: SIMD2<Double>
    let normal: SIMD2<Double>
    let length: Double
    let shoulderSpan: Double
    let hipSpan: Double

    init?(
        leftShoulder: SIMD2<Double>,
        rightShoulder: SIMD2<Double>,
        leftHip: SIMD2<Double>,
        rightHip: SIMD2<Double>,
        minimumLength: Double
    ) {
        let shoulderCenter = (leftShoulder + rightShoulder) * 0.5
        let hipCenter = (leftHip + rightHip) * 0.5
        let torsoVector = hipCenter - shoulderCenter
        let torsoLength = BodyWarpMath.length(torsoVector)
        let shoulderSpan = BodyWarpMath.length(rightShoulder - leftShoulder)
        let hipSpan = BodyWarpMath.length(rightHip - leftHip)
        guard torsoLength >= minimumLength, shoulderSpan > 0.02 else {
            return nil
        }

        let axis = torsoVector / torsoLength
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.leftHip = leftHip
        self.rightHip = rightHip
        self.shoulderCenter = shoulderCenter
        self.hipCenter = hipCenter
        self.axis = axis
        normal = SIMD2<Double>(-axis.y, axis.x)
        length = torsoLength
        self.shoulderSpan = shoulderSpan
        self.hipSpan = hipSpan
    }

    func centerPoint(at t: Double) -> SIMD2<Double> {
        shoulderCenter + (hipCenter - shoulderCenter) * t
    }

    /// Projection of an image point into torso coordinates: `t` runs 0 at the
    /// shoulder centre to 1 at the hip centre; `lateral` is signed distance
    /// along the shoulder line.
    func projection(of point: SIMD2<Double>) -> (t: Double, lateral: Double) {
        let relative = point - shoulderCenter
        return (
            t: BodyWarpMath.dot(relative, axis) / length,
            lateral: BodyWarpMath.dot(relative, normal)
        )
    }

    /// Expected torso half-width at a given axial position. It protects the
    /// torso from arm pinch influence; it is not a body measurement.
    func protectionHalfWidth(at t: Double) -> Double {
        let clamped = BodyWarpMath.clamp(t, to: 0 ... 1)
        let shoulderHalfWidth = shoulderSpan * 0.5
        let hipHalfWidth = hipSpan > 0.01 ? hipSpan * 0.5 : shoulderHalfWidth * 0.85
        let interpolated = shoulderHalfWidth + (hipHalfWidth - shoulderHalfWidth) * clamped
        return interpolated * 0.90
    }

    func coveragePoints(metricSpace: BodyWarpMetricSpace) -> [NormalizedPoint] {
        (0 ..< 7).map { index in
            let t = 0.18 + 0.72 * Double(index) / 6.0
            return metricSpace.normalized(centerPoint(at: t))
        }
    }
}

/// Pose-derived geometry for one primary body.
///
/// Only image-relative ratios and distances are used. Nothing here identifies a
/// person or converts pixels to real-world measurements.
struct BodyPoseGeometry {
    let shoulderSpan: Double
    let leftArm: BodyArmStatus
    let rightArm: BodyArmStatus
    let torso: BodyTorsoStatus

    init(
        joints: [BodyJointKind: NormalizedPoint],
        metricSpace: BodyWarpMetricSpace,
        configuration: BodyWarpConfiguration
    ) {
        let leftShoulder = Self.sanitized(joints[.leftShoulder])
        let rightShoulder = Self.sanitized(joints[.rightShoulder])
        let leftHip = Self.sanitized(joints[.leftHip])
        let rightHip = Self.sanitized(joints[.rightHip])

        let directShoulderSpan: Double?
        if let leftShoulder, let rightShoulder {
            let left = metricSpace.point(leftShoulder)
            let right = metricSpace.point(rightShoulder)
            directShoulderSpan = BodyWarpMath.length(right - left)
        } else {
            directShoulderSpan = nil
        }

        let fallbackHipSpan: Double?
        if let leftHip, let rightHip {
            let left = metricSpace.point(leftHip)
            let right = metricSpace.point(rightHip)
            fallbackHipSpan = BodyWarpMath.length(right - left) / 0.80
        } else {
            fallbackHipSpan = nil
        }

        var span = 0.26
        if let directShoulderSpan, directShoulderSpan > 0.03 {
            span = directShoulderSpan
        } else if let fallbackHipSpan, fallbackHipSpan > 0.03 {
            span = fallbackHipSpan
        }
        shoulderSpan = span

        leftArm = Self.makeArm(
            shoulder: leftShoulder,
            elbow: Self.sanitized(joints[.leftElbow]),
            wrist: Self.sanitized(joints[.leftWrist]),
            shoulderSpan: span,
            metricSpace: metricSpace,
            configuration: configuration
        )
        rightArm = Self.makeArm(
            shoulder: rightShoulder,
            elbow: Self.sanitized(joints[.rightElbow]),
            wrist: Self.sanitized(joints[.rightWrist]),
            shoulderSpan: span,
            metricSpace: metricSpace,
            configuration: configuration
        )

        if let leftShoulder, let rightShoulder, let leftHip, let rightHip {
            let frame = BodyTorsoFrame(
                leftShoulder: metricSpace.point(leftShoulder),
                rightShoulder: metricSpace.point(rightShoulder),
                leftHip: metricSpace.point(leftHip),
                rightHip: metricSpace.point(rightHip),
                minimumLength: configuration.minimumTorsoLength
            )
            if let frame {
                torso = .available(frame)
            } else {
                torso = .degenerate
            }
        } else {
            torso = .missingJoints
        }
    }

    private static func sanitized(_ point: NormalizedPoint?) -> NormalizedPoint? {
        guard let point,
              point.x.isFinite,
              point.y.isFinite,
              point.x >= -0.05,
              point.x <= 1.05,
              point.y >= -0.05,
              point.y <= 1.05
        else {
            return nil
        }
        return point.clamped()
    }

    private static func makeArm(
        shoulder: NormalizedPoint?,
        elbow: NormalizedPoint?,
        wrist: NormalizedPoint?,
        shoulderSpan: Double,
        metricSpace: BodyWarpMetricSpace,
        configuration: BodyWarpConfiguration
    ) -> BodyArmStatus {
        guard let shoulder, let elbow, let wrist else {
            return .missingJoints
        }
        guard let capsule = BodyArmCapsule(
            shoulder: metricSpace.point(shoulder),
            elbow: metricSpace.point(elbow),
            wrist: metricSpace.point(wrist),
            shoulderSpan: shoulderSpan,
            configuration: configuration
        ) else {
            return .degenerate
        }
        return .available(capsule)
    }
}
