import Foundation
import Observation
import StyleToneCore

// MARK: - Dependencies

/// Everything the pairing screen needs from the host.
///
/// The quality analyzer defaults to the explicit "unavailable" stand-in so an
/// ungraded pair can never reach learning before WP-05 is wired. The store
/// defaults to memory; the app injects `FilePairingSessionStore` in its
/// composition root.
public struct PairingDependencies: Sendable {
    public var qualityAnalyzer: any PairQualityAnalyzing
    public var sessionStore: any PairingSessionStoring
    public var imageImporter: any PairingImageImporting
    public var dateProvider: any DateProviding
    public var availabilityProvider: any PairingPickerAvailabilityProviding
    public var target: PairingTarget

    public init(
        qualityAnalyzer: any PairQualityAnalyzing = UnavailablePairQualityAnalyzer(),
        sessionStore: any PairingSessionStoring = InMemoryPairingSessionStore(),
        imageImporter: any PairingImageImporting = PairingImageImporter(),
        dateProvider: any DateProviding = SystemDateProvider(),
        availabilityProvider: any PairingPickerAvailabilityProviding = SystemPairingPickerAvailability(),
        target: PairingTarget = .defaultTarget
    ) {
        self.qualityAnalyzer = qualityAnalyzer
        self.sessionStore = sessionStore
        self.imageImporter = imageImporter
        self.dateProvider = dateProvider
        self.availabilityProvider = availabilityProvider
        self.target = target
    }

    /// Safe defaults for previews and the shell before WP-05/WP-08 land.
    public static let placeholder = PairingDependencies()
}

// MARK: - View model

/// State and actions behind the pairing screen.
///
/// All asynchronous work (decode, quality check, save) is awaited from the
/// caller's task, which keeps the flow deterministic for tests: an import call
/// returns only after the pair is graded and handed to the store. The main actor
/// stays free while the analyzer/loader run off-actor.
@MainActor
@Observable
public final class PairingViewModel {
    // MARK: Observable state

    public private(set) var availability: PairingPickerAvailability
    public private(set) var saveState: PairingSaveState = .idle
    public private(set) var notice: PairingNotice?
    public private(set) var isLoading = false
    public private(set) var importingPairID: UUID?
    /// The picker request awaiting a result. The screen binds the system
    /// picker's presentation to this value; SwiftUI clears it on dismissal.
    public var pendingPick: PairingPickRequest?
    public private(set) var hasLoaded = false

    private var state: PairingSessionState
    private let dependencies: PairingDependencies
    private var isStarting = false
    private var saveChain: Task<Void, Never>?

    public init(dependencies: PairingDependencies = .placeholder) {
        self.dependencies = dependencies
        self.availability = .available
        self.state = PairingSessionState(
            target: dependencies.target,
            startedAt: dependencies.dateProvider.now
        )
    }

    // MARK: Derived state

    public var session: PairingSessionState { state }

    public var progress: PairingProgress { state.progress }

    public var rows: [PairingPairRow] { state.rows }

    public var target: PairingTarget { state.target }

    public var canAddPair: Bool {
        hasLoaded && availability.isAvailable && state.canAddPair && importingPairID == nil
    }

    public var canContinue: Bool {
        hasLoaded && state.canContinue
    }

    public var continueHint: String? {
        guard hasLoaded, !state.canContinue else { return nil }
        return PairingCopy.continueHint.text
    }

    public var undo: PairingDeletionBackup? { state.lastDeletion }

    public var showsEmptyState: Bool {
        hasLoaded && state.pairs.isEmpty
    }

    public var hasStalePhotos: Bool {
        state.pairs.contains { !$0.staleSlots.isEmpty }
    }

    public var summary: PairingSessionSummary {
        state.summary(at: now)
    }

    public var isPickerAvailable: Bool { availability.isAvailable }

    /// A picker payload is being imported.
    public var isImporting: Bool { importingPairID != nil }

    /// Cards accept edits only when nothing is being imported.
    public var isEditable: Bool { hasLoaded && !isImporting }

    /// Copy for the save indicator.
    public var saveText: String {
        switch saveState {
        case .idle: return PairingCopy.saveIdle.text
        case .saving: return PairingCopy.saveSaving.text
        case .saved: return PairingCopy.saveSaved.text
        case .failed: return PairingCopy.saveFailed.text
        }
    }

    // MARK: Lifecycle

    /// Loads the stored session and the picker availability once.
    public func start() async {
        guard !hasLoaded, !isStarting else { return }
        isStarting = true
        isLoading = true
        defer {
            isStarting = false
            isLoading = false
        }

        await loadStoredSession()

        let currentAvailability = await dependencies.availabilityProvider.currentAvailability()
        availability = currentAvailability
        if case let .unavailable(reason) = currentAvailability {
            notice = .pickerUnavailable(reason)
        }

        hasLoaded = true
    }

