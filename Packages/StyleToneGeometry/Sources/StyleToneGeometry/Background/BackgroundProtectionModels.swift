import Foundation
import StyleToneCore

/// Non-fatal issues found while planning background protection.
///
/// The frozen ``GeometryConstraint`` protocol has no warning return channel, so
/// the constraint itself cannot surface these to the engine. Callers that need
/// user feedback (the editor scene-warning strip, for example) call
/// ``BackgroundWarpConstraint/makePlan(field:analysis:)`` or
/// ``BackgroundWarpConstraint/assessRisk(field:analysis:protectionEnabled:)``
/// and read the plan's warnings. The constraint still applies the same plan.
///
/// Values deliberately contain no image path, file name or other PII. All
/// counts are per frame; there is no cross-frame identity.
public enum BackgroundProtectionWarning: Sendable, Equatable, Hashable {
    /// The analysis has no background edge mask (WP-05 skipped or failed the
    /// structure stage). Generic background damping still runs, but no lines or
    /// rectangles can be detected.
    case edgeMaskUnavailable

    /// The edge mask exists but contains no pixel above
    /// ``BackgroundProtectionConfiguration/minimumEdgeValue``.
    case edgeMaskEmpty

    /// The edge mask contains edges, but no long horizontal/vertical run formed
    /// a line and no rectangle was closed. Curved/diagonal edges still receive
    /// generic edge protection.
    case noStructureDetected

    /// The edge mask dimensions differ from `PortraitAnalysis.imageSize`.
    /// Normalized coordinates are still used, but the analysis is inconsistent.
    case maskSizeMismatch(expected: PixelSize, actual: PixelSize)

    /// The analysis has no person mask; face/body bounding boxes supplied the
    /// subject support instead.
    case subjectMaskUnavailable

    /// The person mask is present but covers less than
    /// ``BackgroundProtectionConfiguration/subjectMaskEmptyCoverage`` of the
    /// frame; face/body bounding boxes supplied the subject support instead.
    case subjectMaskEmpty

    /// Neither the person mask nor any face/body observation could define a
    /// subject region. The whole frame is treated as background.
    case subjectRegionUnavailable

    /// More lines were found than ``BackgroundProtectionConfiguration/maximumLineCount``;
    /// only the `kept` strongest/longest lines are protected.
    case lineDetectionLimited(detected: Int, kept: Int)

    /// More rectangles were found than
    /// ``BackgroundProtectionConfiguration/maximumRectangleCount``; only the
    /// `kept` largest/strongest rectangles are protected.
    case rectangleDetectionLimited(detected: Int, kept: Int)

    /// Background protection is switched off. This is informational and is
    /// only emitted by ``BackgroundWarpConstraint/assessRisk(field:analysis:protectionEnabled:)``.
    case protectionDisabled

    /// Background protection is switched off **and** the current field moves
    /// detected background structure enough to be visible.
    case protectionDisabledWithStructures(
        lineCount: Int,
        rectangleCount: Int,
        riskyVertexCount: Int
    )

    /// Protection ran, but some structure vertices still carry a visible
    /// residual displacement (for example because the subject-support gate
    /// intentionally keeps the region moving).
    case structureDisplacementResidual(maximumDisplacement: Float)
}

/// One detected straight structure line.
///
/// Coordinates are normalized image units with a top-left origin. For a
/// horizontal line, `position` is `y` and `start`/`end` are `x`; for a vertical
/// line, `position` is `x` and `start`/`end` are `y`.
public struct BackgroundStructureLine: Sendable, Equatable {
    /// Orientation of the detected line.
    public enum Orientation: String, Sendable, Equatable, CaseIterable {
        /// A line of constant `y` that runs along `x`.
        case horizontal
        /// A line of constant `x` that runs along `y`.
        case vertical
    }

