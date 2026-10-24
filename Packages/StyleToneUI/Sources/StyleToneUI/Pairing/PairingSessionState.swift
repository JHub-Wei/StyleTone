import Foundation
import StyleToneCore

/// Pure value model for the pairing session.
///
/// Every mutation takes the current instant so tests can drive a virtual clock
/// and the UI stays free of hidden `Date()` calls. The type owns the rules that
/// matter for the product: a red pair is never learnable, deleting keeps one
/// level of undo, and the timeline records the 12-pairs/6-minutes budget.
public struct PairingSessionState: Sendable, Equatable {
    /// The largest session the UI accepts; also the acceptance scenario size.
    public static let maximumPairs = 12
    /// The trial minimum: fewer usable pairs cannot produce a profile.
    public static let minimumLearnablePairs = 3
    /// Acceptance budget: 12 pairs in under six minutes.
    public static let timeBudgetSeconds: TimeInterval = 6 * 60
    /// Number of pairs the budget refers to.
    public static let timeBudgetPairCount = 12

    public private(set) var target: PairingTarget
    public private(set) var stage: PairingStage
    public private(set) var pairs: [PairingPairState]
    public private(set) var timeline: PairingTimeline
    public private(set) var lastDeletion: PairingDeletionBackup?
    public private(set) var updatedAt: Date

    public init(target: PairingTarget = .defaultTarget, startedAt: Date) {
        self.target = target
        self.stage = .editing
        self.pairs = []
        self.timeline = PairingTimeline(startedAt: startedAt)
        self.lastDeletion = nil
        self.updatedAt = startedAt
    }

    init(
        target: PairingTarget,
        stage: PairingStage,
        pairs: [PairingPairState],
        timeline: PairingTimeline,
        lastDeletion: PairingDeletionBackup?,
        updatedAt: Date
    ) {
        self.target = target
        self.stage = stage
        self.pairs = pairs
        self.timeline = timeline
        self.lastDeletion = lastDeletion
        self.updatedAt = updatedAt
    }

    // MARK: - Lookups

    public func pair(withID pairID: UUID) -> PairingPairState? {
        pairs.first { $0.id == pairID }
    }

    public func position(of pairID: UUID) -> Int? {
        pairs.firstIndex { $0.id == pairID }
    }

    /// Pair rows with the 1-based number the card header displays.
    public var rows: [PairingPairRow] {
        pairs.enumerated().map { offset, pair in
            PairingPairRow(number: offset + 1, pair: pair)
        }
    }

    public var isFull: Bool {
        pairs.count >= Self.maximumPairs
    }

    public var canAddPair: Bool {
        !isFull
    }

    // MARK: - Counts and progress

    /// Complete, non-rejected pairs. Rejected pairs are excluded here and in
    /// `learnableSamples`, which is what keeps red pairs out of learning.
    public var learnablePairs: [PairingPairState] {
        pairs.filter { $0.isLearnable }
    }

    public var learnableCount: Int {
        learnablePairs.count
    }

    public var learnableSamples: [PairSample] {
        pairs.compactMap { pair in
            guard pair.isLearnable,
                  let original = pair.original,
                  let edited = pair.edited,
                  let quality = pair.quality
            else {
                return nil
            }
            return PairSample(
                id: pair.id,
                original: original.asset,
                edited: edited.asset,
                quality: quality
            )
        }
    }

    public var progress: PairingProgress {
        let learnable = pairs.filter { $0.isLearnable }
        let good = learnable.filter { $0.quality?.grade == .good }.count
        let warning = learnable.filter { $0.quality?.grade == .warning }.count
        let rejected = pairs.filter { $0.isRejected }.count
        let pending = max(0, pairs.count - good - warning - rejected)
        return PairingProgress(
            eligible: learnable.count,
            target: target.count,
            good: good,
            warning: warning,
            rejected: rejected,
            pending: pending,
            total: pairs.count
        )
    }

    /// The finish action needs the trial minimum of usable pairs.
    public var canContinue: Bool {
        learnableCount >= Self.minimumLearnablePairs
    }

    public var remainingToMinimum: Int {
        max(0, Self.minimumLearnablePairs - learnableCount)
    }

