import Foundation
import Observation
import StyleToneCore

/// Observable controller for the editor's skin area (WP-16).
///
/// The controller owns the smoothing/evenness preview, the blemish mark stack
/// and the render job that calls the injected `RetouchRendering` /
/// `BlemishRemoving` engines. It never mutates `ImageAsset` (immutable by
/// contract) and never keeps the original in a mutable buffer.
///
/// Failure and cancellation semantics:
/// - `sourceImage` is never replaced by a render result.
/// - `displayedImage` changes only after a successful render.
/// - On failure the last valid image, the sliders and the committed mark list
///   stay as they were; `failure` offers a retry of the same job snapshot.
/// - A render is transactional: an added mark or an undo is committed only
///   after the whole recomposition succeeds.
@MainActor
@Observable
public final class SkinToolsViewModel {
    // MARK: Dependencies

    public let configuration: SkinToolsConfiguration
    private let retoucher: any RetouchRendering
    private let blemishRemover: any BlemishRemoving

    // MARK: Immutable input

    public private(set) var sourceImage: ImageAsset
    public private(set) var analysis: PortraitAnalysis

    // MARK: Output

    /// The last successfully rendered image. Starts as `sourceImage`.
    public private(set) var displayedImage: ImageAsset

    // MARK: Controls

    public private(set) var smoothing: Double = 0
    public private(set) var evenness: Double = 0
    public private(set) var blemishes: [BlemishEdit] = []
    public private(set) var radius: Double
    public private(set) var zoomScale: Double = SkinToolsLimits.minimumZoom
    public private(set) var isBlemishMode = false

    // MARK: Status

    public private(set) var isRendering = false
    public private(set) var failure: SkinToolsFailure?
    public private(set) var notice: SkinToolsNotice?
    public private(set) var pendingBlemish: BlemishEdit?

    /// Increments whenever `displayedImage` changes (successful render, reset
    /// or source replacement). WP-17 observes this to refresh its preview.
    public private(set) var renderRevision = 0

    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var renderToken = UUID()
    @ObservationIgnored private var pendingJob: RenderJob?

    // MARK: Init

    public init(
        image: ImageAsset,
        analysis: PortraitAnalysis,
        retoucher: any RetouchRendering,
        blemishRemover: any BlemishRemoving,
        configuration: SkinToolsConfiguration = .standard
    ) {
        self.sourceImage = image
        self.analysis = analysis
        self.displayedImage = image
        self.retoucher = retoucher
        self.blemishRemover = blemishRemover
        self.configuration = configuration
        self.radius = configuration.defaultRadius
        self.zoomScale = configuration.minimumZoom
    }

    /// Convenience for an engine that conforms to both protocols, such as
    /// WP-07's `SkinRetoucher`.
    public convenience init<Engine>(
        image: ImageAsset,
        analysis: PortraitAnalysis,
        engine: Engine,
        configuration: SkinToolsConfiguration = .standard
    ) where Engine: RetouchRendering & BlemishRemoving {
        self.init(
            image: image,
            analysis: analysis,
            retoucher: engine,
            blemishRemover: engine,
            configuration: configuration
        )
    }

    // MARK: Availability

    public var isFaceAvailable: Bool {
        analysis.hasFace
    }

    /// Whether the analysis belongs to the image being displayed.
    public var isAnalysisCompatible: Bool {
        analysis.imageSize == sourceImage.pixelSize
    }

    /// `nil` when the controls can operate.
    public var unavailableReason: SkinToolsUnavailableReason? {
        if !isFaceAvailable { return .noFace }
        if !isAnalysisCompatible { return .analysisMismatch }
        return nil
    }

    public var areControlsEnabled: Bool {
        unavailableReason == nil
    }

    /// False when WP-05 produced no skin mask, or a mask of the wrong size.
    /// The engine safely no-ops in both cases, so the panel shows an
    /// explanatory hint instead of failing.
    public var isSkinMaskAvailable: Bool {
        guard let mask = analysis.skinMask else { return false }
        return mask.width == sourceImage.pixelSize.width
            && mask.height == sourceImage.pixelSize.height
    }

    // MARK: Derived state

    public var hasAdjustments: Bool {
        smoothing > 0 || evenness > 0 || !blemishes.isEmpty
    }

    /// True when the displayed pixels are the untouched source image.
    public var isShowingOriginal: Bool {
        displayedImage.cgImage === sourceImage.cgImage
    }

    /// True only when the displayed image is the original and no control has
    /// a pending adjustment.
    public var isAtOriginal: Bool {
        isShowingOriginal && !hasAdjustments
    }

    public var canApplyBlemish: Bool {
        areControlsEnabled
            && !isRendering
            && blemishes.count < configuration.maximumBlemishes
    }

    public var canUndoBlemish: Bool {
        areControlsEnabled && !isRendering && !blemishes.isEmpty
    }