    /// Detected orientation.
    public let orientation: Orientation
    /// Constant coordinate of the line (`y` for horizontal, `x` for vertical).
    public let position: Float
    /// Start of the detected extent along the line.
    public let start: Float
    /// End of the detected extent along the line.
    public let end: Float
    /// Detection strength in `0...1` (mean edge evidence of the run).
    public let strength: Float

    init(
        orientation: Orientation,
        position: Float,
        start: Float,
        end: Float,
        strength: Float
    ) {
        self.orientation = orientation
        self.position = position
        self.start = start
        self.end = end
        self.strength = strength
    }

    /// Length of the detected extent in normalized units.
    public var span: Float {
        max(0, end - start)
    }
}

/// One detected axis-aligned rectangle (door frame, floor tile, table top).
public struct BackgroundStructureRectangle: Sendable, Equatable {
    /// Rectangle in normalized image coordinates.
    public let rect: NormalizedRect
    /// Detection strength in `0...1` (the weakest of its four boundary lines).
    public let strength: Float

    init(rect: NormalizedRect, strength: Float) {
        self.rect = rect
        self.strength = strength
    }
}

/// PII-free measurements of one protection plan.
///
/// Retentions are ratios of summed displacement magnitudes:
/// `after / before`. A value of `1` means the region was not damped at all; `0`
/// means it was pinned.
public struct BackgroundProtectionMetrics: Sendable, Equatable {
    /// Number of mesh vertices in the plan.
    public let vertexCount: Int
    /// Number of detected straight lines.
    public let detectedLineCount: Int
    /// Number of detected rectangles.
    public let detectedRectangleCount: Int
    /// Fraction of vertices outside the subject support (`support < 0.5`).
    public let backgroundVertexFraction: Float
    /// Fraction of **background** vertices with structure protection `>= 0.5`.
    public let protectedBackgroundVertexFraction: Float
    /// Mean structure protection over background vertices, `0...1`.
    public let meanStructureProtection: Float
    /// Largest displacement magnitude before the constraint.
    public let maximumDisplacementBefore: Float
    /// Largest displacement magnitude after the constraint.
    public let maximumDisplacementAfter: Float
    /// Displacement ratio retained in the background. `1` when nothing moved.
    public let backgroundRetention: Float
    /// Displacement ratio retained inside the subject support (`support >= 0.9`).
    /// This is the "slimming effect is preserved" metric.
    public let subjectRetention: Float
    /// Largest displacement on a structure-core vertex (`protection >= 0.75`)
    /// before.
    public let maximumStructureDisplacementBefore: Float
    /// Largest displacement on a structure-core vertex after.
    public let maximumStructureDisplacementAfter: Float
    /// Largest along-line normal deviation before the constraint, normalized.
    public let maximumLineDeviationBefore: Float
    /// Largest along-line normal deviation after the constraint, normalized.
    public let maximumLineDeviationAfter: Float
    /// Structure vertices whose **source** displacement exceeds the risk
    /// threshold, measured on core vertices (`protection >= 0.75`).
    public let riskyVertexCount: Int
    /// Structure vertices whose **constrained** displacement exceeds the risk threshold.
    public let residualRiskyVertexCount: Int
    /// Number of vertices with a non-zero source displacement.
    public let movedVertexCount: Int

