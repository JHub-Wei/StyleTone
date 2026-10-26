import Foundation
import StyleToneCore

/// WP-15 background protection as a post-pass ``GeometryConstraint``.
///
/// The constraint is registered as the engine's `backgroundConstraint`, so
/// `GeometryRenderingEngine` runs it **after** the face, body and legs passes
/// and **before** boundary pinning/feathering (`contracts.md` §4.1). The engine
/// only calls it when `GeometryParameters.backgroundProtection` is `true`; the
/// switch itself stays in WP-06.
///
/// ## What it does
///
/// 1. Reads `PortraitAnalysis.backgroundEdgeMask` (WP-05) and detects long
///    horizontal/vertical lines plus axis-aligned rectangles (door frames,
///    floor tiles, table edges, window mouldings).
/// 2. Builds a subject support map from the person mask, falling back to
///    face/body bounding boxes when segmentation is missing or empty.
/// 3. Dampens displacement on background edges, lines and rectangle interiors,
///    with a soft background-only baseline. The subject region keeps 100 % of
///    its displacement, so face/body/leg slimming is not weakened.
/// 4. Forces every detected line core to a single rigid displacement, so a
///    straight line can translate slightly but cannot bend.
///
/// ## Warnings
///
/// ``GeometryConstraint`` has no warning return channel. Call
/// ``makePlan(field:analysis:)`` for a plan with
/// ``BackgroundProtectionPlan/warnings`` and metrics, or
/// ``assessRisk(field:analysis:protectionEnabled:)`` when the user toggles
/// background protection off and the editor needs to show a warning.
///
/// The constraint never throws for missing masks, an empty person mask or
/// undetectable structure: it degrades to generic background damping. It only
/// throws for a structurally invalid field or cancellation.
///
/// ## Example
///
/// ```swift
/// let engine = GeometryRenderingEngine(
///     passes: [
///         GeometryPassEntry(phase: .face, pass: FaceWarpContributor()),
///         GeometryPassEntry(phase: .body, pass: BodyWarpContributor()),
///         GeometryPassEntry(phase: .legs, pass: LegsWarpContributor())
///     ],
///     backgroundConstraint: BackgroundWarpConstraint(),
///     configuration: .preview
/// )
///
/// // Toggle-off warning for the editor:
/// let field = try engine.makeField(analysis: analysis, geometry: parameters)
/// let risk = try BackgroundWarpConstraint().assessRisk(
///     field: field,
///     analysis: analysis,
///     protectionEnabled: false
/// )
/// if risk.level != .low { showBackgroundWarning(risk.warnings) }
/// ```
public struct BackgroundWarpConstraint: GeometryConstraint {
    /// Stable constraint identifier used by diagnostics and ordering tests.
    public static let constraintIdentifier = "background.structure-protection"

    /// Stable identifier used by the pipeline and tests.
    public let identifier: String

    /// Detection thresholds, retention values and risk limits.
    public let configuration: BackgroundProtectionConfiguration

    /// Creates the constraint.
    ///
    /// - Parameters:
    ///   - identifier: Stable diagnostics identifier.
    ///   - configuration: Safety rails; defaults to
    ///     ``BackgroundProtectionConfiguration/standard``.
    public init(
        identifier: String = BackgroundWarpConstraint.constraintIdentifier,
        configuration: BackgroundProtectionConfiguration = .standard
    ) {
        self.identifier = identifier
        self.configuration = configuration
    }

    /// Applies background protection to `field` in place.
    ///
    /// The field density is unchanged. The method validates the field before
    /// planning and replaces the offsets with the constrained offsets.
    ///
    /// - Throws: ``GeometryError`` when the field is invalid, or
    ///   `CancellationError` when the enclosing task is cancelled.
    public func constrain(
        _ field: inout WarpField,
        analysis: PortraitAnalysis
    ) throws {
        try Task.checkCancellation()
        try field.validate()
        let plan = try makePlan(field: field, analysis: analysis)
        try plan.applyingConstraint(to: &field)
    }

