import StyleToneCore
import SwiftUI

/// Composition root for the app shell.
///
/// The container depends only on `StyleToneCore` protocols. Concrete Vision,
/// Metal, SwiftData and StoreKit implementations are injected later by the
/// integration work packages; the app shell must never import them. Until then
/// `AppDependencies.placeholder` supplies explicit "unavailable" stand-ins so
/// placeholder screens can be previewed without crashing.
struct AppDependencies: Sendable {
    var portraitAnalyzer: any PortraitAnalyzing
    var pairQualityAnalyzer: any PairQualityAnalyzing
    var learner: any StyleLearning
    var retouchRenderer: any RetouchRendering
    var blemishRemover: any BlemishRemoving
    var geometryRenderer: any GeometryRendering
    var imageRenderer: any ImageRendering
    var exporter: any ImageExporting
    var profileStore: any StyleProfileStore
    var purchases: any PurchaseServicing
    var logger: any AppLogging
    var dateProvider: any DateProviding

    init(
        portraitAnalyzer: any PortraitAnalyzing = UnavailablePortraitAnalyzer(),
        pairQualityAnalyzer: any PairQualityAnalyzing = UnavailablePairQualityAnalyzer(),
        learner: any StyleLearning = UnavailableStyleLearner(),
        retouchRenderer: any RetouchRendering = UnavailableRetouchRenderer(),
        blemishRemover: any BlemishRemoving = UnavailableBlemishRemover(),
        geometryRenderer: any GeometryRendering = UnavailableGeometryRenderer(),
        imageRenderer: any ImageRendering = UnavailableImageRenderer(),
        exporter: any ImageExporting = UnavailableImageExporter(),
        profileStore: any StyleProfileStore = UnavailableProfileStore(),
        purchases: any PurchaseServicing = UnavailablePurchaseService(),
        logger: any AppLogging = NoopLogger(),
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.portraitAnalyzer = portraitAnalyzer
        self.pairQualityAnalyzer = pairQualityAnalyzer
        self.learner = learner
        self.retouchRenderer = retouchRenderer
        self.blemishRemover = blemishRemover
        self.geometryRenderer = geometryRenderer
        self.imageRenderer = imageRenderer
        self.exporter = exporter
        self.profileStore = profileStore
        self.purchases = purchases
        self.logger = logger
        self.dateProvider = dateProvider
    }

    /// Safe container for placeholders and previews.
    static let placeholder = AppDependencies()
}

// MARK: - Unavailable stand-ins

// These types exist so the shell can run before engine work packages land.
// They throw `StyleToneError.invalidState` rather than pretending to succeed;
// the composition root replaces them with real implementations.

struct UnavailablePortraitAnalyzer: PortraitAnalyzing {
    func analyze(_ image: ImageAsset) async throws -> PortraitAnalysis {
        throw StyleToneError.invalidState
    }
}

struct UnavailablePairQualityAnalyzer: PairQualityAnalyzing {
    func assess(original: ImageAsset, edited: ImageAsset) async throws -> PairQuality {
        throw StyleToneError.invalidState
    }
}

struct UnavailableStyleLearner: StyleLearning {
    func learn(samples: [PairSample], answers: [CalibrationAnswer]) async throws -> StyleProfile {
        throw StyleToneError.invalidState
    }
}

struct UnavailableRetouchRenderer: RetouchRendering {
    func retouch(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) async throws -> ImageAsset {
        throw StyleToneError.invalidState
    }
}

struct UnavailableBlemishRemover: BlemishRemoving {
    func removeBlemish(
        _ image: ImageAsset,
        at point: BlemishPoint,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        throw StyleToneError.invalidState
    }
}

struct UnavailableGeometryRenderer: GeometryRendering {
    func warp(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: FaceParameters,
        body: BodyParameters,
        backgroundProtection: Bool
    ) async throws -> ImageAsset {
        throw StyleToneError.invalidState
    }
}

struct UnavailableImageRenderer: ImageRendering {
    func render(_ request: RenderRequest) async throws -> RenderOutput {
        throw StyleToneError.invalidState
    }
}

struct UnavailableImageExporter: ImageExporting {
    func export(_ output: ImageAsset, options: ExportOptions) async throws -> ExportResult {
        throw StyleToneError.invalidState
    }
}

struct UnavailableProfileStore: StyleProfileStore {
    func loadActive() async throws -> StyleProfile? {
        throw StyleToneError.invalidState
    }

    func save(_ profile: StyleProfile) async throws {
        throw StyleToneError.invalidState
    }

    func deleteAll() async throws {
        throw StyleToneError.invalidState
    }
}

struct UnavailablePurchaseService: PurchaseServicing {
    var state: PurchaseState {
        get async { .unknown }
    }

    func product() async throws -> PurchaseProduct {
        throw StyleToneError.invalidState
    }

    func purchase() async throws -> PurchaseState {
        throw StyleToneError.invalidState
    }

    func restore() async throws -> PurchaseState {
        throw StyleToneError.invalidState
    }
}

private struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue = AppDependencies.placeholder
}

extension EnvironmentValues {
    /// Dependency container injected by the shell; screens resolve services
    /// through Core protocols only.
    var appDependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
