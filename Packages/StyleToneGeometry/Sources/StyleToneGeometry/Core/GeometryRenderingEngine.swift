import Foundation
import StyleToneCore

/// Ordered execution of geometry passes, constraints and boundary handling.
///
/// The order is frozen by `contracts.md` §4.1:
///
/// ```text
/// Face pass → Body pass → Legs pass → constraints → background constraint
/// → boundary pinning/feathering → renderer
/// ```
///
/// Passes are sorted by ``GeometryPassPhase``, so registration order cannot
/// accidentally put legs before face. Constraint order is the array order; the
/// background constraint is always last and only runs when
/// `parameters.backgroundProtection` is `true`.
public struct GeometryPipeline: Sendable {
    /// Registered passes, stored with their execution phase.
    public let passes: [GeometryPassEntry]
    /// Post-pass constraints in execution order.
    public let constraints: [any GeometryConstraint]
    /// Background protection constraint (WP-15), run last.
    public let backgroundConstraint: (any GeometryConstraint)?
    /// Boundary pinning/feathering and displacement clamp.
    public let boundaryPolicy: GeometryBoundaryPolicy
    /// Number of vertices per grid axis.
    public let gridDimension: Int

    public init(
        passes: [GeometryPassEntry] = [],
        constraints: [any GeometryConstraint] = [],
        backgroundConstraint: (any GeometryConstraint)? = nil,
        boundaryPolicy: GeometryBoundaryPolicy = .standard,
        gridDimension: Int = GeometryQuality.preview.gridDimension
    ) {
        self.passes = passes
        self.constraints = constraints
        self.backgroundConstraint = backgroundConstraint
        self.boundaryPolicy = boundaryPolicy
        self.gridDimension = gridDimension
    }

    /// Creates a pipeline from the engine configuration.
    public init(
        passes: [GeometryPassEntry] = [],
        constraints: [any GeometryConstraint] = [],
        backgroundConstraint: (any GeometryConstraint)? = nil,
        configuration: GeometryWarpConfiguration
    ) {
        self.init(
            passes: passes,
            constraints: constraints,
            backgroundConstraint: backgroundConstraint,
            boundaryPolicy: configuration.boundaryPolicy,
            gridDimension: configuration.gridDimension
        )
    }

    /// Returns a copy at another mesh density, preserving passes, constraints
    /// and the boundary policy.
    public func withQuality(_ quality: GeometryQuality) -> GeometryPipeline {
        GeometryPipeline(
            passes: passes,
            constraints: constraints,
            backgroundConstraint: backgroundConstraint,
            boundaryPolicy: boundaryPolicy,
            gridDimension: quality.gridDimension
        )
    }

    /// Runs every stage and returns the final field.
    ///
    /// The returned field has passed validation before and after every stage and
    /// has the boundary policy applied. It is ready for a renderer backend.
    ///
    /// - Throws: `CancellationError` when the current task is cancelled, the
    ///   error thrown by a pass/constraint, or ``GeometryError`` when a stage
    ///   corrupts the field.
    public func makeField(
        analysis: PortraitAnalysis,
        parameters: GeometryParameters
    ) throws -> WarpField {
        try Task.checkCancellation()
        var field = try WarpField(width: gridDimension, height: gridDimension)

        for entry in orderedPasses {
            try Task.checkCancellation()
            try entry.pass.contribute(
                to: &field,
                analysis: analysis,
                parameters: parameters
            )
            try validateInvariants(of: field)
        }

        for constraint in constraints {
            try Task.checkCancellation()
            try constraint.constrain(&field, analysis: analysis)
            try validateInvariants(of: field)
        }

        if parameters.backgroundProtection, let backgroundConstraint {
            try Task.checkCancellation()
            try backgroundConstraint.constrain(&field, analysis: analysis)
            try validateInvariants(of: field)
        }

        try Task.checkCancellation()
        try boundaryPolicy.apply(to: &field)
        try validateInvariants(of: field)
        return field
    }