    /// Re-checks whether the picker can open.
    public func refreshAvailability() async {
        let updated = await dependencies.availabilityProvider.currentAvailability()
        availability = updated
        switch updated {
        case .available:
            if notice?.action == .refreshPickerAvailability {
                notice = nil
            }
        case let .unavailable(reason):
            notice = .pickerUnavailable(reason)
        }
    }

    // MARK: Picking

    /// Adds an empty pair and immediately asks for both photos.
    ///
    /// If the previous attempt left an untouched empty card behind (the user
    /// cancelled the picker), that card is reused instead of stacking another
    /// one; the session never accumulates empty placeholders.
    public func addPair() {
        guard hasLoaded else { return }
        guard availability.isAvailable else {
            if case let .unavailable(reason) = availability {
                notice = .pickerUnavailable(reason)
            }
            return
        }

        if let reusable = state.pairs.last(where: { pair in
            pair.original == nil
                && pair.edited == nil
                && pair.quality == nil
                && pair.staleSlots.isEmpty
        }) {
            pendingPick = PairingPickRequest(pairID: reusable.id, mode: .pair)
            return
        }

        guard state.canAddPair else {
            notice = .limitReached()
            return
        }
        guard let pairID = state.addPair(now: now) else { return }
        scheduleSave()
        pendingPick = PairingPickRequest(pairID: pairID, mode: .pair)
    }

    /// Asks for one slot of an existing pair (add or replace).
    public func pick(_ slot: PairingSlot, in pairID: UUID) {
        guard hasLoaded, state.pair(withID: pairID) != nil else { return }
        guard availability.isAvailable else {
            if case let .unavailable(reason) = availability {
                notice = .pickerUnavailable(reason)
            }
            return
        }
        pendingPick = PairingPickRequest(pairID: pairID, mode: .slot(slot))
    }

    /// Dismisses the picker without a selection.
    ///
    /// The empty card is kept: the user can fill one slot at a time or delete
    /// it, and a later "Add pair" reuses it instead of adding another empty
    /// card. Existing photos are never touched.
    public func cancelPick() {
        pendingPick = nil
    }

    /// Reports a payload that could not even be read from the picker.
    ///
    /// The request is closed first so the sheet dismisses, then the notice
    /// offers a retry that reopens the picker for the same pair.
    public func reportImportFailure(_ error: PairingImportError) {
        guard let request = pendingPick else {
            notice = PairingNotice(kind: .error, title: error.title, message: error.message)
            return
        }
        pendingPick = nil
        notice = .importFailure(error, mode: request.mode, pairID: request.pairID)
    }

    /// Imports the picker selection.
    ///
    /// All photos are decoded before any slot is touched, so a failure leaves
    /// the existing pair exactly as it was; a replacement can never lose the
    /// photo it was replacing.
    public func importPickedPhotos(_ picked: [PairingPickedPhoto]) async {
        guard let request = pendingPick else { return }
        guard !picked.isEmpty else {
            cancelPick()
            return
        }

        let mode = request.mode
        let selection = Array(picked.prefix(mode.selectionLimit))
        let pairID = request.pairID

        pendingPick = nil
        importingPairID = pairID
        defer { importingPairID = nil }

        var imported: [PairingPhoto] = []
        do {
            for photo in selection {
                try Task.checkCancellation()
                let importedPhoto = try await dependencies.imageImporter.importImage(
                    from: photo.data,
                    sourceIdentifier: photo.sourceIdentifier,
                    importedAt: now
                )
                imported.append(importedPhoto)
            }
        } catch is CancellationError {
            return
        } catch let error as PairingImportError {
            notice = .importFailure(error, mode: mode, pairID: pairID)
            return
        } catch {
            notice = .importFailure(.unknown, mode: mode, pairID: pairID)
            return
        }

        guard state.pair(withID: pairID) != nil else { return }

        var updated = state
        let slots = mode.slots
        for (index, photo) in imported.enumerated() where index < slots.count {
            updated.attach(photo, to: slots[index], pairID: pairID, now: now)
        }
        state = updated
        scheduleSave()

        importingPairID = nil
        await assess(pairID: pairID)
    }

    // MARK: Quality

    /// Re-runs the quality check for one pair.
    public func retryAssessment(pairID: UUID) async {
        await assess(pairID: pairID)
    }

    // MARK: Editing

    public func removePhoto(_ slot: PairingSlot, in pairID: UUID) {
        if state.removePhoto(slot, from: pairID, now: now) {
            scheduleSave()
        }
    }

    public func deletePair(_ pairID: UUID) {
        if state.deletePair(pairID, now: now) {
            scheduleSave()
        }
    }

    public func undoDelete() {
        guard state.undoLastDeletion(now: now) else { return }
        scheduleSave()
    }

    public func selectTarget(_ target: PairingTarget) {
        guard state.target != target else { return }
        state.setTarget(target, now: now)
        scheduleSave()
    }

    // MARK: Completion