    public func summary(at date: Date) -> PairingSessionSummary {
        let progress = self.progress
        return PairingSessionSummary(
            stage: stage,
            target: target.count,
            totalPairs: pairs.count,
            goodCount: progress.good,
            warningCount: progress.warning,
            rejectedCount: progress.rejected,
            learnableCount: learnableCount,
            elapsed: timeline.elapsed(at: date),
            budgetPairCount: Self.timeBudgetPairCount,
            budgetSeconds: Self.timeBudgetSeconds
        )
    }

    /// `true` when the session is still inside the 12-pairs/6-minutes budget.
    public func meetsTimeBudget(at date: Date) -> Bool {
        timeline.meetsTimeBudget(at: date, budget: Self.timeBudgetSeconds)
    }

    // MARK: - Pair mutations

    /// Appends an empty pair. Returns `nil` when the session is full.
    @discardableResult
    public mutating func addPair(now: Date) -> UUID? {
        guard canAddPair else { return nil }
        let pair = PairingPairState(createdAt: now, updatedAt: now)
        pairs.append(pair)
        contentChanged(now)
        return pair.id
    }

    /// Attaches or replaces the photo of one slot.
    ///
    /// Replacing keeps the other slot untouched: that is what makes a
    /// replacement non-destructive. Any previous quality result is cleared
    /// because it described different pixels.
    @discardableResult
    public mutating func attach(
        _ photo: PairingPhoto,
        to slot: PairingSlot,
        pairID: UUID,
        now: Date
    ) -> Bool {
        guard let position = position(of: pairID) else { return false }
        var pair = pairs[position]
        let wasComplete = pair.isComplete
        switch slot {
        case .original:
            pair.original = photo
            pair.needsReselectOriginal = false
        case .edited:
            pair.edited = photo
            pair.needsReselectEdited = false
        }
        pair.contentRevision += 1
        pair.assessment = .waitingForImages
        pair.updatedAt = now
        pairs[position] = pair
        if !wasComplete, pair.isComplete {
            notePairComplete(at: now)
        }
        contentChanged(now)
        return true
    }

    /// Removes one photo and remembers it for undo.
    @discardableResult
    public mutating func removePhoto(
        _ slot: PairingSlot,
        from pairID: UUID,
        now: Date
    ) -> Bool {
        guard let position = position(of: pairID) else { return false }
        var pair = pairs[position]
        guard let photo = pair.photo(for: slot) else { return false }

        lastDeletion = PairingDeletionBackup(
            pairID: pairID,
            content: .photo(
                slot: slot,
                photo: photo,
                previousAssessment: pair.assessment,
                previousNeedsReselect: pair.needsReselect(for: slot)
            ),
            deletedAt: now
        )

        switch slot {
        case .original:
            pair.original = nil
            pair.needsReselectOriginal = false
        case .edited:
            pair.edited = nil
            pair.needsReselectEdited = false
        }
        pair.contentRevision += 1
        pair.assessment = .waitingForImages
        pair.updatedAt = now
        pairs[position] = pair
        contentChanged(now)
        return true
    }

    /// Deletes a whole pair and remembers it for undo.
    @discardableResult
    public mutating func deletePair(_ pairID: UUID, now: Date) -> Bool {
        guard let position = position(of: pairID) else { return false }
        let pair = pairs.remove(at: position)
        lastDeletion = PairingDeletionBackup(
            pairID: pairID,
            content: .pair(pair, index: position),
            deletedAt: now
        )
        contentChanged(now)
        return true
    }

    /// Restores the most recent deletion, if any.
    ///
    /// Undo is single level and is cleared by a successful restore or by a new
    /// destructive action. Pair restores clamp to the current list length.
    @discardableResult
    public mutating func undoLastDeletion(now: Date) -> Bool {
        guard let backup = lastDeletion else { return false }

        switch backup.content {
        case let .pair(pair, index):
            guard !pairs.contains(where: { $0.id == pair.id }) else {
                lastDeletion = nil
                return false
            }
            var restored = pair
            restored.updatedAt = now
            let safeIndex = min(max(0, index), pairs.count)
            pairs.insert(restored, at: safeIndex)
            lastDeletion = nil
            contentChanged(now)
            return true

        case let .photo(slot, photo, previousAssessment, previousNeedsReselect):
            guard let position = position(of: backup.pairID) else {
                lastDeletion = nil
                return false
            }
            var pair = pairs[position]
            switch slot {
            case .original:
                pair.original = photo
                pair.needsReselectOriginal = previousNeedsReselect
            case .edited:
                pair.edited = photo
                pair.needsReselectEdited = previousNeedsReselect
            }
            pair.assessment = previousAssessment
            pair.contentRevision += 1
            pair.updatedAt = now
            pairs[position] = pair
            lastDeletion = nil
            contentChanged(now)
            return true
        }
    }

