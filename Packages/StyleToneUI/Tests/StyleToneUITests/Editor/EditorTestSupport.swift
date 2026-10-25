import Foundation
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

// MARK: - Factories

enum EditorTestFactory {
    static let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
    static let imageSize = PixelSize(width: 200, height: 100)
    static let previewSize = PixelSize(width: 64, height: 32)

    static func image(size: PixelSize = imageSize) throws -> ImageAsset {
        try MockImageAssetFactory.solid(size: size)
    }

    static func analysis(
        size: PixelSize = imageSize,
        faceCount: Int = 1,
        includesBody: Bool = true,
        warnings: [AnalysisWarning] = []
    ) throws -> PortraitAnalysis {
        try MockPortraitAnalysisFactory.portrait(
            size: size,
            faceCount: faceCount,
            includesBody: includesBody,
            includesMasks: true,
            warnings: warnings
        )
    }

    static func dependencies(
        renderer: any ImageRendering,
        exporter: any ImageExporting = EditorRecordingExporter(),
        analyzer: any PortraitAnalyzing,
        style: StyleProfile = .editorNaturalDefault,
        previewSize: PixelSize = EditorTestFactory.previewSize
    ) -> EditorDependencies {
        EditorDependencies(
            analyzer: analyzer,
            renderer: renderer,
            exporter: exporter,
            previewPreparer: EditorStubPreviewPreparer(size: previewSize),
            styleProvider: StaticEditorStyleProvider(style: style),
            dateProvider: FixedDateProvider(referenceDate),
            logger: NoopLogger()
        )
    }

    @MainActor
    static func viewModel(
        renderer: any ImageRendering,
        exporter: any ImageExporting = EditorRecordingExporter(),
        analyzer: any PortraitAnalyzing,
        style: StyleProfile = .editorNaturalDefault,
        previewSize: PixelSize = EditorTestFactory.previewSize
    ) -> EditorViewModel {
        EditorViewModel(
            dependencies: dependencies(
                renderer: renderer,
                exporter: exporter,
                analyzer: analyzer,
                style: style,
                previewSize: previewSize
            )
        )
    }

    @MainActor
    static func loadedViewModel(
        renderer: any ImageRendering = EditorRecordingRenderer(),
        exporter: any ImageExporting = EditorRecordingExporter(),
        style: StyleProfile = .editorNaturalDefault,
        analysis: PortraitAnalysis? = nil,
        image: ImageAsset? = nil
    ) async throws -> (EditorViewModel, ImageAsset, PortraitAnalysis) {
        let resolvedImage = try image ?? self.image()
        let resolvedAnalysis = try analysis ?? self.analysis(size: resolvedImage.pixelSize)
        let model = viewModel(
            renderer: renderer,
            exporter: exporter,
            analyzer: EditorFixedAnalyzer(resolvedAnalysis),
            style: style
        )
        await model.load(image: resolvedImage)
        await model.waitForRenderIdle()
        return (model, resolvedImage, resolvedAnalysis)
    }
}

// MARK: - Analyzers

struct EditorFixedAnalyzer: PortraitAnalyzing {
    let analysis: PortraitAnalysis

    init(_ analysis: PortraitAnalysis) {
        self.analysis = analysis
    }

    func analyze(_ image: ImageAsset) async throws -> PortraitAnalysis {
        analysis
    }
}

/// Replays a fixed list of timestamps so render duration is deterministic.
final class EditorSteppingDateProvider: DateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let dates: [Date]
    private var index = 0

    init(dates: [Date]) {
        self.dates = dates.isEmpty ? [EditorTestFactory.referenceDate] : dates
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        let date = dates[min(index, dates.count - 1)]
        index += 1
        return date
    }
}

actor EditorScriptedAnalyzer: PortraitAnalyzing {
    enum Step: Sendable {
        case success(PortraitAnalysis)
        case failure(StyleToneError)
    }

    private var steps: [Step]
    private(set) var callCount = 0

    init(steps: [Step]) {
        self.steps = steps
    }

    func analyze(_ image: ImageAsset) async throws -> PortraitAnalysis {
        callCount += 1
        guard !steps.isEmpty else {
            throw StyleToneError.imageAnalysisFailed
        }
        switch steps.removeFirst() {
        case let .success(analysis):
            return analysis
        case let .failure(error):
            throw error
        }
    }
}

// MARK: - Renderers

/// Records requests and returns the request image unchanged.
actor EditorRecordingRenderer: ImageRendering {
    private(set) var requests: [RenderRequest] = []
    private var errors: [StyleToneError?] = []
    private var durations: [TimeInterval] = []

    func setErrors(_ errors: [StyleToneError?]) {
        self.errors = errors
    }

    func setDurations(_ durations: [TimeInterval]) {
        self.durations = durations
    }

    var callCount: Int {
        requests.count
    }

    func render(_ request: RenderRequest) async throws -> RenderOutput {
        requests.append(request)

        if !errors.isEmpty {
            let error = errors.removeFirst()
            if let error {
                throw error
            }
        }

        let duration = durations.isEmpty ? 0.02 : durations.removeFirst()
        return RenderOutput(image: request.image, warnings: [], duration: duration)
    }
}