    public var canClearBlemishes: Bool {
        canUndoBlemish
    }

    public var canCancelRendering: Bool {
        isRendering
    }

    public var canReset: Bool {
        hasAdjustments || isRendering
    }

    public var canZoomIn: Bool {
        areControlsEnabled && zoomScale < configuration.maximumZoom
    }

    public var canZoomOut: Bool {
        areControlsEnabled && zoomScale > configuration.minimumZoom
    }

    public var canResetZoom: Bool {
        canZoomOut
    }

    public var maximumBlemishes: Int {
        configuration.maximumBlemishes
    }

    /// Parameters for the WP-07 retouch stage. `blemish` mirrors whether the UI
    /// holds marks; the actual repair goes through `blemishPoints`.
    public var skinParameters: SkinParameters {
        SkinParameters(
            smoothing: smoothing,
            evenness: evenness,
            blemish: blemishes.isEmpty ? 0 : 1
        )
    }

    /// Points for `RenderRequest.blemishPoints` (WP-17 integration).
    public var blemishPoints: [BlemishPoint] {
        blemishes.map(\.blemishPoint)
    }

    /// The skin fields WP-17 can copy into `ManualAdjustments`.
    public var manualAdjustments: ManualAdjustments {
        ManualAdjustments(
            smoothing: smoothing,
            evenness: evenness,
            blemish: blemishes.isEmpty ? 0 : 1
        )
    }

    /// Copies only the skin fields into an existing adjustment set, leaving
    /// tone/geometry fields untouched.
    public func applySkinFields(to adjustments: inout ManualAdjustments) {
        adjustments.smoothing = smoothing
        adjustments.evenness = evenness
        adjustments.blemish = blemishes.isEmpty ? 0 : 1
    }

    // MARK: Sliders

    public func setSmoothing(_ value: Double) {
        guard areControlsEnabled, pendingBlemish == nil else { return }
        let clamped = SkinToolsMath.clampUnit(value)
        guard clamped != smoothing else { return }
        smoothing = clamped
        requestRender(makeJob(kind: .retouch), delay: configuration.renderDelay)
    }

    public func setEvenness(_ value: Double) {
        guard areControlsEnabled, pendingBlemish == nil else { return }
        let clamped = SkinToolsMath.clampUnit(value)
        guard clamped != evenness else { return }
        evenness = clamped
        requestRender(makeJob(kind: .retouch), delay: configuration.renderDelay)
    }

    // MARK: Blemish mode

    public func beginBlemishMode() {
        guard areControlsEnabled else { return }
        isBlemishMode = true
        notice = nil
    }

    public func endBlemishMode() {
        isBlemishMode = false
    }

    public func setRadius(_ value: Double) {
        guard areControlsEnabled else { return }
        radius = SkinToolsMath.clampRadius(value)
    }

    /// Applies a repair at a normalized image point.
    ///
    /// The mark is committed only after the engine succeeds; a failed repair
    /// leaves the image and the undo history untouched.
    public func addBlemish(at point: NormalizedPoint) {
        guard areControlsEnabled, !isRendering else { return }
        guard point.x.isFinite, point.y.isFinite else { return }
        guard blemishes.count < configuration.maximumBlemishes else {
            notice = .blemishLimitReached
            return
        }

        let edit = BlemishEdit(point: point, radius: radius)
        let target = blemishes + [edit]
        requestRender(
            RenderJob(
                sliders: currentParameters,
                blemishes: target,
                kind: .blemish,
                candidate: edit
            ),
            delay: .zero
        )
    }

    /// Removes the last mark. The result is transactional: on failure the mark
    /// stays applied and the previous image remains visible.
    public func undoBlemish() {
        guard canUndoBlemish else { return }
        var target = blemishes
        target.removeLast()
        requestRender(
            RenderJob(
                sliders: currentParameters,
                blemishes: target,
                kind: .undo,
                candidate: nil
            ),
            delay: .zero
        )
    }

    /// Removes every mark with the same transactional semantics as undo.
    public func clearBlemishes() {
        guard canClearBlemishes else { return }
        requestRender(
            RenderJob(
                sliders: currentParameters,
                blemishes: [],
                kind: .undo,
                candidate: nil
            ),
            delay: .zero
        )
    }

    // MARK: Zoom

    public func setZoom(_ value: Double) {
        guard areControlsEnabled, value.isFinite else { return }
        zoomScale = min(
            max(value, configuration.minimumZoom),
            configuration.maximumZoom
        )
    }

    public func zoomIn() {
        setZoom(zoomScale + SkinToolsLimits.zoomStep)
    }

    public func zoomOut() {
        setZoom(zoomScale - SkinToolsLimits.zoomStep)
    }

    public func resetZoom() {
        setZoom(configuration.minimumZoom)
    }

