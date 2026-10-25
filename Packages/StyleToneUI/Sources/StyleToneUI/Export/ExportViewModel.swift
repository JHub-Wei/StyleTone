import Foundation
import Observation
import StyleToneCore

/// State and actions behind the export sheet.
///
/// One export attempt renders the full-resolution request (WP-17), encodes it
/// with `ImageExporting` (WP-02), then either saves the very same file through
/// the add-only photo library or hands it to the system share sheet. The staged
/// file is deleted on every terminal path. The free-export counter is written
/// only after the system confirms delivery, so failures and cancellations never
/// consume a free export.
@MainActor
@Observable
public final class ExportViewModel {
    // MARK: Observable state

    public private(set) var stage: ExportStage = .idle
    public private(set) var progress: ExportProgress?
    public private(set) var failure: ExportFailure?
    public private(set) var outcome: ExportOutcome?
    public private(set) var infoNotice: ExportText?
    public private(set) var authorization: PhotoLibraryAccess = .notDetermined
    public private(set) var entitlement: ExportEntitlement = .unlimited
    public private(set) var quotaLoadFailed = false
    public private(set) var hasLoaded = false
    public private(set) var timings: ExportTimings?
    public private(set) var lastDestination: ExportDestination?

    /// Format and quality choices; mutating them is ignored while work is busy.
    public var settings: ExportSettings

    /// The share request the screen presents; cleared by the sheet completion.
    public var pendingShare: ExportShareRequest?

    // MARK: Private state

    private let source: ExportSource
    private let dependencies: ExportDependencies
    private let fileStore: ExportTemporaryFileStore
    private var stagedFile: ExportStagedFile?
    /// Correlation token for the share completion.
    ///
    /// `pendingShare` is also the SwiftUI sheet item, so SwiftUI writes `nil`
    /// into it when the sheet dismisses. The completion handler must not depend
    /// on that value surviving the dismissal; this token is cleared only by the
    /// completion/cancel/close paths.
    private var activeShareRequest: ExportShareRequest?
    private var activeTask: Task<Void, Never>?
    private var isStarting = false
    private var renderDuration: TimeInterval = 0
    private var encodeDuration: TimeInterval = 0

    public init(
        source: ExportSource,
        dependencies: ExportDependencies = .placeholder,
        settings: ExportSettings = ExportSettings()
    ) {
        self.source = source
        self.dependencies = dependencies
        self.settings = settings
        self.fileStore = dependencies.fileStore
    }

    // MARK: - Derived UI state

    public var isBusy: Bool { stage.isBusy }

    public var canExport: Bool {
        hasLoaded
            && !isBusy
            && activeTask == nil
            && !quotaLoadFailed
            && entitlement.canExport
            && source.expectedPixelSize.isPositive
    }

    public var canSaveToLibrary: Bool {
        guard canExport else { return false }
        switch authorization {
        case .notDetermined, .authorized, .limited:
            return true
        case .denied, .restricted, .unavailable:
            return false
        }
    }

    public var canShare: Bool {
        canExport && dependencies.supportsSystemShare
    }

    public var supportsSystemShare: Bool {
        dependencies.supportsSystemShare
    }

    public var canCancel: Bool {
        switch stage {
        case .preparing, .requestingAccess, .rendering, .encoding:
            return true
        case .savingToLibrary, .awaitingShare, .idle, .finished, .failed, .cancelled:
            return false
        }
    }

    public var isCloseEnabled: Bool {
        stage != .savingToLibrary
    }

    public var isQuotaExhausted: Bool {
        hasLoaded && !quotaLoadFailed && entitlement.isExhausted
    }

    public var canRetry: Bool {
        (stage == .failed || stage == .cancelled) && lastDestination != nil
    }

    public var expectedPixelSize: PixelSize { source.expectedPixelSize }

    public var previewImage: ImageAsset { source.previewImage }

    public var previewAspectRatio: Double { source.aspectRatio }

    public var isLargeImage: Bool { source.isLargeImage }

    public var pixelSizeText: String {
        ExportCopy.pixelSizeText(source.expectedPixelSize)
    }

    public var megapixelsText: String {
        ExportCopy.megapixelsText(source.megapixels)
    }

    public var stageText: String {
        ExportCopy.progressText(stage).text
    }

    public var progressPercentText: String {
        "\(progress?.percent ?? 0)%"
    }

