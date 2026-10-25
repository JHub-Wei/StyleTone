import Foundation
import Observation
import StyleToneCore

/// State, actions and undo history for the editor.
///
/// The view model owns the edit state and the interaction rules, but delegates
/// all pixel work to `ImageRendering`. Preview and full renders are scheduled
/// through `EditorRenderPipeline`: dragging uses a downscaled proxy, releasing
/// the slider requests full quality, and a newer request always wins.
@MainActor
@Observable
public final class EditorViewModel {
    // MARK: Observable state

    public private(set) var image: ImageAsset?
    public private(set) var analysis: PortraitAnalysis?
    public private(set) var style: StyleProfile
    public private(set) var edits: EditorEditState
    public private(set) var displayedImage: ImageAsset?
    public private(set) var displayedQuality: EditorRenderQuality = .full
    public private(set) var selectedArea: EditorToolArea = .face
    public private(set) var renderState: EditorRenderState = .idle
    public private(set) var renderWarnings: [EditorWarning] = []
    public private(set) var issue: EditorIssue?
    public private(set) var isShowingOriginal = false
    public private(set) var isSplitComparisonEnabled = false
    public private(set) var splitPosition: Double = 0.5
    public private(set) var zoom = EditorZoomState()
    public private(set) var pendingBackgroundProtectionDisable = false
    public private(set) var exportState: EditorExportState = .idle
    public private(set) var lastExport: ExportResult?
    public private(set) var performanceLevel: EditorPerformanceLevel = .full
    public private(set) var lastRenderDuration: TimeInterval?
    public private(set) var isAnalyzing = false
    public private(set) var isLoadingStyle = false
    public private(set) var isReadyForEditing = false
    public private(set) var hasLoaded = false
    public private(set) var undoCount = 0
    public private(set) var redoCount = 0

    // MARK: Private state

    private let dependencies: EditorDependencies
    @ObservationIgnored private var history = EditorHistory()
    @ObservationIgnored private var interactionBaseline: EditorEditState?
    @ObservationIgnored private var isInteracting = false
    @ObservationIgnored private var renderGeneration = 0
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var governor = EditorPerformanceGovernor()
    @ObservationIgnored private var lastFullRenderedEdits: EditorEditState?
    @ObservationIgnored private var lastExportOptions: ExportOptions?

    @ObservationIgnored private lazy var pipeline: EditorRenderPipeline = {
        EditorRenderPipeline(
            renderer: dependencies.renderer,
            previewPreparer: dependencies.previewPreparer
        ) { [weak self] completion in
            self?.receive(completion)
        }
    }()

    private enum RenderMode {
        case automatic
        case full
    }

    // MARK: Init

    public init(dependencies: EditorDependencies = .placeholder) {
        self.dependencies = dependencies
        self.style = .editorNaturalDefault
        self.edits = .initial
    }

    // MARK: Derived state

    public var hasImage: Bool { image != nil }

    public var canEdit: Bool {
        image != nil && isReadyForEditing
    }

    public var canUndo: Bool { undoCount > 0 }
    public var canRedo: Bool { redoCount > 0 }
    public var canReset: Bool { edits != .original }

    public var canExport: Bool {
        image != nil && isReadyForEditing && !exportState.isBusy
    }

    public var isRendering: Bool { renderState.isRendering }

    public var isPerformanceDegraded: Bool { performanceLevel.isDegraded }

    public var availableAreas: [EditorToolArea] {
        EditorToolArea.allCases.filter { $0.isAvailable(in: analysis) }
    }

    public var selectedAdjustments: [EditorAdjustment] {
        EditorAdjustment.all(in: selectedArea)
    }

    public var selectedAreaIsAvailable: Bool {
        isReadyForEditing && selectedArea.isAvailable(in: analysis)
    }

    public var currentPlan: EditorRenderPlan? {
        guard let analysis else { return nil }
        return EditorRenderPlan.make(style: style, analysis: analysis, edits: edits)
    }

    /// All warnings that should be visible now, deduplicated and in a stable
    /// order: analysis first, then the background-risk note, then engine
    /// warnings from the last successful render.
    public var warnings: [EditorWarning] {
        var groups: [[EditorWarning]] = []

        if let analysis {
            var sceneWarnings = analysis.warnings.map { EditorWarning.from($0) }
            if !analysis.hasFace, !sceneWarnings.contains(where: { $0.kind == .noFace }) {
                sceneWarnings.append(EditorWarning.from(AnalysisWarning.noFace))
            }
            if !analysis.hasBody, !sceneWarnings.contains(where: { $0.kind == .noBody }) {
                sceneWarnings.append(EditorWarning.from(AnalysisWarning.noBody))
            }
            groups.append(sceneWarnings)
        }

        if let plan = currentPlan, plan.shouldWarp, !plan.backgroundProtection {
            groups.append([.backgroundRisk])
        }

        // Background risk is derived from the current plan above, so an older
        // render result must not keep the warning alive after protection is
        // switched back on.
        groups.append(renderWarnings.filter { $0.kind != .backgroundRisk })
        return EditorWarning.merge(groups)
    }