/// A renderer whose completions are controlled by the test.
///
/// `releaseNext()` lets the next request finish; a canceled pipeline task then
/// fails its `Task.checkCancellation()` after the gate, proving the canceled
/// result is discarded without a real timer or sleep.
actor EditorGatedRenderer: ImageRendering {
    private(set) var requests: [RenderRequest] = []
    private var releases: [CheckedContinuation<Void, Never>] = []
    private var permits = 0
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func render(_ request: RenderRequest) async throws -> RenderOutput {
        requests.append(request)
        resumeWaiters()

        if permits > 0 {
            permits -= 1
        } else {
            await withCheckedContinuation { continuation in
                releases.append(continuation)
            }
        }

        try Task.checkCancellation()
        let image = try MockImageAssetFactory.solid(size: request.image.pixelSize)
        return RenderOutput(image: image, warnings: [], duration: 0.02)
    }

    func waitForRequestCount(_ count: Int) async {
        if requests.count >= count {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func releaseNext() {
        if !releases.isEmpty {
            let continuation = releases.removeFirst()
            continuation.resume()
        } else {
            permits += 1
        }
    }

    private func resumeWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if requests.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }
}

// MARK: - Preview

struct EditorStubPreviewPreparer: EditorPreviewPreparing {
    let size: PixelSize

    func preparePreview(
        image: ImageAsset,
        analysis: PortraitAnalysis,
        maximumLongEdge: Int
    ) async throws -> EditorPreviewContext {
        let preview = try MockImageAssetFactory.solid(size: size)
        let previewAnalysis = PortraitAnalysis(
            imageSize: size,
            faces: analysis.faces,
            body: analysis.body,
            personMask: nil,
            skinMask: nil,
            backgroundEdgeMask: nil,
            warnings: analysis.warnings
        )
        return EditorPreviewContext(image: preview, analysis: previewAnalysis)
    }
}

// MARK: - Exporter

actor EditorRecordingExporter: ImageExporting {
    private(set) var images: [ImageAsset] = []
    private(set) var options: [ExportOptions] = []
    private var error: StyleToneError?

    func setError(_ error: StyleToneError?) {
        self.error = error
    }

    var callCount: Int {
        images.count
    }

    func export(_ output: ImageAsset, options: ExportOptions) async throws -> ExportResult {
        if let error {
            throw error
        }
        images.append(output)
        self.options.append(options)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-export")
            .appendingPathExtension(options.format == .heic ? "heic" : "jpg")
        return ExportResult(url: url, pixelSize: output.pixelSize, format: options.format)
    }
}

// MARK: - Orchestration probes

actor EditorCallLog {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }
}

struct EditorLoggingRetoucher: RetouchRendering {
    let log: EditorCallLog

    func retouch(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) async throws -> ImageAsset {
        await log.append("retouch")
        return image
    }
}

struct EditorLoggingBlemishRemover: BlemishRemoving {
    let log: EditorCallLog

    func removeBlemish(
        _ image: ImageAsset,
        at point: BlemishPoint,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        await log.append("blemish")
        return image
    }
}

struct EditorLoggingGeometryRenderer: GeometryRendering {
    let log: EditorCallLog

    func warp(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: FaceParameters,
        body: BodyParameters,
        backgroundProtection: Bool
    ) async throws -> ImageAsset {
        await log.append(backgroundProtection ? "geometry:protected" : "geometry:open")
        return image
    }
}

struct EditorLoggingToneRenderer: EditorToneRendering {
    let log: EditorCallLog

    func applyTone(
        _ image: ImageAsset,
        settings: EditorToneSettings,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        await log.append("tone")
        return image
    }
}

struct EditorFailingToneRenderer: EditorToneRendering {
    let error: StyleToneError

    init(error: StyleToneError = .renderingFailed) {
        self.error = error
    }

    func applyTone(
        _ image: ImageAsset,
        settings: EditorToneSettings,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        throw error
    }
}

struct EditorCancellingRetoucher: RetouchRendering {
    func retouch(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) async throws -> ImageAsset {
        throw CancellationError()
    }
}

struct EditorFailingRetoucher: RetouchRendering {
    let error: StyleToneError

    init(error: StyleToneError = .retouchingFailed) {
        self.error = error
    }

    func retouch(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) async throws -> ImageAsset {
        throw error
    }
}

struct EditorCancellingBlemishRemover: BlemishRemoving {
    func removeBlemish(
        _ image: ImageAsset,
        at point: BlemishPoint,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        throw CancellationError()
    }
}

struct EditorFailingGeometryRenderer: GeometryRendering {
    let error: StyleToneError

    init(error: StyleToneError = .warpingFailed) {
        self.error = error
    }

    func warp(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: FaceParameters,
        body: BodyParameters,
        backgroundProtection: Bool
    ) async throws -> ImageAsset {
        throw error
    }
}