    public var format: ExportFormat {
        get { settings.format }
        set {
            guard !isBusy else { return }
            settings.format = newValue
        }
    }

    public var quality: ExportQuality {
        get { settings.quality }
        set {
            guard !isBusy else { return }
            settings.quality = newValue
        }
    }

    public var quotaText: String? {
        guard hasLoaded, !quotaLoadFailed else { return nil }
        switch entitlement {
        case .unlimited:
            return ExportCopy.quotaUnlimited.text
        case let .free(remaining):
            guard remaining > 0 else {
                return ExportCopy.quotaExhausted.text
            }
            return ExportCopy.quotaText(remaining: remaining)
        case .exhausted:
            return ExportCopy.quotaExhausted.text
        }
    }

    public var outcomeTitle: ExportText {
        outcome?.destination == .share
            ? ExportCopy.outcomeSharedTitle
            : ExportCopy.outcomeSavedTitle
    }

    public var outcomeMessage: ExportText {
        outcome?.destination == .share
            ? ExportCopy.outcomeSharedMessage
            : ExportCopy.outcomeSavedMessage
    }

    public var outcomeDetailText: String? {
        guard let outcome else { return nil }
        let formatName = ExportCopy.formatTitle(outcome.format).text
        let pixels = ExportCopy.pixelSizeText(outcome.pixelSize)
        let size = ExportCopy.fileSizeText(bytes: outcome.byteCount)
        return [formatName, pixels, size].joined(separator: " · ")
    }

    public var outcomeCountPending: Bool {
        outcome?.counted == false
    }

    // MARK: - Lifecycle

    /// Loads permission state and the entitlement once.
    public func start() async {
        guard !hasLoaded, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        cleanupStaleFiles()
        authorization = await dependencies.photoLibrary.authorizationStatus()
        await refreshEntitlement()
        hasLoaded = true
    }

    /// Re-reads the add-only authorization status, e.g. after returning from
    /// Settings. The screen calls this when the scene becomes active.
    public func refreshAuthorization() async {
        authorization = await dependencies.photoLibrary.authorizationStatus()
    }

    /// Re-reads the entitlement; used by the quota-retry action.
    public func refreshEntitlement() async {
        do {
            entitlement = try await dependencies.quota.entitlement()
            quotaLoadFailed = false
            if failure?.kind == .quotaUnavailable {
                failure = nil
                if stage == .failed {
                    stage = .idle
                }
                progress = nil
            }
        } catch {
            quotaLoadFailed = true
            dependencies.logger.log(
                .warning,
                "export entitlement unavailable",
                metadata: ["code": "E_QUOTA_READ"]
            )
        }
    }

    // MARK: - Actions

    /// Runs the pipeline and saves the encoded file to Photos.
    public func saveToLibrary() {
        begin(.photoLibrary)
    }

    /// Runs the pipeline and presents the system share sheet.
    public func share() {
        guard dependencies.supportsSystemShare else {
            presentFailure(ExportFailure.make(kind: .shareUnavailable, stage: .preparing))
            return
        }
        begin(.share)
    }

    /// Retry after a failure or a cancellation.
    ///
    /// When only the library save failed, the already-encoded file is saved
    /// again instead of rendering/encoding a second time. Every other failure
    /// starts a fresh attempt with the same source and settings.
    public func retry() {
        guard !isBusy, activeTask == nil, hasLoaded else { return }
        guard stage == .failed || stage == .cancelled else { return }
        guard let destination = lastDestination else { return }

        if destination == .photoLibrary,
           let file = stagedFile,
           fileStore.fileExists(at: file.url),
           failure?.stage == .savingToLibrary {
            failure = nil
            infoNotice = nil
            outcome = nil
            setProgress(.preparing, 0.02)
            activeTask = Task { [weak self] in
                guard let self else { return }
                await self.retrySave(file)
            }
            return
        }

        failure = nil
        outcome = nil
        begin(destination)
    }

    /// Reuses the staged file for sharing after a save/permission failure; if
    /// no file survived, starts a fresh share export.
    public func shareInstead() {
        guard !isBusy, activeTask == nil, hasLoaded else { return }
        guard dependencies.supportsSystemShare else {
            presentFailure(ExportFailure.make(kind: .shareUnavailable, stage: stage))
            return
        }

        failure = nil
        outcome = nil
        infoNotice = nil
        lastDestination = .share

        if let file = stagedFile, fileStore.fileExists(at: file.url) {
            let request = ExportShareRequest(file: file)
            activeShareRequest = request
            pendingShare = request
            setProgress(.awaitingShare, 0.94)
            return
        }

        begin(.share)
    }