    /// Builds the plan without mutating a field.
    ///
    /// Use this entry point when the editor warning strip needs detection
    /// warnings or metrics. Applying the plan's constrained offsets produces
    /// exactly the same field as ``constrain(_:analysis:)``.
    ///
    /// A zero field returns an empty plan immediately; there is nothing to
    /// protect and no detection is run.
    ///
    /// - Throws: ``GeometryError`` when the field is invalid, or
    ///   `CancellationError` when the enclosing task is cancelled.
    public func makePlan(
        field: WarpField,
        analysis: PortraitAnalysis
    ) throws -> BackgroundProtectionPlan {
        try BackgroundProtectionPlanner(configuration: configuration)
            .makePlan(field: field, analysis: analysis)
    }

    /// Assesses the risk of the current field with protection on or off.
    ///
    /// The editor calls this when the user changes the background-protection
    /// switch. With `protectionEnabled == false`, the source field is assessed
    /// directly and ``BackgroundProtectionWarning/protectionDisabled`` is always
    /// reported; a visible structure displacement also reports
    /// ``BackgroundProtectionWarning/protectionDisabledWithStructures(lineCount:rectangleCount:riskyVertexCount:)``
    /// and raises the level. With `protectionEnabled == true`, the plan is
    /// applied conceptually and the residual displacement is assessed instead.
    ///
    /// - Throws: ``GeometryError`` when the field is invalid, or
    ///   `CancellationError` when the enclosing task is cancelled.
    public func assessRisk(
        field: WarpField,
        analysis: PortraitAnalysis,
        protectionEnabled: Bool
    ) throws -> BackgroundProtectionRisk {
        let plan = try makePlan(field: field, analysis: analysis)
        let metrics = plan.metrics
        var warnings = plan.warnings

        let riskyVertexCount: Int
        let maximumDisplacement: Float
        let level: BackgroundProtectionRisk.Level

        if protectionEnabled {
            riskyVertexCount = metrics.residualRiskyVertexCount
            maximumDisplacement = metrics.maximumStructureDisplacementAfter
            level = Self.riskLevel(
                riskyVertexCount: riskyVertexCount,
                maximumDisplacement: maximumDisplacement,
                configuration: configuration
            )
            if level != .low {
                warnings.append(
                    .structureDisplacementResidual(
                        maximumDisplacement: maximumDisplacement
                    )
                )
            }
        } else {
            riskyVertexCount = metrics.riskyVertexCount
            maximumDisplacement = metrics.maximumStructureDisplacementBefore
            level = Self.riskLevel(
                riskyVertexCount: riskyVertexCount,
                maximumDisplacement: maximumDisplacement,
                configuration: configuration
            )
            warnings.append(.protectionDisabled)
            if level != .low {
                warnings.append(
                    .protectionDisabledWithStructures(
                        lineCount: metrics.detectedLineCount,
                        rectangleCount: metrics.detectedRectangleCount,
                        riskyVertexCount: riskyVertexCount
                    )
                )
            }
        }

        let structureVertexCount = plan.protectionWeights.reduce(into: 0) {
            if $1 >= 0.5 {
                $0 += 1
            }
        }
        return BackgroundProtectionRisk(
            level: level,
            riskyVertexCount: riskyVertexCount,
            structureVertexCount: structureVertexCount,
            maximumStructureDisplacement: maximumDisplacement,
            warnings: warnings,
            metrics: metrics
        )
    }

    private static func riskLevel(
        riskyVertexCount: Int,
        maximumDisplacement: Float,
        configuration: BackgroundProtectionConfiguration
    ) -> BackgroundProtectionRisk.Level {
        let threshold = configuration.riskDisplacementThreshold
        if maximumDisplacement >= threshold * 2
            || riskyVertexCount >= configuration.riskHighVertexCount {
            return .high
        }
        if maximumDisplacement >= threshold || riskyVertexCount > 0 {
            return .moderate
        }
        return .low
    }
}