    /// Passes sorted by phase, stable for equal phases.
    public var orderedPasses: [GeometryPassEntry] {
        passes.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.phase != rhs.element.phase {
                    return lhs.element.phase < rhs.element.phase
                }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    private func validateInvariants(of field: WarpField) throws {
        try field.validate()
        guard field.width == gridDimension, field.height == gridDimension else {
            throw GeometryError.invalidGrid(width: field.width, height: field.height)
        }
    }
}

/// Default `GeometryRendering` implementation.
///
/// The actor owns the ordered pipeline and the renderer backend. It is the
/// integration point for WP-12/13/14 passes and the WP-15 background
/// constraint; WP-17 calls the protocol method with the active parameters.
public actor GeometryRenderingEngine: GeometryRendering {
    /// Ordered pipeline used for protocol calls.
    public let pipeline: GeometryPipeline
    /// Renderer backend (Metal when available, CPU otherwise).
    public let backend: any GeometryWarpBackend
    /// Quality, boundary and identity settings.
    public let configuration: GeometryWarpConfiguration

    /// Creates an engine.
    ///
    /// - Parameters:
    ///   - passes: Pass entries; phases are sorted by the pipeline.
    ///   - constraints: Non-background constraints in execution order.
    ///   - backgroundConstraint: WP-15 constraint, run only when background
    ///     protection is requested.
    ///   - configuration: Mesh quality and boundary/identity settings.
    ///   - backend: Renderer override. When `nil`, Metal is used if available,
    ///     otherwise the CPU reference backend.
    public init(
        passes: [GeometryPassEntry] = [],
        constraints: [any GeometryConstraint] = [],
        backgroundConstraint: (any GeometryConstraint)? = nil,
        configuration: GeometryWarpConfiguration = .preview,
        backend: (any GeometryWarpBackend)? = nil
    ) {
        self.pipeline = GeometryPipeline(
            passes: passes,
            constraints: constraints,
            backgroundConstraint: backgroundConstraint,
            configuration: configuration
        )
        self.backend = backend ?? GeometryBackendFactory.makeDefault()
        self.configuration = configuration
    }

    /// Identifier of the active backend (`geometry.metal` or `geometry.cpu`).
    public var backendIdentifier: String {
        backend.identifier
    }

    /// `true` when the active backend renders on the GPU.
    public var isGPUAccelerated: Bool {
        backend.isGPUAccelerated
    }

    /// `GeometryRendering` entry point.
    public func warp(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: FaceParameters,
        body: BodyParameters,
        backgroundProtection: Bool
    ) async throws -> ImageAsset {
        try await warp(
            image,
            analysis: analysis,
            geometry: GeometryParameters(
                face: parameters,
                body: body,
                backgroundProtection: backgroundProtection
            ),
            quality: configuration.quality
        )
    }

    /// Warps with a custom mesh density.
    public func warp(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        geometry: GeometryParameters,
        quality: GeometryQuality
    ) async throws -> ImageAsset {
        try Task.checkCancellation()
        let effectiveConfiguration = GeometryWarpConfiguration(
            quality: quality,
            boundaryPolicy: configuration.boundaryPolicy,
            allowsIdentityShortcut: configuration.allowsIdentityShortcut
        )
        let effectivePipeline = pipeline.withQuality(quality)

        let field = try effectivePipeline.makeField(
            analysis: analysis,
            parameters: geometry
        )
        if effectiveConfiguration.allowsIdentityShortcut, field.isZero() {
            return image
        }
        return try backend.warp(
            image,
            field: field,
            configuration: effectiveConfiguration
        )
    }

    /// Builds the field without rendering. Useful for diagnostics, tests and
    /// future background-risk warnings.
    public func makeField(
        analysis: PortraitAnalysis,
        geometry: GeometryParameters,
        quality: GeometryQuality? = nil
    ) throws -> WarpField {
        let effectivePipeline: GeometryPipeline
        if let quality {
            effectivePipeline = pipeline.withQuality(quality)
        } else {
            effectivePipeline = pipeline
        }
        return try effectivePipeline.makeField(
            analysis: analysis,
            parameters: geometry
        )
    }
}