    /// Called by the share sheet exactly once when it finishes.
    public func completeShare(_ request: ExportShareRequest, completed: Bool) async {
        // Do not guard on `pendingShare`: SwiftUI clears the sheet item when the
        // controller dismisses, which can happen before this task runs.
        guard activeShareRequest?.id == request.id, let file = stagedFile else { return }
        activeShareRequest = nil
        pendingShare = nil

        if completed {
            let current = timings ?? ExportTimings(
                render: renderDuration,
                encode: encodeDuration,
                save: 0,
                total: renderDuration + encodeDuration
            )
            await finishSuccess(destination: .share, file: file, timings: current)
        } else {
            cleanupStagedFile()
            failure = nil
            outcome = nil
            progress = nil
            stage = .idle
            infoNotice = ExportCopy.shareCancelled
        }
    }

    /// Cancels work that has not been handed to PhotoKit/the share sheet yet.
    ///
    /// A library save is not cancellable once PhotoKit starts it: the photo may
    /// already be added, so the flow waits for the result and counts it. The
    /// screen hides the cancel button during that stage.
    public func cancel() {
        guard isBusy else { return }

        switch stage {
        case .awaitingShare:
            activeShareRequest = nil
            pendingShare = nil
            cleanupStagedFile()
            failure = nil
            outcome = nil
            progress = nil
            stage = .cancelled
        case .savingToLibrary:
            return
        default:
            activeTask?.cancel()
            cleanupStagedFile()
            failure = nil
            outcome = nil
            progress = nil
            stage = .cancelled
        }
    }

    /// Dismisses a failure and deletes any file kept for "Share instead".
    public func dismissFailure() {
        activeShareRequest = nil
        cleanupStagedFile()
        failure = nil
        if stage == .failed {
            stage = .idle
            progress = nil
        }
    }

    public func dismissInfoNotice() {
        infoNotice = nil
    }

    /// App-level fallback when the export screen goes away while the share item
    /// is already dismissed but its completion never arrived.
    ///
    /// Without this, the model would stay `.awaitingShare` forever (Save/Share
    /// disabled, Cancel hidden) and the staged file would only die in the stale
    /// sweep. A still-visible share sheet has a non-nil `pendingShare` and is
    /// therefore not abandoned here.
    public func abandonShareIfPending() {
        guard stage == .awaitingShare, pendingShare == nil else { return }
        activeShareRequest = nil
        cleanupStagedFile()
        failure = nil
        outcome = nil
        progress = nil
        stage = .idle
        infoNotice = ExportCopy.shareCancelled
    }

    /// Cleans up before the sheet closes. A save already handed to PhotoKit is
    /// allowed to finish (its task owns cleanup). A share awaiting its
    /// completion is also left alone so the completion can still count it;
    /// dismissing the share sheet routes through `completeShare`.
    public func prepareForClose() {
        guard stage != .savingToLibrary, stage != .awaitingShare else { return }
        activeTask?.cancel()
        activeTask = nil
        pendingShare = nil
        activeShareRequest = nil
        cleanupStagedFile()
        failure = nil
        outcome = nil
        infoNotice = nil
        progress = nil
        stage = .idle
    }

    /// Waits for the active attempt. Intended for host integration and tests;
    /// a pending share sheet is not waited on (the user owns that time).
    ///
    /// A single await is deliberate: a previous attempt may already have
    /// completed while the model is still unwinding, and looping on a stale
    /// completed task would spin forever.
    public func waitForCompletion() async {
        await activeTask?.value
    }

    // MARK: - Pipeline

