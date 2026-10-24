import Foundation
import Observation
import StyleToneCore

/// Serializes calibration draft writes so a late autosave cannot resurrect an
/// old draft after the completed profile was stored and the draft cleared.
private actor CalibrationDraftWriter {
    private enum Operation {
        case save(CalibrationDraft)
        case clear
    }

    private let store: any CalibrationProgressStoring
    private var queue: [Operation] = []
    private var isDraining = false
    private var failed = false

    init(store: any CalibrationProgressStoring) {
        self.store = store
    }

    func enqueueSave(_ draft: CalibrationDraft) {
        queue.append(.save(draft))
        startIfNeeded()
    }

    func enqueueClear() {
        queue.append(.clear)
        startIfNeeded()
    }

    func flush() async {
        while isDraining || !queue.isEmpty {
            await Task.yield()
        }
    }

    func consumeFailure() -> Bool {
        defer { failed = false }
        return failed
    }

    private func startIfNeeded() {
        guard !isDraining, !queue.isEmpty else { return }
        isDraining = true
        Task { await drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            let operation = queue.removeFirst()
            do {
                switch operation {
                case let .save(draft):
                    try await store.saveDraft(draft)
                case .clear:
                    try await store.clearDraft()
                }
            } catch {
                failed = true
            }
        }
        isDraining = false
    }
}

/// Observable controller for the 3/5/8 calibration flow.
///
/// The controller owns learning and persistence tasks. It accepts any
/// `StyleLearning` implementation, so WP-11 can replace
/// `CalibrationMockStyleLearning` without changing the UI or flow. No account,
/// network, or login state exists anywhere in this type.
@MainActor
@Observable
public final class CalibrationViewModel {
    public private(set) var flow: CalibrationFlow
    public private(set) var isBusy = false
    public private(set) var isRestored = false
    public private(set) var notice: CalibrationNotice?

    private let learner: any StyleLearning
    private let profileStore: any StyleProfileStore
    private let progressStore: any CalibrationProgressStoring
    private let dateProvider: any DateProviding
    private let writer: CalibrationDraftWriter
    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private var workToken = UUID()
    @ObservationIgnored private var saveDraftTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceGeneration = 0
    @ObservationIgnored private var pendingProfile: StyleProfile?

    public init(
        samples: [PairSample],
        learner: any StyleLearning,
        profileStore: any StyleProfileStore,
        progressStore: any CalibrationProgressStoring,
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.flow = CalibrationFlow(samples: samples, now: dateProvider.now)
        self.learner = learner
        self.profileStore = profileStore
        self.progressStore = progressStore
        self.dateProvider = dateProvider
        self.writer = CalibrationDraftWriter(store: progressStore)
    }

    /// Standalone wiring used by SwiftUI previews and early integration.
    /// Production passes the WP-08 store and the WP-11 learner explicitly.
    public convenience init(samples: [PairSample]) {
        self.init(
            samples: samples,
            learner: CalibrationMockStyleLearning(),
            profileStore: CalibrationPreviewStyleProfileStore(),
            progressStore: CalibrationInMemoryProgressStore()
        )
    }

    // MARK: Lifecycle

    /// Loads a saved draft exactly once. Missing pair images do not crash or
    /// discard the draft; the flow remains on pair selection with a notice.
    public func restoreIfNeeded() async {
        guard !isRestored else { return }
        isRestored = true

        do {
            guard let draft = try await progressStore.loadDraft() else { return }
            switch flow.restore(from: draft) {
            case .restored:
                notice = .restored
            case .missingPairs:
                notice = .missingPairs
            case .incompatibleVersion:
                notice = .progressUnavailable
            }
        } catch {
            notice = .progressUnavailable
        }
    }

    /// Saves the current draft before the screen is dismissed. Pair images are
    /// owned by WP-09; only their identifiers and calibration answers are
    /// written here.
    public func pause() async {
        guard !isBusy else { return }
        saveDraftTask?.cancel()
        saveDraftTask = nil
        persistenceGeneration += 1

        await writer.enqueueSave(flow.makeDraft())
        await writer.flush()
        if await writer.consumeFailure() {
            notice = .progressUnavailable
        }
    }

    /// Test/UI hook that waits for the current learner and its follow-up save.
    public func waitForLearningToFinish() async {
        while isBusy {
            if let workTask {
                await workTask.value
            } else {
                await Task.yield()
            }
        }
    }

    public func dismissNotice() {
        notice = nil
    }

    // MARK: Pair stage

    @discardableResult
    public func addSamples(_ samples: [PairSample]) -> Int {
        guard !isBusy else { return 0 }
        let added = flow.addSamples(samples, now: dateProvider.now)
        if added > 0 {
            notice = nil
            schedulePersist()
        }
        return added
    }

    @discardableResult
    public func beginComparisons(using tier: CalibrationPairTier? = nil) -> Bool {
        guard !isBusy else { return false }
        guard flow.startComparisons(using: tier, now: dateProvider.now) else {
            return false
        }
        notice = nil
        schedulePersist()
        return true
    }

    // MARK: AB stage

    public func answerCurrent(choseA: Bool) {
        guard !isBusy else { return }
        guard flow.answerCurrent(choseA: choseA, now: dateProvider.now) else {
            return
        }
        notice = nil
        schedulePersist()

        if flow.phase == .learning {
            startLearning()
        }
    }

    public func skipCurrentComparison() {
        guard !isBusy else { return }
        guard flow.skipCurrentComparison(now: dateProvider.now) else {
            return
        }
        notice = nil
        schedulePersist()

        if flow.phase == .learning {
            startLearning()
        }
    }