    // MARK: Lifecycle / recovery

    /// Cancels an in-flight render. The displayed image and committed marks
    /// stay at their last valid values.
    public func cancelRendering() {
        guard isRendering else { return }
        renderToken = UUID()
        renderTask?.cancel()
        renderTask = nil
        isRendering = false
        pendingBlemish = nil
        pendingJob = nil
        failure = nil
        notice = .renderingCancelled
    }

    /// Retries the exact job that failed, using its slider/mark snapshot.
    public func retry() {
        guard !isRendering, failure != nil, let job = pendingJob else { return }
        requestRender(job, delay: .zero)
    }

    public func dismissFailure() {
        failure = nil
        pendingJob = nil
    }

    public func dismissNotice() {
        notice = nil
    }

    /// Restores the original image and clears every skin adjustment.
    public func reset() {
        cancelCurrentWork()
        smoothing = 0
        evenness = 0
        blemishes = []
        pendingBlemish = nil
        failure = nil
        notice = nil
        radius = configuration.defaultRadius
        zoomScale = configuration.minimumZoom
        isBlemishMode = false
        displayedImage = sourceImage
        renderRevision += 1
    }

    /// Replaces the edited photo (for example after a new import) and resets
    /// the skin area. The old render task is cancelled and cannot commit.
    public func replaceSource(_ image: ImageAsset, analysis: PortraitAnalysis) {
        cancelCurrentWork()
        sourceImage = image
        self.analysis = analysis
        displayedImage = image
        smoothing = 0
        evenness = 0
        blemishes = []
        pendingBlemish = nil
        failure = nil
        notice = nil
        radius = configuration.defaultRadius
        zoomScale = configuration.minimumZoom
        isBlemishMode = false
        renderRevision += 1
    }

    /// Test/host hook that waits for the current render job to settle.
    public func waitForRendering() async {
        while isRendering {
            guard let task = renderTask else { break }
            await task.value
        }
    }

    // MARK: Rendering

    private var currentParameters: SkinParameters {
        SkinParameters(
            smoothing: smoothing,
            evenness: evenness,
            blemish: blemishes.isEmpty ? 0 : 1
        )
    }

    private struct RenderJob: Sendable {
        let sliders: SkinParameters
        let blemishes: [BlemishEdit]
        let kind: SkinToolsFailure.Kind
        let candidate: BlemishEdit?
    }

    private func makeJob(kind: SkinToolsFailure.Kind) -> RenderJob {
        RenderJob(
            sliders: currentParameters,
            blemishes: blemishes,
            kind: kind,
            candidate: nil
        )
    }

    private func requestRender(_ job: RenderJob, delay: Duration) {
        guard areControlsEnabled else { return }

        renderTask?.cancel()
        let token = UUID()
        renderToken = token
        failure = nil
        notice = nil
        pendingBlemish = job.candidate
        isRendering = true
        let effectiveDelay = max(delay, .zero)

        renderTask = Task { @MainActor [weak self] in
            if effectiveDelay > .zero {
                do {
                    try await Task.sleep(for: effectiveDelay)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, let self else { return }
            guard self.renderToken == token else { return }
            await self.perform(job, token: token)
        }
    }

    private func perform(_ job: RenderJob, token: UUID) async {
        guard renderToken == token else { return }

        let source = sourceImage
        let analysis = self.analysis

        do {
            try Task.checkCancellation()
            var image = source

            // Zero strength must return the source itself, bit for bit. Do not
            // call the engine for a neutral job: the identity check is what
            // proves "strength 0 = original".
            if job.sliders.smoothing > 0 || job.sliders.evenness > 0 {
                image = try await retoucher.retouch(
                    source,
                    analysis: analysis,
                    parameters: job.sliders
                )
            }

            for edit in job.blemishes {
                try Task.checkCancellation()
                image = try await blemishRemover.removeBlemish(
                    image,
                    at: edit.blemishPoint,
                    analysis: analysis
                )
            }

            try Task.checkCancellation()
            guard renderToken == token else { return }

            displayedImage = image
            blemishes = job.blemishes
            pendingBlemish = nil
            pendingJob = nil
            failure = nil
            isRendering = false
            renderTask = nil
            renderRevision += 1
        } catch {
            guard renderToken == token else { return }

            isRendering = false
            renderTask = nil
            pendingBlemish = nil

            if Self.isCancellation(error) {
                notice = .renderingCancelled
            } else {
                pendingJob = job
                failure = SkinToolsFailure(
                    kind: job.kind,
                    underlying: error as? StyleToneError
                )
            }
        }
    }

    private func cancelCurrentWork() {
        renderToken = UUID()
        renderTask?.cancel()
        renderTask = nil
        pendingJob = nil
        isRendering = false
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let styleToneError = error as? StyleToneError {
            return styleToneError.isCancellation
        }
        return false
    }
}