    private func begin(_ destination: ExportDestination) {
        guard !isBusy, activeTask == nil, hasLoaded else { return }

        guard source.expectedPixelSize.isPositive else {
            presentFailure(ExportFailure.make(kind: .invalidImage, stage: .preparing))
            return
        }
        guard !quotaLoadFailed else {
            presentFailure(ExportFailure.make(kind: .quotaUnavailable, stage: .preparing))
            return
        }
        guard entitlement.canExport else {
            presentFailure(ExportFailure.make(kind: .quotaExhausted, stage: .preparing))
            return
        }

        failure = nil
        outcome = nil
        infoNotice = nil
        pendingShare = nil
        activeShareRequest = nil
        cleanupStagedFile()
        renderDuration = 0
        encodeDuration = 0
        timings = nil
        lastDestination = destination
        setProgress(.preparing, 0.02)

        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.run(destination: destination)
        }
    }

    private func run(destination: ExportDestination) async {
        defer { activeTask = nil }

        do {
            try Task.checkCancellation()

            if destination == .photoLibrary {
                setProgress(.requestingAccess, 0.05)
                let access = await resolveLibraryAccess()
                try Task.checkCancellation()
                try Self.requireAddAccess(access)
            }

            setProgress(.rendering, 0.10)
            let renderStart = now
            let output = try await dependencies.renderer.render(source.request)
            renderDuration = max(0, now.timeIntervalSince(renderStart))
            try Task.checkCancellation()

            guard output.image.pixelSize == source.expectedPixelSize else {
                throw ExportPipelineError.resolutionMismatch(
                    expected: source.expectedPixelSize,
                    actual: output.image.pixelSize
                )
            }
            setProgress(.rendering, 0.60)
            setProgress(.encoding, 0.62)
            fileStore.prepareDirectoryForExport()

            let encodeStart = now
            let exported = try await dependencies.exporter.export(
                output.image,
                options: settings.options
            )
            encodeDuration = max(0, now.timeIntervalSince(encodeStart))

            if Task.isCancelled {
                _ = fileStore.remove(exported.url)
                throw CancellationError()
            }

            let file = makeStagedFile(exported)
            stagedFile = file
            try validate(exported)
            timings = ExportTimings(
                render: renderDuration,
                encode: encodeDuration,
                save: 0,
                total: renderDuration + encodeDuration
            )

            switch destination {
            case .photoLibrary:
                setProgress(.savingToLibrary, 0.94)
                let saveStart = now
                try await dependencies.photoLibrary.save(file)
                let saveDuration = max(0, now.timeIntervalSince(saveStart))
                let total = ExportTimings(
                    render: renderDuration,
                    encode: encodeDuration,
                    save: saveDuration,
                    total: renderDuration + encodeDuration + saveDuration
                )
                await finishSuccess(destination: .photoLibrary, file: file, timings: total)

            case .share:
                setProgress(.awaitingShare, 0.94)
                let request = ExportShareRequest(file: file)
                activeShareRequest = request
                pendingShare = request
            }
        } catch is CancellationError {
            finishCancellation()
        } catch let error as StyleToneError where error.isCancellation {
            finishCancellation()
        } catch {
            presentFailure(ExportFailure.map(error, stage: stage))
        }
    }

    /// Retries only the photo-library save of an already encoded file.
    private func retrySave(_ file: ExportStagedFile) async {
        defer { activeTask = nil }
        let saveStart = now

        do {
            try Task.checkCancellation()
            setProgress(.savingToLibrary, 0.94)
            try await dependencies.photoLibrary.save(file)
            let saveDuration = max(0, now.timeIntervalSince(saveStart))
            let total = ExportTimings(
                render: renderDuration,
                encode: encodeDuration,
                save: saveDuration,
                total: renderDuration + encodeDuration + saveDuration
            )
            await finishSuccess(destination: .photoLibrary, file: file, timings: total)
        } catch is CancellationError {
            finishCancellation()
        } catch let error as StyleToneError where error.isCancellation {
            finishCancellation()
        } catch {
            presentFailure(ExportFailure.map(error, stage: stage))
        }
    }

    private func resolveLibraryAccess() async -> PhotoLibraryAccess {
        var access = await dependencies.photoLibrary.authorizationStatus()
        authorization = access

        if access == .notDetermined {
            access = await dependencies.photoLibrary.requestAddOnlyAccess()
            authorization = access
        }
        return access
    }

    private static func requireAddAccess(_ access: PhotoLibraryAccess) throws {
        switch access {
        case .authorized, .limited:
            return
        case .restricted:
            throw ExportLibraryError.permissionRestricted
        case .denied, .notDetermined:
            throw ExportLibraryError.permissionDenied
        case .unavailable:
            throw ExportLibraryError.unavailable
        }
    }

    private func validate(_ result: ExportResult) throws {
        guard let info = fileStore.encodedImageInfo(of: result.url) else {
            throw ExportPipelineError.missingOutput
        }
        // The exporter's metadata must match the bytes it wrote; then the bytes
        // must match what the user asked for.
        guard result.format == info.format else {
            throw ExportPipelineError.formatMismatch(
                expected: result.format,
                actual: info.format
            )
        }
        guard result.pixelSize == info.pixelSize else {
            throw ExportPipelineError.exportSizeMismatch(
                expected: result.pixelSize,
                actual: info.pixelSize
            )
        }
        guard info.format == settings.format else {
            throw ExportPipelineError.formatMismatch(
                expected: settings.format,
                actual: info.format
            )
        }
        guard info.pixelSize == source.expectedPixelSize else {
            throw ExportPipelineError.exportSizeMismatch(
                expected: source.expectedPixelSize,
                actual: info.pixelSize
            )
        }
    }

    // MARK: - Completion

    private func finishSuccess(
        destination: ExportDestination,
        file: ExportStagedFile,
        timings: ExportTimings
    ) async {
        let counted = await recordSuccessfulExport()
        outcome = ExportOutcome(
            destination: destination,
            format: file.format,
            pixelSize: file.pixelSize,
            byteCount: file.byteCount,
            duration: timings.total,
            counted: counted,
            completedAt: now
        )
        self.timings = timings
        failure = nil
        infoNotice = nil
        pendingShare = nil
        activeShareRequest = nil
        progress = ExportProgress(stage: .finished, fraction: 1)
        stage = .finished
        cleanupStagedFile()

        dependencies.logger.log(
            .info,
            "export finished",
            metadata: [
                "destination": destination.rawValue,
                "format": file.format.rawValue,
                "counted": counted ? "true" : "false",
            ]
        )
    }

    private func recordSuccessfulExport() async -> Bool {
        do {
            try await dependencies.quota.recordSuccessfulExport()
            // The cached entitlement is a UI hint; WP-20's persisted count is
            // authoritative. If the record succeeded but a later local write
            // failed, the next refresh corrects this value.
            if case let .free(remaining) = entitlement {
                entitlement = .freeExports(max(0, remaining - 1))
            }
            return true
        } catch {
            // The photo is already delivered; a quota write failure must not
            // turn a successful save into an error screen. It must, however,
            // fail closed for the next attempt: the local entitlement is no
            // longer trustworthy, so block new exports until the host or the
            // quota-retry action reloads the persisted count.
            quotaLoadFailed = true
            dependencies.logger.log(
                .warning,
                "export count not recorded",
                metadata: ["code": "E_EXPORT_COUNT"]
            )
            return false
        }
    }

    private func finishCancellation() {
        activeShareRequest = nil
        pendingShare = nil
        failure = nil
        outcome = nil
        progress = nil
        cleanupStagedFile()
        stage = .cancelled
    }

    private func presentFailure(_ failure: ExportFailure) {
        self.failure = failure
        outcome = nil
        pendingShare = nil
        activeShareRequest = nil
        progress = nil
        stage = .failed
        if !failure.keepsStagedFile {
            cleanupStagedFile()
        }
        dependencies.logger.log(
            .error,
            "export failed",
            metadata: [
                "code": failure.diagnosticCode,
                "stage": failure.stage.rawValue,
            ]
        )
    }

    // MARK: - File lifecycle

    private func makeStagedFile(_ result: ExportResult) -> ExportStagedFile {
        fileStore.applyFileProtection(to: result.url)
        return ExportStagedFile(
            url: result.url,
            format: result.format,
            pixelSize: result.pixelSize,
            byteCount: fileStore.byteCount(of: result.url),
            createdAt: now
        )
    }

    private func cleanupStagedFile() {
        guard let file = stagedFile else { return }
        _ = fileStore.remove(file.url)
        stagedFile = nil
    }

    private func cleanupStaleFiles() {
        let removed = fileStore.removeStaleFiles(now: now)
        guard removed > 0 else { return }
        dependencies.logger.log(
            .info,
            "removed stale export files",
            metadata: ["count": String(removed)]
        )
    }

    // MARK: - Helpers

    private var now: Date {
        dependencies.dateProvider.now
    }

    private func setProgress(_ stage: ExportStage, _ fraction: Double) {
        self.stage = stage
        progress = ExportProgress(stage: stage, fraction: fraction)
    }
}
