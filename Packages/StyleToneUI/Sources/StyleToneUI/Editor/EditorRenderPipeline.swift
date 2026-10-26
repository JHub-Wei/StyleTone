import Foundation
import StyleToneCore

// MARK: - Job and completion

public struct EditorRenderJob: Sendable {
    public let id: Int
    public let quality: EditorRenderQuality
    public let request: RenderRequest
    /// Proxy long edge; ignored for full-quality jobs.
    public let previewLongEdge: Int

    public init(
        id: Int,
        quality: EditorRenderQuality,
        request: RenderRequest,
        previewLongEdge: Int
    ) {
        self.id = id
        self.quality = quality
        self.request = request
        self.previewLongEdge = previewLongEdge
    }
}

public enum EditorRenderOutcome: Sendable {
    case success(RenderOutput)
    case cancelled
    case failure(StyleToneError)
}

public struct EditorRenderCompletion: Sendable {
    public let jobID: Int
    public let quality: EditorRenderQuality
    public let outcome: EditorRenderOutcome

    public init(jobID: Int, quality: EditorRenderQuality, outcome: EditorRenderOutcome) {
        self.jobID = jobID
        self.quality = quality
        self.outcome = outcome
    }
}

// MARK: - Pipeline

/// Main-actor render queue with latest-wins semantics.
///
/// Only one render task runs at a time. While it runs, newer previews replace
/// the pending job instead of piling up. A full-quality submit cancels the
/// in-flight job; its completion is discarded because it is no longer the
/// latest. This gives three guarantees:
///
/// - the main actor never blocks on pixel work (the engines are async actors);
/// - a stale preview can never overwrite a newer image;
/// - creating a new image or leaving the screen cancels everything.
@MainActor
public final class EditorRenderPipeline {
    public typealias Handler = @MainActor (EditorRenderCompletion) -> Void

    private let renderer: any ImageRendering
    private let previewPreparer: any EditorPreviewPreparing
    private let handler: Handler

    private var pendingJob: EditorRenderJob?
    private var activeJob: EditorRenderJob?
    private var activeTask: Task<EditorRenderOutcome, Never>?
    private var worker: Task<Void, Never>?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var latestSubmittedID = 0
    private var deliveryEnabled = true

    public init(
        renderer: any ImageRendering,
        previewPreparer: any EditorPreviewPreparing = EditorPreviewPreparer(),
        handler: @escaping Handler
    ) {
        self.renderer = renderer
        self.previewPreparer = previewPreparer
        self.handler = handler
    }

    public var isRendering: Bool {
        activeJob != nil || pendingJob != nil
    }

    public var activeQuality: EditorRenderQuality? {
        activeJob?.quality
    }

    /// Queues the latest job.
    ///
    /// - Parameter cancelActive: pass `true` when a full-quality render
    ///   supersedes a proxy. Preview ticks pass `false` so a slow device still
    ///   produces frames instead of restarting on every tick.
    public func submit(_ job: EditorRenderJob, cancelActive: Bool = false) {
        latestSubmittedID = max(latestSubmittedID, job.id)
        deliveryEnabled = true
        pendingJob = job
        if cancelActive {
            activeTask?.cancel()
        }
        startWorkerIfNeeded()
    }

    /// Drops queued work and requests cancellation of the active render. A
    /// cooperative renderer unwinds quickly; one that ignores cancellation is
    /// allowed to finish, but its result is never delivered.
    public func cancelAll() {
        pendingJob = nil
        deliveryEnabled = false
        activeTask?.cancel()
        if activeTask == nil {
            finishIfIdle()
        }
    }

    /// Awaits the queue becoming empty. Tests and export use this instead of
    /// sleeping.
    public func waitForIdle() async {
        if worker == nil {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            idleWaiters.append(continuation)
        }
    }

    // MARK: - Private

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            await self.drain()
        }
    }

    private func drain() async {
        while let job = pendingJob {
            pendingJob = nil
            activeJob = job

            let renderer = self.renderer
            let preparer = self.previewPreparer
            let task = Task {
                await EditorRenderPipeline.perform(
                    job,
                    renderer: renderer,
                    previewPreparer: preparer
                )
            }
            activeTask = task

            let outcome = await task.value
            activeTask = nil
            activeJob = nil

            let shouldDeliver = deliveryEnabled && job.id == latestSubmittedID
            if shouldDeliver {
                handler(
                    EditorRenderCompletion(
                        jobID: job.id,
                        quality: job.quality,
                        outcome: outcome
                    )
                )
            }
        }

        worker = nil
        resumeIdleWaiters()
    }

    private func finishIfIdle() {
        guard worker == nil else { return }
        resumeIdleWaiters()
    }

    private func resumeIdleWaiters() {
        guard worker == nil, pendingJob == nil, activeJob == nil else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    nonisolated private static func perform(
        _ job: EditorRenderJob,
        renderer: any ImageRendering,
        previewPreparer: any EditorPreviewPreparing
    ) async -> EditorRenderOutcome {
        do {
            try Task.checkCancellation()

            var request = job.request
            if job.quality == .preview {
                let context = try await previewPreparer.preparePreview(
                    image: request.image,
                    analysis: request.analysis,
                    maximumLongEdge: job.previewLongEdge
                )
                request = RenderRequest(
                    image: context.image,
                    analysis: context.analysis,
                    style: request.style,
                    strength: request.strength,
                    adjustments: request.adjustments,
                    backgroundProtection: request.backgroundProtection,
                    blemishPoints: request.blemishPoints
                )
            }

            try Task.checkCancellation()
            let output = try await renderer.render(request)
            try Task.checkCancellation()
            return .success(output)
        } catch is CancellationError {
            return .cancelled
        } catch let error as StyleToneError {
            return error.isCancellation ? .cancelled : .failure(error)
        } catch {
            return .failure(.renderingFailed)
        }
    }
}
