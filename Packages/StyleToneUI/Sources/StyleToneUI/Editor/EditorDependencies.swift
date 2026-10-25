import Foundation
import StyleToneCore

// MARK: - Style

public protocol EditorStyleProviding: Sendable {
    func activeStyle() async throws -> StyleProfile
}

/// Fixed style used by previews and Phase A before WP-11 is wired.
public struct StaticEditorStyleProvider: EditorStyleProviding {
    public let style: StyleProfile

    public init(style: StyleProfile = .editorNaturalDefault) {
        self.style = style
    }

    public func activeStyle() async throws -> StyleProfile {
        style
    }
}

/// Loads the active profile from a `StyleProfileStore` and falls back to the
/// natural default when none exists.
public struct StoreEditorStyleProvider: EditorStyleProviding {
    public let store: any StyleProfileStore
    public let fallback: StyleProfile

    public init(
        store: any StyleProfileStore,
        fallback: StyleProfile = .editorNaturalDefault
    ) {
        self.store = store
        self.fallback = fallback
    }

    public func activeStyle() async throws -> StyleProfile {
        try await store.loadActive() ?? fallback
    }
}

public extension StyleProfile {
    /// Neutral natural default used when no style has been calibrated.
    ///
    /// It is intentionally all-zero so an untouched editor renders the original
    /// image without invoking any engine.
    static let editorNaturalDefault = StyleProfile(
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

// MARK: - Dependencies

/// Everything the editor needs from the host.
///
/// The renderer is built from engine protocols by default, so tests can inject
/// a single `ImageRendering` double. The app composition root should pass the
/// real analyzer, retouch/geometry engines, tone engine and exporter.
public struct EditorDependencies: Sendable {
    public var analyzer: any PortraitAnalyzing
    public var renderer: any ImageRendering
    public var exporter: any ImageExporting
    public var previewPreparer: any EditorPreviewPreparing
    public var styleProvider: any EditorStyleProviding
    public var dateProvider: any DateProviding
    public var logger: any AppLogging

    public init(
        analyzer: any PortraitAnalyzing = EditorUnavailableAnalyzer(),
        retoucher: any RetouchRendering = EditorUnavailableRetoucher(),
        blemishRemover: any BlemishRemoving = EditorUnavailableBlemishRemover(),
        geometryRenderer: any GeometryRendering = EditorUnavailableGeometryRenderer(),
        toneRenderer: any EditorToneRendering = PassthroughToneRenderer(),
        renderer: (any ImageRendering)? = nil,
        exporter: any ImageExporting = EditorUnavailableExporter(),
        previewPreparer: any EditorPreviewPreparing = EditorPreviewPreparer(),
        styleProvider: any EditorStyleProviding = StaticEditorStyleProvider(),
        dateProvider: any DateProviding = SystemDateProvider(),
        logger: any AppLogging = NoopLogger()
    ) {
        self.analyzer = analyzer
        self.renderer = renderer ?? EditorRenderer(
            retoucher: retoucher,
            blemishRemover: blemishRemover,
            geometryRenderer: geometryRenderer,
            toneRenderer: toneRenderer,
            dateProvider: dateProvider
        )
        self.exporter = exporter
        self.previewPreparer = previewPreparer
        self.styleProvider = styleProvider
        self.dateProvider = dateProvider
        self.logger = logger
    }

    /// Safe defaults for previews: analysis/exporter fail closed and the
    /// renderer's unavailable engines surface an actionable issue instead of
    /// pretending to succeed.
    public static let placeholder = EditorDependencies()
}

// MARK: - Fail-closed stand-ins

public struct EditorUnavailableAnalyzer: PortraitAnalyzing {
    public init() {}

    public func analyze(_ image: ImageAsset) async throws -> PortraitAnalysis {
        throw StyleToneError.invalidState
    }
}

public struct EditorUnavailableRetoucher: RetouchRendering {
    public init() {}

    public func retouch(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) async throws -> ImageAsset {
        throw StyleToneError.invalidState
    }
}

public struct EditorUnavailableBlemishRemover: BlemishRemoving {
    public init() {}

    public func removeBlemish(
        _ image: ImageAsset,
        at point: BlemishPoint,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        throw StyleToneError.invalidState
    }
}

public struct EditorUnavailableGeometryRenderer: GeometryRendering {
    public init() {}

    public func warp(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: FaceParameters,
        body: BodyParameters,
        backgroundProtection: Bool
    ) async throws -> ImageAsset {
        throw StyleToneError.invalidState
    }
}

public struct EditorUnavailableExporter: ImageExporting {
    public init() {}

    public func export(_ output: ImageAsset, options: ExportOptions) async throws -> ExportResult {
        throw StyleToneError.exportFailed
    }
}