    public func isAdjustmentEnabled(_ adjustment: EditorAdjustment) -> Bool {
        canEdit && adjustment.area.isAvailable(in: analysis)
    }

    // MARK: Lifecycle

    /// Loads a photo and starts analysis. Replaces any previous session and
    /// cancels every in-flight render.
    public func load(image: ImageAsset) async {
        sessionID = UUID()
        let token = sessionID

        pipeline.cancelAll()
        renderGeneration += 1

        self.image = image
        self.analysis = nil
        self.style = .editorNaturalDefault
        self.edits = .initial
        self.displayedImage = image
        self.displayedQuality = .full
        self.renderState = .ready(.full)
        self.renderWarnings = []
        self.issue = nil
        self.pendingBackgroundProtectionDisable = false
        self.exportState = .idle
        self.lastExport = nil
        self.lastExportOptions = nil
        self.lastRenderDuration = nil
        self.lastFullRenderedEdits = nil
        self.isShowingOriginal = false
        self.isSplitComparisonEnabled = false
        self.splitPosition = 0.5
        self.zoom = EditorZoomState()
        self.governor.reset()
        self.performanceLevel = .full
        self.selectedArea = .face
        self.history.clear()
        self.syncHistoryCounts()
        self.interactionBaseline = nil
        self.isInteracting = false
        self.isAnalyzing = true
        self.isReadyForEditing = false
        self.hasLoaded = true

        await analyze(image: image, token: token, isRetry: false)
    }

    /// Alias that reads naturally at call sites that start a new session.
    public func start(image: ImageAsset) async {
        await load(image: image)
    }

    /// Retries only the analysis, keeping the current edit state.
    public func retryAnalysis() async {
        guard let image, !isAnalyzing else { return }
        issue = nil
        isAnalyzing = true
        isReadyForEditing = false
        await analyze(image: image, token: sessionID, isRetry: true)
    }

    /// Reloads the active style and re-renders.
    public func reloadStyle() async {
        guard !isLoadingStyle else { return }
        issue = nil
        await loadStyle(token: sessionID)
        guard isReadyForEditing else { return }
        scheduleFullRender()
    }

    public func dismissIssue() {
        issue = nil
    }

    /// Performs the recovery attached to the current issue.
    public func recover() async {
        guard let issue, let recovery = issue.recovery else {
            dismissIssue()
            return
        }
        dismissIssue()

        switch recovery {
        case .retryAnalysis:
            await retryAnalysis()
        case .retryRender:
            scheduleFullRender()
        case .reloadStyle:
            await reloadStyle()
        case .retryExport:
            if let options = lastExportOptions {
                _ = try? await export(options: options)
            }
        }
    }

    // MARK: Editing

    /// Called when a slider gesture begins. All changes until
    /// `endInteraction()` become one undo step.
    public func beginInteraction() {
        guard canEdit else { return }
        if interactionBaseline == nil {
            interactionBaseline = edits
        }
        isInteracting = true
    }

    /// Called when a slider gesture ends: commits one history entry and asks
    /// for a full-quality render.
    public func endInteraction() {
        guard isInteracting else { return }
        isInteracting = false
        commitInteractionBaseline()
        scheduleFullRender()
    }

    /// Cancels the current gesture and restores its starting state.
    public func cancelInteraction() {
        guard isInteracting else { return }
        isInteracting = false
        if let baseline = interactionBaseline, baseline != edits {
            edits = baseline
            scheduleFullRender()
        }
        interactionBaseline = nil
    }

    public func setAdjustment(_ adjustment: EditorAdjustment, to value: Double) {
        guard isAdjustmentEnabled(adjustment) else { return }
        var next = edits
        adjustment.set(value, in: &next.adjustments)
        commit(next, record: true, render: .automatic)
    }

    public func setStrength(_ value: Double) {
        guard canEdit else { return }
        var next = edits
        next.setStrength(value)
        commit(next, record: true, render: .automatic)
    }

    /// One-tap natural look: a conservative 70 % total strength.
    public func applyNaturalPreset() {
        guard canEdit else { return }
        finalizeInteractionIfNeeded()
        var next = edits
        next.setStrength(EditorEditState.naturalStrength)
        commit(next, record: true, render: .full)
    }