    /// Marks the session complete and returns the samples for learning.
    ///
    /// Red pairs are filtered out by `learnableSamples`, so they can never be
    /// handed to `StyleLearning`.
    @discardableResult
    public func finish() -> [PairSample]? {
        guard state.complete(at: now) else {
            notice = PairingNotice(kind: .info, title: PairingCopy.continueHint)
            return nil
        }
        let samples = state.learnableSamples
        scheduleSave()
        return samples
    }

    public func skip() {
        state.skip(at: now)
        scheduleSave()
    }

    public func resumeEditing() {
        state.resumeEditing(now: now)
        scheduleSave()
    }

    // MARK: Notices and recovery

    public func dismissNotice() {
        notice = nil
    }

    public func perform(_ action: PairingNoticeAction) async {
        switch action {
        case let .reopenPicker(mode, pairID):
            notice = nil
            guard hasLoaded, state.pair(withID: pairID) != nil else { return }
            pendingPick = PairingPickRequest(pairID: pairID, mode: mode)

        case let .retryAssessment(pairID):
            notice = nil
            await assess(pairID: pairID)

        case .retrySave:
            notice = nil
            await saveNow()

        case .retryLoad:
            notice = nil
            hasLoaded = false
            isLoading = true
            await loadStoredSession()
            hasLoaded = true
            isLoading = false

        case .startFreshSession:
            await startFreshSession()

        case .refreshPickerAvailability:
            await refreshAvailability()

        case .resumeEditing:
            notice = nil
            resumeEditing()
        }
    }

    /// Clears the stored metadata and starts from an empty session.
    public func startFreshSession() async {
        do {
            try await dependencies.sessionStore.clear()
            notice = nil
        } catch {
            notice = .sessionLoadFailure(.clearFailed)
        }
        state = PairingSessionState(target: dependencies.target, startedAt: now)
        pendingPick = nil
        importingPairID = nil
        saveState = .idle
    }

    /// Waits for the latest queued metadata save.
    public func flushPersistence() async {
        let chain = saveChain
        await chain?.value
    }

    // MARK: - Private

    private var now: Date {
        dependencies.dateProvider.now
    }

    private func loadStoredSession() async {
        do {
            guard let snapshot = try await dependencies.sessionStore.load() else {
                return
            }
            let restored = try PairingSessionState(snapshot: snapshot, restoredAt: now)
            state = restored
            pendingPick = nil
            if restored.stage == .completed {
                notice = .completedSession()
            } else {
                notice = .restoredSession(hasStalePhotos: restored.pairs.contains {
                    !$0.staleSlots.isEmpty
                })
            }
        } catch let error as PairingSessionStoreError {
            notice = .sessionLoadFailure(error)
        } catch is CancellationError {
            return
        } catch {
            notice = .sessionLoadFailure(.corrupted)
        }
    }

    /// Runs the analyzer for a complete pair and applies the guarded result.
    private func assess(pairID: UUID) async {
        guard let pair = state.pair(withID: pairID),
              let original = pair.original,
              let edited = pair.edited
        else {
            return
        }

        if state.hasIdenticalSelection(pairID) {
            if state.rejectIdenticalSelection(
                for: pairID,
                revision: pair.contentRevision,
                now: now
            ) {
                scheduleSave()
            }
            return
        }

        guard let revision = state.beginAssessment(for: pairID, now: now) else { return }

        do {
            let quality = try await dependencies.qualityAnalyzer.assess(
                original: original.asset,
                edited: edited.asset
            )
            guard state.completeAssessment(
                quality,
                for: pairID,
                revision: revision,
                now: now
            ) else {
                return
            }
            scheduleSave()
        } catch is CancellationError {
            if state.failAssessment(
                PairingAssessmentFailure(code: .cancelled),
                for: pairID,
                revision: revision,
                now: now
            ) {
                scheduleSave()
            }
            return
        } catch {
            let failure = PairingAssessmentFailure.map(error)
            if state.failAssessment(failure, for: pairID, revision: revision, now: now) {
                scheduleSave()
            }
        }
    }

    /// Queues a metadata save; saves run in order and never overlap.
    private func scheduleSave() {
        guard hasLoaded else { return }
        let snapshot = state.snapshot()
        let store = dependencies.sessionStore
        let previous = saveChain
        saveState = .saving
        saveChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await store.save(snapshot)
                self.saveState = .saved(self.now)
            } catch {
                self.saveState = .failed
                self.notice = .sessionSaveFailure()
            }
        }
    }

    /// Saves immediately, bypassing the queue, for the retry action.
    private func saveNow() async {
        await saveChain?.value
        let snapshot = state.snapshot()
        saveState = .saving
        do {
            try await dependencies.sessionStore.save(snapshot)
            saveState = .saved(now)
        } catch {
            saveState = .failed
            notice = .sessionSaveFailure()
        }
    }

    #if DEBUG
    /// Seeds a deterministic session for SwiftUI previews only.
    public func seedForPreview(_ session: PairingSessionState) {
        state = session
        pendingPick = nil
        notice = nil
        saveState = .saved(now)
        hasLoaded = true
        isLoading = false
    }
    #endif
}