    public func finishComparisons() {
        guard !isBusy else { return }
        guard flow.finishComparisons(now: dateProvider.now) else { return }
        notice = nil
        schedulePersist()
        startLearning()
    }

    public func skipToNaturalDefault() {
        guard !isBusy else { return }
        guard flow.beginNaturalDefault(now: dateProvider.now) else { return }
        notice = nil
        schedulePersist()

        let profile = CalibrationFlow.naturalDefaultProfile(now: dateProvider.now)
        startSaving(profile)
    }

    // MARK: Failure recovery

    public func retry() {
        guard !isBusy, let failure = flow.failure else { return }

        switch failure.kind {
        case .learning:
            guard flow.retryLearning(now: dateProvider.now) else { return }
            schedulePersist()
            startLearning()
        case .savingProfile:
            guard let profile = pendingProfile else {
                guard flow.retryLearning(now: dateProvider.now) else { return }
                schedulePersist()
                startLearning()
                return
            }
            guard flow.retryLearning(now: dateProvider.now) else { return }
            schedulePersist()
            startSaving(profile)
        case .restoring, .missingPairs:
            break
        }
    }

    /// Returns to the AB screen after a failure without discarding answers.
    /// A natural-default save started before any tier was selected returns to
    /// the pair screen instead, where the user has a valid exit.
    public func returnToComparisons() {
        guard !isBusy else { return }
        returnToPriorStage()
        pendingProfile = nil
        notice = nil
        schedulePersist()
    }

    /// Cancels learning or saving and returns to the AB screen.
    public func cancelWork() {
        guard isBusy else { return }
        workToken = UUID()
        workTask?.cancel()
        workTask = nil
        pendingProfile = nil
        isBusy = false

        returnToPriorStage()
        notice = .cancelledLearning
        schedulePersist()
    }

    public func recalibrate() {
        guard !isBusy else { return }
        guard flow.recalibrate(now: dateProvider.now) else { return }
        pendingProfile = nil
        notice = nil
        schedulePersist()
    }

    // MARK: Learning

    private func startLearning() {
        guard !isBusy, flow.phase == .learning else { return }
        guard let request = flow.learningRequest else {
            _ = flow.failLearning(CalibrationFailure(kind: .learning), now: dateProvider.now)
            notice = nil
            return
        }

        isBusy = true
        let token = UUID()
        workToken = token
        let learner = self.learner

        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                let profile = try await learner.learn(
                    samples: request.samples,
                    answers: request.answers
                )
                try Task.checkCancellation()
                guard self.workToken == token else { return }

                // Reuse the same work token; the save task replaces
                // `workTask` and the learning task then returns.
                self.startSaving(profile, token: token)
            } catch {
                guard self.workToken == token else { return }
                if Self.isCancellation(error) {
                    self.finishCancelledWork()
                } else {
                    _ = self.flow.failLearning(
                        CalibrationFailure(kind: .learning),
                        now: self.dateProvider.now
                    )
                    self.isBusy = false
                    self.workTask = nil
                    self.schedulePersist()
                }
            }
        }
    }

    private func startSaving(_ profile: StyleProfile, token optionalToken: UUID? = nil) {
        let token = optionalToken ?? UUID()
        workToken = token
        pendingProfile = profile
        isBusy = true
        let profileStore = self.profileStore

        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await profileStore.save(profile)
                try Task.checkCancellation()
                guard self.workToken == token else { return }

                _ = self.flow.completeLearning(profile, now: self.dateProvider.now)
                self.pendingProfile = nil
                self.isBusy = false
                self.workTask = nil
                self.notice = nil
                self.clearProgress()
            } catch {
                guard self.workToken == token else { return }
                if Self.isCancellation(error) {
                    self.finishCancelledWork()
                } else {
                    self.pendingProfile = profile
                    _ = self.flow.failLearning(
                        CalibrationFailure(kind: .savingProfile),
                        now: self.dateProvider.now
                    )
                    self.isBusy = false
                    self.workTask = nil
                    self.schedulePersist()
                }
            }
        }
    }

    private func finishCancelledWork() {
        workTask = nil
        pendingProfile = nil
        isBusy = false
        returnToPriorStage()
        notice = .cancelledLearning
        schedulePersist()
    }

    private func returnToPriorStage() {
        if flow.selectedPairCount >= CalibrationLimits.minimumPairCount {
            _ = flow.cancelLearning(now: dateProvider.now)
        } else {
            _ = flow.recalibrate(now: dateProvider.now)
        }
    }

    // MARK: Persistence

    private func schedulePersist() {
        persistenceGeneration += 1
        let generation = persistenceGeneration
        let draft = flow.makeDraft()

        saveDraftTask?.cancel()
        saveDraftTask = Task { [weak self] in
            // Coalesce bursts of answers into a single small JSON write.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let self else { return }
            guard self.persistenceGeneration == generation else { return }

            await self.writer.enqueueSave(draft)
            await self.writer.flush()
            let failed = await self.writer.consumeFailure()
            guard self.persistenceGeneration == generation else { return }
            if failed {
                self.notice = .progressUnavailable
            }
        }
    }

    private func clearProgress() {
        persistenceGeneration += 1
        saveDraftTask?.cancel()
        saveDraftTask = nil

        Task { [weak self] in
            guard let self else { return }
            await self.writer.enqueueClear()
            await self.writer.flush()
            if await self.writer.consumeFailure() {
                self.notice = .progressUnavailable
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let styleToneError = error as? StyleToneError, styleToneError.isCancellation {
            return true
        }
        return false
    }
}