    // MARK: Background protection

    /// Requests a protection change. Turning protection off requires a second
    /// confirmation because it can bend straight lines.
    public func requestBackgroundProtection(_ enabled: Bool) {
        guard canEdit else { return }
        if enabled {
            pendingBackgroundProtectionDisable = false
            applyBackgroundProtection(true)
        } else if edits.backgroundProtection {
            pendingBackgroundProtectionDisable = true
        }
    }

    public func confirmBackgroundProtectionDisable() {
        guard pendingBackgroundProtectionDisable else { return }
        pendingBackgroundProtectionDisable = false
        applyBackgroundProtection(false)
    }

    public func cancelBackgroundProtectionDisable() {
        pendingBackgroundProtectionDisable = false
    }

    // MARK: Blemish points

    public func addBlemishPoint(at point: NormalizedPoint, radius: Double = 0.02) {
        guard canEdit else { return }
        finalizeInteractionIfNeeded()
        var next = edits
        guard next.addBlemishPoint(point, radius: radius) else { return }
        commit(next, record: true, render: .full)
    }

    public func removeLastBlemishPoint() {
        guard canEdit else { return }
        finalizeInteractionIfNeeded()
        var next = edits
        guard next.removeLastBlemishPoint() else { return }
        commit(next, record: true, render: .full)
    }

    public func clearBlemishPoints() {
        guard canEdit else { return }
        finalizeInteractionIfNeeded()
        var next = edits
        guard !next.blemishPoints.isEmpty else { return }
        next.blemishPoints.removeAll()
        commit(next, record: true, render: .full)
    }

    // MARK: Undo, redo, reset

    public func undo() {
        finalizeInteractionIfNeeded()
        guard let previous = history.undo(current: edits) else { return }
        syncHistoryCounts()
        edits = previous
        scheduleFullRender()
    }

    public func redo() {
        finalizeInteractionIfNeeded()
        guard let next = history.redo(current: edits) else { return }
        syncHistoryCounts()
        edits = next
        scheduleFullRender()
    }

    /// Resets to the original image. Strength is set to 0 so neither the style
    /// baseline nor manual offsets apply; the active style is not discarded and
    /// can be brought back by raising the strength slider.
    public func reset() {
        guard canEdit else { return }
        finalizeInteractionIfNeeded()
        guard edits != .original else { return }
        history.record(edits)
        syncHistoryCounts()
        edits = .original
        scheduleFullRender()
    }

    // MARK: Tools

    public func selectArea(_ area: EditorToolArea) {
        guard area.isAvailable(in: analysis) else { return }
        selectedArea = area
    }

    // MARK: Comparison and zoom

    public func setShowingOriginal(_ showing: Bool) {
        isShowingOriginal = showing
    }

    public func toggleSplitComparison() {
        isSplitComparisonEnabled.toggle()
    }

    public func setSplitPosition(_ value: Double) {
        guard value.isFinite else { return }
        splitPosition = min(max(value, 0.05), 0.95)
    }

    public func setZoomScale(_ scale: Double) {
        zoom.setScale(scale)
    }

    public func magnify(by factor: Double) {
        zoom.magnify(by: factor)
    }

    public func panBy(x: Double, y: Double) {
        zoom.pan(dx: x, dy: y)
    }

    public func resetZoom() {
        zoom.reset()
    }

    public func toggleZoom() {
        if zoom.isZoomed {
            zoom.reset()
        } else {
            zoom.setScale(2.0)
        }
    }

    // MARK: Rendering

    public func retryRender() {
        issue = nil
        scheduleFullRender()
    }

    /// Cancels queued and in-flight renders, keeping the last committed image.
    public func cancelRendering() {
        pipeline.cancelAll()
        if case .rendering(_) = renderState {
            renderState = .ready(displayedQuality)
        }
    }

    /// Awaits the queue becoming empty; used by tests and before export.
    public func waitForRenderIdle() async {
        await pipeline.waitForIdle()
    }

    // MARK: Export

