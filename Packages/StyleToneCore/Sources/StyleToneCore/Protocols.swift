import Foundation

public protocol PortraitAnalyzing: Sendable {
    func analyze(_ image: ImageAsset) async throws -> PortraitAnalysis
}

public protocol PairQualityAnalyzing: Sendable {
    func assess(original: ImageAsset, edited: ImageAsset) async throws -> PairQuality
}

public protocol StyleLearning: Sendable {
    func learn(samples: [PairSample], answers: [CalibrationAnswer]) async throws -> StyleProfile
}

public protocol RetouchRendering: Sendable {
    func retouch(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) async throws -> ImageAsset
}

public protocol BlemishRemoving: Sendable {
    func removeBlemish(
        _ image: ImageAsset,
        at point: BlemishPoint,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset
}

public protocol GeometryRendering: Sendable {
    func warp(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: FaceParameters,
        body: BodyParameters,
        backgroundProtection: Bool
    ) async throws -> ImageAsset
}

public protocol ImageRendering: Sendable {
    func render(_ request: RenderRequest) async throws -> RenderOutput
}

public protocol ImageExporting: Sendable {
    func export(_ output: ImageAsset, options: ExportOptions) async throws -> ExportResult
}

public protocol StyleProfileStore: Sendable {
    func loadActive() async throws -> StyleProfile?
    func save(_ profile: StyleProfile) async throws
    func deleteAll() async throws
}

public protocol PurchaseServicing: Sendable {
    var state: PurchaseState { get async }
    func product() async throws -> PurchaseProduct
    func purchase() async throws -> PurchaseState
    func restore() async throws -> PurchaseState
}

public protocol DateProviding: Sendable {
    var now: Date { get }
}

public struct SystemDateProvider: DateProviding {
    public init() {}
    public var now: Date { Date() }
}
