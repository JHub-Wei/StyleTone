import Foundation
import StyleToneCore

/// Everything the export flow needs from the host.
///
/// The UI target depends on `StyleToneCore` protocols only. The composition root
/// injects the WP-17 renderer, the WP-02 file exporter, a PhotoKit adapter, the
/// WP-20 quota service, logging and the clock. Defaults fail closed so a
/// half-wired build cannot pretend to save photos.
public struct ExportDependencies: Sendable {
    public var renderer: any ImageRendering
    public var exporter: any ImageExporting
    public var photoLibrary: any ExportPhotoLibrary
    public var quota: any ExportQuotaServicing
    public var logger: any AppLogging
    public var dateProvider: any DateProviding
    public var fileStore: ExportTemporaryFileStore
    /// False on platforms without the system share sheet (macOS package tests).
    public var supportsSystemShare: Bool

    public init(
        renderer: any ImageRendering = UnavailableExportRenderer(),
        exporter: any ImageExporting = UnavailableExportExporter(),
        photoLibrary: any ExportPhotoLibrary = UnavailableExportPhotoLibrary(),
        quota: any ExportQuotaServicing = UnavailableExportQuota(),
        logger: any AppLogging = NoopLogger(),
        dateProvider: any DateProviding = SystemDateProvider(),
        fileStore: ExportTemporaryFileStore = ExportTemporaryFileStore(),
        supportsSystemShare: Bool = ExportDependencies.systemShareSupport
    ) {
        self.renderer = renderer
        self.exporter = exporter
        self.photoLibrary = photoLibrary
        self.quota = quota
        self.logger = logger
        self.dateProvider = dateProvider
        self.fileStore = fileStore
        self.supportsSystemShare = supportsSystemShare
    }

    /// Safe defaults for previews and tests before the engines land.
    public static let placeholder = ExportDependencies()

    /// `true` when `ExportShareSheet` can present `UIActivityViewController`.
    #if canImport(UIKit)
    public static let systemShareSupport = true
    #else
    public static let systemShareSupport = false
    #endif
}

// MARK: - Fail-closed stand-ins

/// Renderer used before WP-17 is wired; throws instead of returning a proxy.
public struct UnavailableExportRenderer: ImageRendering, Sendable {
    public init() {}

    public func render(_ request: RenderRequest) async throws -> RenderOutput {
        throw StyleToneError.invalidState
    }
}

/// Exporter used before WP-02 is wired; throws instead of faking a file.
public struct UnavailableExportExporter: ImageExporting, Sendable {
    public init() {}

    public func export(_ output: ImageAsset, options: ExportOptions) async throws -> ExportResult {
        throw StyleToneError.invalidState
    }
}