    init(
        vertexCount: Int,
        detectedLineCount: Int,
        detectedRectangleCount: Int,
        backgroundVertexFraction: Float,
        protectedBackgroundVertexFraction: Float,
        meanStructureProtection: Float,
        maximumDisplacementBefore: Float,
        maximumDisplacementAfter: Float,
        backgroundRetention: Float,
        subjectRetention: Float,
        maximumStructureDisplacementBefore: Float,
        maximumStructureDisplacementAfter: Float,
        maximumLineDeviationBefore: Float,
        maximumLineDeviationAfter: Float,
        riskyVertexCount: Int,
        residualRiskyVertexCount: Int,
        movedVertexCount: Int
    ) {
        self.vertexCount = vertexCount
        self.detectedLineCount = detectedLineCount
        self.detectedRectangleCount = detectedRectangleCount
        self.backgroundVertexFraction = backgroundVertexFraction
        self.protectedBackgroundVertexFraction = protectedBackgroundVertexFraction
        self.meanStructureProtection = meanStructureProtection
        self.maximumDisplacementBefore = maximumDisplacementBefore
        self.maximumDisplacementAfter = maximumDisplacementAfter
        self.backgroundRetention = backgroundRetention
        self.subjectRetention = subjectRetention
        self.maximumStructureDisplacementBefore = maximumStructureDisplacementBefore
        self.maximumStructureDisplacementAfter = maximumStructureDisplacementAfter
        self.maximumLineDeviationBefore = maximumLineDeviationBefore
        self.maximumLineDeviationAfter = maximumLineDeviationAfter
        self.riskyVertexCount = riskyVertexCount
        self.residualRiskyVertexCount = residualRiskyVertexCount
        self.movedVertexCount = movedVertexCount
    }

    /// Zero metrics for an empty/zero field or an aborted plan.
    static func empty(vertexCount: Int) -> BackgroundProtectionMetrics {
        BackgroundProtectionMetrics(
            vertexCount: vertexCount,
            detectedLineCount: 0,
            detectedRectangleCount: 0,
            backgroundVertexFraction: 0,
            protectedBackgroundVertexFraction: 0,
            meanStructureProtection: 0,
            maximumDisplacementBefore: 0,
            maximumDisplacementAfter: 0,
            backgroundRetention: 1,
            subjectRetention: 1,
            maximumStructureDisplacementBefore: 0,
            maximumStructureDisplacementAfter: 0,
            maximumLineDeviationBefore: 0,
            maximumLineDeviationAfter: 0,
            riskyVertexCount: 0,
            residualRiskyVertexCount: 0,
            movedVertexCount: 0
        )
    }
}

/// A complete background protection pass for one mesh density.
///
/// The plan is a pure value: it contains the source field, the constrained
/// field and the protection maps used to produce it. It can be inspected for
/// diagnostics, applied to a ``WarpField`` or discarded.
public struct BackgroundProtectionPlan: Sendable {
    /// Number of vertices per row.
    public let gridWidth: Int
    /// Number of vertex rows.
    public let gridHeight: Int
    /// Displacement before the constraint, row-major.
    public let sourceOffsets: [SIMD2<Float>]
    /// Displacement after the constraint, row-major. Same sign convention as
    /// ``WarpField`` (content displacement, positive moves right/down).
    public let constrainedOffsets: [SIMD2<Float>]
    /// Combined structure protection per vertex, `0...1`.
    public let protectionWeights: [Float]
    /// Subject support per vertex, `0...1`. `1` keeps the full displacement.
    public let subjectSupport: [Float]
    /// Detected straight lines, sorted horizontal-first then by position.
    public let lines: [BackgroundStructureLine]
    /// Detected rectangles, largest/strongest first.
    public let rectangles: [BackgroundStructureRectangle]
    /// Measurements of the plan.
    public let metrics: BackgroundProtectionMetrics
    /// Non-fatal planning issues. Empty when no warning was necessary.
    public let warnings: [BackgroundProtectionWarning]

    init(
        gridWidth: Int,
        gridHeight: Int,
        sourceOffsets: [SIMD2<Float>],
        constrainedOffsets: [SIMD2<Float>],
        protectionWeights: [Float],
        subjectSupport: [Float],
        lines: [BackgroundStructureLine],
        rectangles: [BackgroundStructureRectangle],
        metrics: BackgroundProtectionMetrics,
        warnings: [BackgroundProtectionWarning]
    ) {
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.sourceOffsets = sourceOffsets
        self.constrainedOffsets = constrainedOffsets
        self.protectionWeights = protectionWeights
        self.subjectSupport = subjectSupport
        self.lines = lines
        self.rectangles = rectangles
        self.metrics = metrics
        self.warnings = warnings
    }

    /// `true` when the source field had no displacement and the plan is a no-op.
    public var isEmpty: Bool {
        metrics.maximumDisplacementBefore == 0
    }

