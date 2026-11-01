import Foundation
import StyleToneCore
import StyleToneGeometry
import StyleToneImaging
import StyleToneLearning
import StyleTonePersistence
import StyleToneRetouch
import StyleToneUI
import StyleToneVision

/// Live Phase A dependency graph for the A6 self-use build.
///
/// Every service below is the real implementation:
///
/// | Role | Implementation |
/// |---|---|
/// | profile store | `SwiftDataStyleProfileStore` |
/// | learning | `StyleLearningEngine` |
/// | pair quality | `VisionPairQualityAnalyzer` |
/// | portrait analysis | `VisionPortraitAnalyzer` |
/// | retouch / blemish | `SkinRetoucher` |
/// | geometry | `GeometryRenderingEngine(Face+Body+Legs, BackgroundWarpConstraint)` |
/// | file export | `FileImageExporter` |
/// | photo library | `PhotoKitExportPhotoLibrary` (add-only) |
/// | quota | `UnlimitedExportQuota` (Phase A allow-all) |
///
/// The struct only stores Sendable protocol existentials and immutable engine
/// values, so it can be passed through SwiftUI environments and `@Observable`
/// hosts. Constructing it performs no file or photo-library I/O; the stores do
/// their work on their own actors when first used.
struct A6Dependencies: Sendable {
    let profileStore: any StyleProfileStore
    let learner: any StyleLearning
    let pairQualityAnalyzer: any PairQualityAnalyzing
    let portraitAnalyzer: any PortraitAnalyzing
    let retoucher: any RetouchRendering
    let blemishRemover: any BlemishRemoving
    let geometryRenderer: any GeometryRendering
    let exporter: any ImageExporting
    let imageLoader: ImageLoader
    let photoLibrary: any ExportPhotoLibrary
    let quota: any ExportQuotaServicing
    let logger: any AppLogging
    let dateProvider: any DateProviding
    let pairingImageImporter: any PairingImageImporting

    init(
        profileStore: any StyleProfileStore,
        learner: any StyleLearning,
        pairQualityAnalyzer: any PairQualityAnalyzing,
        portraitAnalyzer: any PortraitAnalyzing,
        retoucher: any RetouchRendering,
        blemishRemover: any BlemishRemoving,
        geometryRenderer: any GeometryRendering,
        exporter: any ImageExporting,
        imageLoader: ImageLoader,
        photoLibrary: any ExportPhotoLibrary,
        quota: any ExportQuotaServicing,
        logger: any AppLogging,
        dateProvider: any DateProviding,
        pairingImageImporter: any PairingImageImporting
    ) {
        self.profileStore = profileStore
        self.learner = learner
        self.pairQualityAnalyzer = pairQualityAnalyzer
        self.portraitAnalyzer = portraitAnalyzer
        self.retoucher = retoucher
        self.blemishRemover = blemishRemover
        self.geometryRenderer = geometryRenderer
        self.exporter = exporter
        self.imageLoader = imageLoader
        self.photoLibrary = photoLibrary
        self.quota = quota
        self.logger = logger
        self.dateProvider = dateProvider
        self.pairingImageImporter = pairingImageImporter
    }

    // MARK: - Live composition

    /// Builds the real Phase A graph.
    ///
    /// No I/O happens here: `SwiftDataStyleProfileStore` defers container
    /// creation, the Vision analyzers are stateless values, and the geometry
    /// engine only picks a backend (Metal when available, CPU otherwise).
    static func live() -> A6Dependencies {
        let logger: any AppLogging = NoopLogger()
        let dateProvider: any DateProviding = SystemDateProvider()
        let profileStore = SwiftDataStyleProfileStore(
            logger: logger,
            dateProvider: dateProvider
        )
        let retoucher = SkinRetoucher()

        let geometryRenderer = GeometryRenderingEngine(
            passes: [
                GeometryPassEntry(phase: .face, pass: FaceWarpContributor()),
                GeometryPassEntry(phase: .body, pass: BodyWarpContributor()),
                GeometryPassEntry(phase: .legs, pass: LegsWarpContributor())
            ],
            backgroundConstraint: BackgroundWarpConstraint(),
            configuration: .preview
        )

        return A6Dependencies(
            profileStore: profileStore,
            learner: StyleLearningEngine(dateProvider: dateProvider),
            pairQualityAnalyzer: VisionPairQualityAnalyzer(),
            portraitAnalyzer: VisionPortraitAnalyzer(),
            retoucher: retoucher,
            blemishRemover: retoucher,
            geometryRenderer: geometryRenderer,
            exporter: FileImageExporter(),
            imageLoader: ImageLoader(),
            photoLibrary: makePhotoLibrary(),
            quota: UnlimitedExportQuota(),
            logger: logger,
            dateProvider: dateProvider,
            pairingImageImporter: PairingImageImporter()
        )
    }

