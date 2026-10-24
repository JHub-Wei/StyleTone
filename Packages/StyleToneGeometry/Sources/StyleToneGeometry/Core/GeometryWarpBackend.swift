import Foundation
import StyleToneCore

/// Mesh density used by the engine.
///
/// Preview uses a 32×32 vertex grid (interactive), export uses 64×64. The
/// values are part of the WP-06 contract; WP-12/13/14 receive whatever field
/// the engine selects and must not assume a fixed size.
public enum GeometryQuality: String, Sendable, CaseIterable, Codable {
    case preview
    case export

    /// Number of vertices per grid axis.
    public var gridDimension: Int {
        switch self {
        case .preview:
            return 32
        case .export:
            return 64
        }
    }
}

/// Runtime configuration for one warp.
public struct GeometryWarpConfiguration: Sendable, Equatable {
    /// Mesh density.
    public var quality: GeometryQuality
    /// Boundary pinning/feathering and displacement clamp.
    public var boundaryPolicy: GeometryBoundaryPolicy
    /// When `true`, a field that is already zero returns the input image
    /// untouched (bit-exact, no colour round trip).
    public var allowsIdentityShortcut: Bool

    public init(
        quality: GeometryQuality = .preview,
        boundaryPolicy: GeometryBoundaryPolicy = .standard,
        allowsIdentityShortcut: Bool = true
    ) {
        self.quality = quality
        self.boundaryPolicy = boundaryPolicy
        self.allowsIdentityShortcut = allowsIdentityShortcut
    }

    /// Interactive configuration: 32×32 grid, identity shortcut enabled.
    public static let preview = GeometryWarpConfiguration(quality: .preview)
    /// Export configuration: 64×64 grid, identity shortcut enabled.
    public static let export = GeometryWarpConfiguration(quality: .export)

    /// Grid dimension derived from ``quality``.
    public var gridDimension: Int {
        quality.gridDimension
    }
}

/// Backend that turns a validated `WarpField` into pixels.
///
/// `GeometryRenderingEngine` owns the field construction and ordering; a
/// backend only performs the sampling/render step. Backends must be
/// `Sendable`; the engine is an actor and serialises calls.
public protocol GeometryWarpBackend: Sendable {
    /// Stable backend name for diagnostics and performance reports.
    var identifier: String { get }
    /// `true` when the backend uses the GPU.
    var isGPUAccelerated: Bool { get }

    /// Warps `image` with `field`.
    ///
    /// - Parameters:
    ///   - image: Source exchange image. It is not mutated.
    ///   - field: Validated displacement field.
    ///   - configuration: Quality and boundary/identity settings. Boundary
    ///     pinning is normally already applied by the pipeline; a backend must
    ///     still validate the field and must not trust caller-managed input.
    /// - Returns: A new image with the same pixel size and colour space.
    func warp(
        _ image: ImageAsset,
        field: WarpField,
        configuration: GeometryWarpConfiguration
    ) throws -> ImageAsset
}

/// Creates the best available backend for the current device.
public enum GeometryBackendFactory {
    /// Returns Metal when available, otherwise the CPU reference backend.
    ///
    /// The CPU backend is a correctness/reference path, not a 30 fps target.
    public static func makeDefault() -> any GeometryWarpBackend {
        #if canImport(Metal)
        if let metal = MetalGeometryWarp.makeIfAvailable() {
            return metal
        }
        #endif
        return CPUGeometryWarp()
    }
}