    /// Number of vertices in the plan.
    public var vertexCount: Int {
        gridWidth * gridHeight
    }

    /// Combined protection weight at one vertex, or `nil` when out of bounds.
    public func protectionWeight(x: Int, y: Int) -> Float? {
        guard x >= 0, y >= 0, x < gridWidth, y < gridHeight else { return nil }
        return protectionWeights[y * gridWidth + x]
    }

    /// Subject support at one vertex, or `nil` when out of bounds.
    public func support(x: Int, y: Int) -> Float? {
        guard x >= 0, y >= 0, x < gridWidth, y < gridHeight else { return nil }
        return subjectSupport[y * gridWidth + x]
    }

    /// Replaces the offsets of `field` with the constrained offsets.
    ///
    /// The field density must match the plan. The method validates before
    /// writing, so a mismatch leaves `field` untouched.
    ///
    /// - Throws: ``GeometryError/invalidGrid(width:height:)`` when the density
    ///   differs, or ``GeometryError/offsetCountMismatch(expected:actual:)``
    ///   when the arrays do not line up.
    public func applyingConstraint(to field: inout WarpField) throws {
        guard field.width == gridWidth, field.height == gridHeight else {
            throw GeometryError.invalidGrid(width: gridWidth, height: gridHeight)
        }
        guard field.offsets.count == constrainedOffsets.count else {
            throw GeometryError.offsetCountMismatch(
                expected: field.offsets.count,
                actual: constrainedOffsets.count
            )
        }
        field.offsets = constrainedOffsets
    }

    static func empty(
        gridWidth: Int,
        gridHeight: Int,
        warnings: [BackgroundProtectionWarning] = []
    ) -> BackgroundProtectionPlan {
        let count = gridWidth * gridHeight
        return BackgroundProtectionPlan(
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            sourceOffsets: [SIMD2<Float>](repeating: .zero, count: count),
            constrainedOffsets: [SIMD2<Float>](repeating: .zero, count: count),
            protectionWeights: [Float](repeating: 0, count: count),
            subjectSupport: [Float](repeating: 0, count: count),
            lines: [],
            rectangles: [],
            metrics: .empty(vertexCount: count),
            warnings: warnings
        )
    }
}

/// Risk assessment for the background-protection switch.
///
/// The editor uses this when the user turns background protection off: if the
/// current warp field would visibly move detected structure, the result is at
/// least ``BackgroundProtectionRisk/Level/moderate`` and the warnings explain
/// why.
public struct BackgroundProtectionRisk: Sendable, Equatable {
    /// Coarse risk level for a warning banner.
    public enum Level: String, Sendable, Equatable, CaseIterable {
        /// No structure is visibly displaced.
        case low
        /// Structure moves, but below the "obvious distortion" scale.
        case moderate
        /// Several structure vertices or a large displacement — clearly visible.
        case high
    }

    /// Risk level of the assessed configuration.
    public let level: Level
    /// Structure vertices with displacement above the risk threshold.
    public let riskyVertexCount: Int
    /// Vertices that carry any detected structure protection (`>= 0.5`).
    public let structureVertexCount: Int
    /// Largest displacement on a structure vertex.
    public let maximumStructureDisplacement: Float
    /// Detection/plan warnings plus the switch warnings.
    public let warnings: [BackgroundProtectionWarning]
    /// Full metrics for the assessed field (before and after the plan).
    public let metrics: BackgroundProtectionMetrics

    init(
        level: Level,
        riskyVertexCount: Int,
        structureVertexCount: Int,
        maximumStructureDisplacement: Float,
        warnings: [BackgroundProtectionWarning],
        metrics: BackgroundProtectionMetrics
    ) {
        self.level = level
        self.riskyVertexCount = riskyVertexCount
        self.structureVertexCount = structureVertexCount
        self.maximumStructureDisplacement = maximumStructureDisplacement
        self.warnings = warnings
        self.metrics = metrics
    }
}