    /// Renders the current state at full resolution (or reuses the committed
    /// full-quality image) and hands the result to `ImageExporting`.
    ///
    /// A canceled or failed render never reaches the exporter, so a partial
    /// image cannot be written. The exporter owns temp-file cleanup.
    @discardableResult
    public func export(options: ExportOptions = ExportOptions()) async throws -> ExportResult {
        guard let image, isReadyForEditing, !exportState.isBusy else {
            throw StyleToneError.invalidState
        }

        lastExportOptions = options
        if issue?.recovery == .retryExport {
            issue = nil
        }
        exportState = .preparing
        pipeline.cancelAll()
        await pipeline.waitForIdle()

        do {
            try Task.checkCancellation()
        } catch {
            exportState = .idle
            throw StyleToneError.cancelled
        }

        let resolvedAnalysis = analysis ?? PortraitAnalysis.empty(imageSize: image.pixelSize)
        let plan = EditorRenderPlan.make(style: style, analysis: resolvedAnalysis, edits: edits)
        let output: ImageAsset

        if plan.isNoOp {
            output = image
        } else if displayedQuality == .full,
                  renderState == .ready(.full),
                  lastFullRenderedEdits == edits,
                  let displayed = displayedImage {
            output = displayed
        } else {
            do {
                let rendered = try await dependencies.renderer.render(
                    makeRequest(image: image, analysis: resolvedAnalysis)
                )
                try Task.checkCancellation()
                output = rendered.image
            } catch is CancellationError {
                exportState = .idle
                throw StyleToneError.cancelled
            } catch {
                let mapped = Self.renderError(error)
                exportState = .failed
                issue = EditorIssue(
                    error: AppError.map(mapped, diagnosticCode: "ST-EDITOR-EXPORT-RENDER"),
                    recovery: .retryRender
                )
                dependencies.logger.log(
                    .error,
                    "editor.export.render.failed",
                    metadata: ["code": mapped.code]
                )
                throw mapped
            }
        }

        exportState = .exporting
        do {
            try Task.checkCancellation()
            let result = try await dependencies.exporter.export(output, options: options)
            try Task.checkCancellation()
            exportState = .completed
            lastExport = result
            return result
        } catch is CancellationError {
            exportState = .idle
            throw StyleToneError.cancelled
        } catch {
            let mapped = Self.exportError(error)
            exportState = .failed
            issue = EditorIssue(
                error: AppError.map(mapped, diagnosticCode: "ST-EDITOR-EXPORT"),
                recovery: .retryExport
            )
            dependencies.logger.log(
                .error,
                "editor.export.failed",
                metadata: ["code": mapped.code]
            )
            throw mapped
        }
    }

    // MARK: - Private: analysis and style

    private func analyze(image: ImageAsset, token: UUID, isRetry: Bool) async {
        do {
            let result = try await dependencies.analyzer.analyze(image)
            guard token == sessionID else { return }

            analysis = result
            isAnalyzing = false
            await loadStyle(token: token)
            guard token == sessionID else { return }

            isReadyForEditing = true
            selectDefaultAreaIfNeeded()
            if isRetry {
                scheduleFullRender()
            } else {
                renderCurrentStateIfNeeded()
            }
        } catch is CancellationError {
            if token == sessionID {
                isAnalyzing = false
            }
        } catch {
            guard token == sessionID else { return }

            analysis = PortraitAnalysis.empty(imageSize: image.pixelSize)
            isAnalyzing = false
            issue = EditorIssue(
                error: AppError.map(Self.analysisError(error), diagnosticCode: "ST-EDITOR-ANALYZE"),
                recovery: .retryAnalysis
            )
            await loadStyle(token: token)
            guard token == sessionID else { return }
            isReadyForEditing = true
            selectDefaultAreaIfNeeded()
            // Keep the original on screen. Rendering with an empty analysis is
            // possible for tone only, but the user should see the issue first.
        }
    }

    private func loadStyle(token: UUID) async {
        isLoadingStyle = true
        defer { isLoadingStyle = false }

        do {
            let loaded = try await dependencies.styleProvider.activeStyle()
            guard token == sessionID else { return }
            style = loaded
        } catch is CancellationError {
            return
        } catch {
            guard token == sessionID else { return }
            style = .editorNaturalDefault
            if issue == nil {
                issue = EditorIssue(
                    error: AppError.map(.persistenceFailed, diagnosticCode: "ST-EDITOR-STYLE"),
                    recovery: .reloadStyle
                )
            }
        }
    }

    private func selectDefaultAreaIfNeeded() {
        if !selectedArea.isAvailable(in: analysis) {
            selectedArea = availableAreas.first ?? .tone
        }
    }

    private func renderCurrentStateIfNeeded() {
        guard let plan = currentPlan else { return }
        if plan.isNoOp {
            pipeline.cancelAll()
            displayedImage = image
            displayedQuality = .full
            renderState = .ready(.full)
            renderWarnings = []
            return
        }
        scheduleFullRender()
    }

    // MARK: - Private: scheduling

