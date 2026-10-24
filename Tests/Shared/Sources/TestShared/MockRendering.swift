import Foundation
import StyleToneCore

/// Closure-backed `ImageRendering` double.
public struct MockImageRenderer: ImageRendering {
    public typealias Handler = @Sendable (RenderRequest) async throws -> RenderOutput

    private let handler: Handler

    public init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    public func render(_ request: RenderRequest) async throws -> RenderOutput {
        try await handler(request)
    }

    /// Returns the request image unchanged, optionally with warnings/duration.
    public static func echo(
        warnings: [RenderWarning] = [],
        duration: TimeInterval = 0
    ) -> MockImageRenderer {
        MockImageRenderer { request in
            RenderOutput(image: request.image, warnings: warnings, duration: duration)
        }
    }

    public static func failing(_ error: StyleToneError = .renderingFailed) -> MockImageRenderer {
        MockImageRenderer { _ in throw error }
    }
}

/// Closure-backed `ImageExporting` double.
public struct MockImageExporter: ImageExporting {
    public typealias Handler = @Sendable (ImageAsset, ExportOptions) async throws -> ExportResult

    private let handler: Handler

    public init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    public func export(_ output: ImageAsset, options: ExportOptions) async throws -> ExportResult {
        try await handler(output, options)
    }

    /// Returns a plausible result without writing a file. Use a real exporter
    /// (WP-02) when the bytes matter.
    public static func succeeding(format: ExportFormat = .heic) -> MockImageExporter {
        MockImageExporter { image, options in
            let fileExtension = options.format == .heic ? "heic" : "jpg"
            let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let url = directory
                .appendingPathComponent("styletone-mock-export-\(format.rawValue)")
                .appendingPathExtension(fileExtension)
            return ExportResult(url: url, pixelSize: image.pixelSize, format: options.format)
        }
    }

    public static func failing(_ error: StyleToneError = .exportFailed) -> MockImageExporter {
        MockImageExporter { _, _ in throw error }
    }
}

/// Returns the input image unchanged; useful while the real retouch engine is
/// being implemented.
public struct MockRetoucher: RetouchRendering {
    public typealias Handler = @Sendable (ImageAsset, PortraitAnalysis, SkinParameters) async throws -> ImageAsset

    private let handler: Handler

    public init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    public func retouch(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) async throws -> ImageAsset {
        try await handler(image, analysis, parameters)
    }

    public static func passthrough() -> MockRetoucher {
        MockRetoucher { image, _, _ in image }
    }

    public static func failing(_ error: StyleToneError = .retouchingFailed) -> MockRetoucher {
        MockRetoucher { _, _, _ in throw error }
    }
}

/// Returns the input image unchanged for blemish removal.
public struct MockBlemishRemover: BlemishRemoving {
    public typealias Handler = @Sendable (ImageAsset, BlemishPoint, PortraitAnalysis) async throws -> ImageAsset

    private let handler: Handler

    public init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    public func removeBlemish(
        _ image: ImageAsset,
        at point: BlemishPoint,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        try await handler(image, point, analysis)
    }

    public static func passthrough() -> MockBlemishRemover {
        MockBlemishRemover { image, _, _ in image }
    }

    public static func failing(_ error: StyleToneError = .retouchingFailed) -> MockBlemishRemover {
        MockBlemishRemover { _, _, _ in throw error }
    }
}

/// Returns the input image unchanged for geometry warps.
public struct MockGeometryRenderer: GeometryRendering {
    public typealias Handler = @Sendable (
        ImageAsset,
        PortraitAnalysis,
        FaceParameters,
        BodyParameters,
        Bool
    ) async throws -> ImageAsset

    private let handler: Handler

    public init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    public func warp(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: FaceParameters,
        body: BodyParameters,
        backgroundProtection: Bool
    ) async throws -> ImageAsset {
        try await handler(image, analysis, parameters, body, backgroundProtection)
    }

    public static func passthrough() -> MockGeometryRenderer {
        MockGeometryRenderer { image, _, _, _, _ in image }
    }

    public static func failing(_ error: StyleToneError = .warpingFailed) -> MockGeometryRenderer {
        MockGeometryRenderer { _, _, _, _, _ in throw error }
    }
}
