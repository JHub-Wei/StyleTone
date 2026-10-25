import Foundation
import StyleToneCore

/// Non-fatal issues found while planning the face slim/jaw contribution.
///
/// The frozen ``GeometryPass`` protocol has no warning return value, so the
/// pass itself cannot surface these to the engine. Callers that need user
/// feedback (the editor scene-warning strip, for example) call
/// ``FaceWarpContributor/plan(for:parameters:gridWidth:gridHeight:)`` and read
/// ``FaceWarpPlan/warnings``. The pass still applies the same plan.
///
/// Values deliberately contain no image path, face identifier or other PII;
/// `faceIndex` is only the position in `PortraitAnalysis.faces` for this frame.
public enum FaceWarpWarning: Sendable, Equatable, Hashable {
    /// The analysis contains no face. The pass is a safe no-op.
    case noFace

    /// Faces were detected but none was usable (filtered out or missing
    /// landmarks). The pass is a safe no-op.
    case noUsableFace

    /// More than one face was detected. Every usable face is processed, in
    /// descending bounding-box area order.
    case multipleFaces(count: Int)

    /// More usable faces were detected than ``FaceWarpConfiguration/maximumFaceCount``;
    /// only the largest `processed` faces contributed.
    case faceCountLimited(detected: Int, processed: Int)

    /// A face was skipped because its detection confidence was too low.
    case lowConfidence(faceIndex: Int, confidence: Float)

    /// A face was skipped because its bounding box covers too little of the image.
    case faceTooSmall(faceIndex: Int, areaFraction: Float)

    /// A face was skipped because the landmarks needed for a safe contribution
    /// (both eye centres plus at least one of nose/lips) are missing.
    case insufficientLandmarks(faceIndex: Int)

    /// The face contour is missing; the planner fell back to the face bounding
    /// box for width/chin metrics. The contribution is still applied.
    case missingFaceContour(faceIndex: Int)

    /// The bounding box or derived geometry is invalid (non-finite, zero-sized
    /// or inverted). The face was skipped.
    case degenerateFace(faceIndex: Int)
}

/// PII-free debugging metrics for one face that contributed to a plan.
///
/// Values are normalized image coordinates (top-left origin, y down). They are
/// exposed so tests and diagnostics can reason about the field without
/// re-deriving landmarks.
public struct FaceWarpFaceMetrics: Sendable, Equatable {
    /// Index of the face in `PortraitAnalysis.faces`.
    public let faceIndex: Int
    /// Detection confidence reported by the analyzer.
    public let confidence: Float
    /// Bounding-box area as a fraction of the image area.
    public let areaFraction: Float
    /// Symmetry axis used by the displacement profile.
    public let centerX: Float
    /// Estimated eye line; displacement starts below this line.
    public let eyeY: Float
    /// Chin line used as the lower end of the jaw band.
    public let chinY: Float
    /// Half of the face width used to normalize the profile.
    public let halfWidth: Float
    /// `true` when no usable face contour was available and the bounding box
    /// supplied the width/chin metrics.
    public let isContourEstimated: Bool
    /// Largest displacement this face contributed to the plan, in normalized
    /// image units, before overlapping-face normalization.
    public let peakDisplacement: Float

    init(
        faceIndex: Int,
        confidence: Float,
        areaFraction: Float,
        centerX: Float,
        eyeY: Float,
        chinY: Float,
        halfWidth: Float,
        isContourEstimated: Bool,
        peakDisplacement: Float
    ) {
        self.faceIndex = faceIndex
        self.confidence = confidence
        self.areaFraction = areaFraction
        self.centerX = centerX
        self.eyeY = eyeY
        self.chinY = chinY
        self.halfWidth = halfWidth
        self.isContourEstimated = isContourEstimated
        self.peakDisplacement = peakDisplacement
    }
}

/// Displacement contribution produced by the face pass for one mesh density.
///
/// The plan is a pure value: it can be inspected, tested, applied to a
/// ``WarpField`` or discarded without touching the engine. The current
/// ``GeometryPass`` API applies it directly; diagnostics-oriented callers keep
/// the plan to read ``warnings`` and ``faces``.
public struct FaceWarpPlan: Sendable {
    /// Number of vertices per row in ``offsets``.
    public let gridWidth: Int
    /// Number of vertex rows in ``offsets``.
    public let gridHeight: Int
    /// Row-major offsets, `gridWidth * gridHeight` entries, normalized image
    /// units. Positive `x` moves content right, positive `y` moves it down.
    public let offsets: [SIMD2<Float>]
    /// Metrics for every face that contributed, sorted by descending area.
    public let faces: [FaceWarpFaceMetrics]
    /// Non-fatal planning issues. Empty when no warning was necessary.
    public let warnings: [FaceWarpWarning]
    /// Largest offset magnitude in the plan, in normalized image units.
    public let maximumDisplacement: Float
    /// Number of vertices with a non-zero offset.
    public let deformedVertexCount: Int

    init(
        gridWidth: Int,
        gridHeight: Int,
        offsets: [SIMD2<Float>],
        faces: [FaceWarpFaceMetrics],
        warnings: [FaceWarpWarning],
        maximumDisplacement: Float,
        deformedVertexCount: Int
    ) {
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.offsets = offsets
        self.faces = faces
        self.warnings = warnings
        self.maximumDisplacement = maximumDisplacement
        self.deformedVertexCount = deformedVertexCount
    }

    /// `true` when the plan contains no displacement.
    public var isEmpty: Bool {
        maximumDisplacement == 0
    }

    /// Offset of one vertex, or `nil` when out of bounds.
    public func offset(x: Int, y: Int) -> SIMD2<Float>? {
        guard x >= 0, y >= 0, x < gridWidth, y < gridHeight else {
            return nil
        }
        return offsets[y * gridWidth + x]
    }

    /// Adds this plan's offsets to an existing field.
    ///
    /// The field must use the same mesh density as the plan. The method
    /// validates the density first, so a mismatch leaves `field` untouched.
    ///
    /// - Throws: ``GeometryError/invalidGrid(width:height:)`` when the field
    ///   density differs, or ``GeometryError/offsetCountMismatch(expected:actual:)``
    ///   when the arrays do not line up.
    public func applying(to field: inout WarpField) throws {
        guard field.width == gridWidth, field.height == gridHeight else {
            throw GeometryError.invalidGrid(width: gridWidth, height: gridHeight)
        }
        guard field.offsets.count == offsets.count else {
            throw GeometryError.offsetCountMismatch(
                expected: field.offsets.count,
                actual: offsets.count
            )
        }
        for index in offsets.indices {
            field.offsets[index] += offsets[index]
        }
    }
}