    // MARK: - Screen factories

    #if DEBUG
    /// Test-only graph with fail-closed engines and an injectable profile
    /// store. No engine or photo-library work can happen on this path.
    ///
    /// Kept in the app target so tests do not need to name every unavailable
    /// stand-in and cannot drift from the live initializer's parameter list.
    static func testing(profileStore: any StyleProfileStore) -> A6Dependencies {
        A6Dependencies(
            profileStore: profileStore,
            learner: UnavailableStyleLearner(),
            pairQualityAnalyzer: UnavailablePairQualityAnalyzer(),
            portraitAnalyzer: UnavailablePortraitAnalyzer(),
            retoucher: UnavailableRetouchRenderer(),
            blemishRemover: UnavailableBlemishRemover(),
            geometryRenderer: UnavailableGeometryRenderer(),
            exporter: UnavailableImageExporter(),
            imageLoader: ImageLoader(),
            photoLibrary: UnavailableExportPhotoLibrary(),
            quota: UnlimitedExportQuota(),
            logger: NoopLogger(),
            dateProvider: SystemDateProvider(),
            pairingImageImporter: PairingImageImporter()
        )
    }
    #endif

    /// WP-09 pairing graph.
    ///
    /// A fresh in-memory session store is created per pairing run: the session
    /// metadata is not persisted in Phase A, and the view model restores only
    /// metadata, so reusing a store across runs would surface stale slots with
    /// no pixels. The photo importer decodes through `ImageLoader`; the picker
    /// is the out-of-process PHPicker, which needs no photo-library permission.
    func pairingDependencies() -> PairingDependencies {
        PairingDependencies(
            qualityAnalyzer: pairQualityAnalyzer,
            sessionStore: InMemoryPairingSessionStore(),
            imageImporter: pairingImageImporter,
            dateProvider: dateProvider,
            availabilityProvider: SystemPairingPickerAvailability(),
            target: .three
        )
    }

    /// WP-17 editor graph.
    ///
    /// `toneRenderer` is intentionally left at the package default
    /// (`PassthroughToneRenderer`): no real tone engine exists in the packages
    /// yet. Tone/finish sliders therefore render as a no-op in this build; see
    /// the A6 report. Retouch, blemish and geometry are live.
    func editorDependencies() -> EditorDependencies {
        EditorDependencies(
            analyzer: portraitAnalyzer,
            retoucher: retoucher,
            blemishRemover: blemishRemover,
            geometryRenderer: geometryRenderer,
            exporter: exporter,
            styleProvider: StoreEditorStyleProvider(store: profileStore),
            dateProvider: dateProvider,
            logger: logger
        )
    }

    /// WP-19 export graph.
    ///
    /// The export renderer is a real `EditorRenderer` over the same engines, so
    /// a full-resolution save reproduces the editor pipeline. The quota is an
    /// explicit Phase A allow-all and must be replaced by WP-20 before shipping.
    func exportDependencies() -> ExportDependencies {
        ExportDependencies(
            renderer: EditorRenderer(
                retoucher: retoucher,
                blemishRemover: blemishRemover,
                geometryRenderer: geometryRenderer,
                dateProvider: dateProvider
            ),
            exporter: exporter,
            photoLibrary: photoLibrary,
            quota: quota,
            logger: logger,
            dateProvider: dateProvider,
            fileStore: ExportTemporaryFileStore(),
            supportsSystemShare: ExportDependencies.systemShareSupport
        )
    }

    // MARK: - Helpers

    private static func makePhotoLibrary() -> any ExportPhotoLibrary {
        #if canImport(Photos) && os(iOS)
        return PhotoKitExportPhotoLibrary()
        #else
        return UnavailableExportPhotoLibrary()
        #endif
    }
}