    private func schedulePreview() {
        guard let image, let analysis, isReadyForEditing else { return }
        let plan = EditorRenderPlan.make(style: style, analysis: analysis, edits: edits)
        renderGeneration += 1
        let generation = renderGeneration

        if plan.isNoOp {
            pipeline.cancelAll()
            displayedImage = image
            displayedQuality = .full
            renderState = .ready(.full)
            renderWarnings = []
            return
        }

        let request = makeRequest(image: image, analysis: analysis)
        renderState = .rendering(.preview)
        let job = EditorRenderJob(
            id: generation,
            quality: .preview,
            request: request,
            previewLongEdge: governor.previewLongEdge
        )
        pipeline.submit(job, cancelActive: false)
    }

    private func scheduleFullRender() {
        guard let image, let analysis, isReadyForEditing else { return }
        let plan = EditorRenderPlan.make(style: style, analysis: analysis, edits: edits)
        renderGeneration += 1
        let generation = renderGeneration

        if plan.isNoOp {
            pipeline.cancelAll()
            displayedImage = image
            displayedQuality = .full
            renderState = .ready(.full)
            renderWarnings = []
            lastFullRenderedEdits = edits
            return
        }

        let request = makeRequest(image: image, analysis: analysis)
        renderState = .rendering(.full)
        let job = EditorRenderJob(
            id: generation,
            quality: .full,
            request: request,
            previewLongEdge: 0
        )
        pipeline.submit(job, cancelActive: true)
    }

    private func receive(_ completion: EditorRenderCompletion) {
        guard completion.jobID == renderGeneration else { return }

        switch completion.outcome {
        case let .success(output):
            displayedImage = output.image
            displayedQuality = completion.quality
            renderState = .ready(completion.quality)
            lastRenderDuration = output.duration
            renderWarnings = output.warnings.map { EditorWarning.from($0) }

            if completion.quality == .preview {
                governor.record(duration: output.duration, quality: .preview)
                performanceLevel = governor.level
            } else {
                lastFullRenderedEdits = edits
            }

            if issue?.recovery == .retryRender {
                issue = nil
            }
        case .cancelled:
            // The previous committed image stays on screen. Never commit a
            // partially rendered result.
            if case .rendering(_) = renderState {
                renderState = .ready(displayedQuality)
            }
        case let .failure(error):
            renderState = .failed
            issue = EditorIssue(
                error: AppError.map(error, diagnosticCode: "ST-EDITOR-RENDER"),
                recovery: .retryRender
            )
            dependencies.logger.log(
                .error,
                "editor.render.failed",
                metadata: ["code": error.code]
            )
        }
    }

    private func makeRequest(image: ImageAsset, analysis: PortraitAnalysis) -> RenderRequest {
        RenderRequest(
            image: image,
            analysis: analysis,
            style: style,
            strength: edits.strength,
            adjustments: edits.adjustments,
            backgroundProtection: edits.backgroundProtection,
            blemishPoints: edits.blemishPoints
        )
    }

    // MARK: - Private: edit helpers

    private func commit(_ next: EditorEditState, record: Bool, render: RenderMode) {
        guard next != edits else { return }

        if record && !isInteracting {
            history.record(edits)
            syncHistoryCounts()
        }
        edits = next

        switch render {
        case .automatic:
            if isInteracting {
                schedulePreview()
            } else {
                scheduleFullRender()
            }
        case .full:
            scheduleFullRender()
        }
    }

    private func finalizeInteractionIfNeeded() {
        guard isInteracting else { return }
        isInteracting = false
        commitInteractionBaseline()
    }

    private func commitInteractionBaseline() {
        if let baseline = interactionBaseline, baseline != edits {
            history.record(baseline)
            syncHistoryCounts()
        }
        interactionBaseline = nil
    }

    private func applyBackgroundProtection(_ enabled: Bool) {
        finalizeInteractionIfNeeded()
        var next = edits
        next.backgroundProtection = enabled
        commit(next, record: true, render: .full)
    }

    private func syncHistoryCounts() {
        undoCount = history.undoCount
        redoCount = history.redoCount
    }

    private static func renderError(_ error: Error) -> StyleToneError {
        if let error = error as? StyleToneError {
            return error
        }
        if error is CancellationError {
            return .cancelled
        }
        return .renderingFailed
    }

    private static func analysisError(_ error: Error) -> StyleToneError {
        if let error = error as? StyleToneError {
            return error
        }
        if error is CancellationError {
            return .cancelled
        }
        return .imageAnalysisFailed
    }

    private static func exportError(_ error: Error) -> StyleToneError {
        if let error = error as? StyleToneError {
            return error
        }
        if error is CancellationError {
            return .cancelled
        }
        return .exportFailed
    }
}
