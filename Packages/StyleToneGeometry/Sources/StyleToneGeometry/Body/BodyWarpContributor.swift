import Foundation
import StyleToneCore

/// WP-13 body pass: inward arm and waist displacement from pose + person
/// segmentation.
///
/// The pass is intentionally stateless. It reads the primary
/// ``BodyObservation`` and the person mask, computes a bounded contribution, and
/// adds it to the field. It does not identify a person, estimate body
/// measurements, or scan the background for straight lines.
///
/// Safety behavior:
/// - no body / no person mask / reported occlusion / very low body confidence:
///   no displacement;
/// - multiple people: skipped by default (see ``BodyWarpConfiguration``);
/// - wrist and hand region: influence tapers to zero before the wrist;
/// - torso: arm influence is suppressed over the torso envelope;
/// - arms: waist influence is suppressed near the arm capsules;
/// - background: offsets are gated by the person mask.
///
/// Those protections are intentionally conservative. WP-15's background
/// constraint still runs after the body pass and remains responsible for
/// straight-line/background structure.
public struct BodyWarpContributor: GeometryPass {
    /// Stable pass identifier used by diagnostics and ordering tests.
    public static let passIdentifier = "body.arm-waist"

    /// Stable identifier used by the pipeline and tests.
    public let identifier: String
    /// Planner thresholds and hard displacement caps.
    public let configuration: BodyWarpConfiguration

    public init(
        identifier: String = BodyWarpContributor.passIdentifier,
        configuration: BodyWarpConfiguration = .standard
    ) {
        self.identifier = identifier
        self.configuration = configuration
    }

    /// Adds this pass's displacement to `field`.
    ///
    /// The pass never resizes the field and always adds to existing offsets so
    /// the engine's frozen Face → Body → Legs order can be preserved.
    public func contribute(
        to field: inout WarpField,
        analysis: PortraitAnalysis,
        parameters: GeometryParameters
    ) throws {
        try Task.checkCancellation()
        try field.validate()
        let plan = try makePlan(
            analysis: analysis,
            parameters: parameters,
            gridWidth: field.width,
            gridHeight: field.height
        )
        try plan.applying(to: &field)
    }

    /// Computes the contribution without mutating a field.
    ///
    /// Use this entry point when the UI needs warnings or per-region diagnostics.
    /// Calling it and then applying ``BodyWarpPlan/offsets`` produces the same
    /// result as ``contribute(to:analysis:parameters:)``.
    public func makePlan(
        analysis: PortraitAnalysis,
        parameters: GeometryParameters,
        gridWidth: Int = 32,
        gridHeight: Int = 32
    ) throws -> BodyWarpPlan {
        try BodyWarpPlanner(configuration: configuration).makePlan(
            analysis: analysis,
            parameters: parameters,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )
    }

    /// Square-grid convenience for
    /// ``makePlan(analysis:parameters:gridWidth:gridHeight:)``.
    public func makePlan(
        analysis: PortraitAnalysis,
        parameters: GeometryParameters,
        gridDimension: Int
    ) throws -> BodyWarpPlan {
        try makePlan(
            analysis: analysis,
            parameters: parameters,
            gridWidth: gridDimension,
            gridHeight: gridDimension
        )
    }

    /// Alias matching the face pass's diagnostic entry point.
    public func plan(
        for analysis: PortraitAnalysis,
        parameters: GeometryParameters,
        gridWidth: Int = 32,
        gridHeight: Int = 32
    ) throws -> BodyWarpPlan {
        try makePlan(
            analysis: analysis,
            parameters: parameters,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )
    }

    /// Square-grid alias for ``plan(for:parameters:gridWidth:gridHeight:)``.
    public func plan(
        for analysis: PortraitAnalysis,
        parameters: GeometryParameters,
        gridDimension: Int
    ) throws -> BodyWarpPlan {
        try plan(
            for: analysis,
            parameters: parameters,
            gridWidth: gridDimension,
            gridHeight: gridDimension
        )
    }
}