    public mutating func discardLastDeletion() {
        lastDeletion = nil
    }

    // MARK: - Target and stage

    public mutating func setTarget(_ target: PairingTarget, now: Date) {
        guard self.target != target else { return }
        self.target = target
        touch(now)
    }

    /// Marks the session finished. Requires the trial minimum of usable pairs.
    @discardableResult
    public mutating func complete(at date: Date) -> Bool {
        guard canContinue else { return false }
        stage = .completed
        touch(date)
        return true
    }

    /// Skips calibration; the app then falls back to the natural default.
    public mutating func skip(at date: Date) {
        stage = .skipped
        touch(date)
    }

    /// Re-opens a finished session for editing after a relaunch.
    public mutating func resumeEditing(now: Date) {
        guard stage != .editing else { return }
        stage = .editing
        touch(now)
    }

    // MARK: - Quality

    /// Marks a complete pair as being checked and returns the revision the
    /// result must match.
    @discardableResult
    public mutating func beginAssessment(for pairID: UUID, now: Date) -> Int? {
        guard let position = position(of: pairID) else { return nil }
        var pair = pairs[position]
        guard pair.isComplete else {
            pair.assessment = .waitingForImages
            pairs[position] = pair
            return nil
        }
        pair.assessment = .assessing
        pair.updatedAt = now
        pairs[position] = pair
        touch(now)
        return pair.contentRevision
    }

    /// Applies a quality result, dropping it when the pair changed meanwhile.
    @discardableResult
    public mutating func completeAssessment(
        _ quality: PairQuality,
        for pairID: UUID,
        revision: Int,
        now: Date
    ) -> Bool {
        guard let position = position(of: pairID) else { return false }
        var pair = pairs[position]
        guard pair.contentRevision == revision, pair.isComplete else { return false }
        pair.assessment = .completed(quality)
        pair.updatedAt = now
        pairs[position] = pair
        touch(now)
        return true
    }

    /// Records a failed check, again guarded by the content revision.
    @discardableResult
    public mutating func failAssessment(
        _ failure: PairingAssessmentFailure,
        for pairID: UUID,
        revision: Int,
        now: Date
    ) -> Bool {
        guard let position = position(of: pairID) else { return false }
        var pair = pairs[position]
        guard pair.contentRevision == revision, pair.isComplete else { return false }
        pair.assessment = .failed(failure)
        pair.updatedAt = now
        pairs[position] = pair
        touch(now)
        return true
    }

    /// Whether both slots reference the same library asset.
    public func hasIdenticalSelection(_ pairID: UUID) -> Bool {
        guard let pair = self.pair(withID: pairID),
              let originalIdentifier = pair.original?.sourceIdentifier,
              let editedIdentifier = pair.edited?.sourceIdentifier
        else {
            return false
        }
        return originalIdentifier == editedIdentifier
    }

    /// Rejects a pair whose two slots point at the same photo.
    ///
    /// The picker identifier is opaque and may be missing; when it is present
    /// an identical selection can never be a real retouch pair, so it is
    /// graded red without calling the analyzer.
    @discardableResult
    public mutating func rejectIdenticalSelection(
        for pairID: UUID,
        revision: Int,
        now: Date
    ) -> Bool {
        let quality = PairQuality(
            grade: .rejected,
            reasons: [PairingQualityReasonKeys.samePhoto],
            confidence: 1
        )
        return completeAssessment(quality, for: pairID, revision: revision, now: now)
    }

    // MARK: - Private

    private mutating func notePairComplete(at date: Date) {
        timeline.completedPairTimestamps.append(date)
        let limit = Self.maximumPairs * 2
        if timeline.completedPairTimestamps.count > limit {
            timeline.completedPairTimestamps.removeFirst(
                timeline.completedPairTimestamps.count - limit
            )
        }
    }

    private mutating func contentChanged(_ now: Date) {
        stage = .editing
        touch(now)
    }

    private mutating func touch(_ now: Date) {
        updatedAt = now
        timeline.lastActivityAt = now
    }
}
