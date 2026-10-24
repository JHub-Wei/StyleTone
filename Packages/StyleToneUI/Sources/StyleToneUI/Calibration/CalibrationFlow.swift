import Foundation
import StyleToneCore

/// A snapshot passed to `StyleLearning`.
public struct CalibrationLearningRequest: Sendable {
    public let samples: [PairSample]
    public let answers: [CalibrationAnswer]

    public init(samples: [PairSample], answers: [CalibrationAnswer]) {
        self.samples = samples
        self.answers = answers
    }
}

/// Pure, Sendable state machine for WP-10.
///
/// The flow deliberately knows nothing about SwiftUI, file I/O or StyleLearning
/// execution. It never drops pair samples on failure, so retrying learning or
/// going back to compare again cannot lose the user's selection.
public struct CalibrationFlow: Sendable {
    public private(set) var samples: [PairSample]
    public private(set) var phase: CalibrationPhase
    public private(set) var selectedPairCount: Int
    public private(set) var trainingPairIDs: [UUID]
    public private(set) var answers: [CalibrationAnswer]
    public private(set) var comparisonIndex: Int
    public private(set) var skippedComparisonCount: Int
    public private(set) var profile: StyleProfile?
    public private(set) var failure: CalibrationFailure?
    public private(set) var revision: Int
    public private(set) var updatedAt: Date

    public init(samples: [PairSample] = [], now: Date = Date()) {
        self.samples = Self.deduplicated(samples)
        self.phase = .pairs
        self.selectedPairCount = 0
        self.trainingPairIDs = []
        self.answers = []
        self.comparisonIndex = 0
        self.skippedComparisonCount = 0
        self.profile = nil
        self.failure = nil
        self.revision = 0
        self.updatedAt = now
    }

    // MARK: Pair selection

    public var eligibleSamples: [PairSample] {
        samples.filter { Self.isEligible($0) }
    }

    public var eligiblePairCount: Int { eligibleSamples.count }

    public var goodPairCount: Int {
        samples.filter { $0.quality.grade == .good }.count
    }

    public var warningPairCount: Int {
        samples.filter { $0.quality.grade == .warning }.count
    }

    public var rejectedPairCount: Int {
        samples.filter { $0.quality.grade == .rejected }.count
    }

    public var availableTiers: [CalibrationPairTier] {
        CalibrationPairTier.allCases.filter { tier in
            eligiblePairCount >= tier.pairCount
        }
    }

    /// The deepest tier fully backed by eligible pairs, or `nil` below three.
    public var recommendedTier: CalibrationPairTier? {
        CalibrationPairTier.allCases.reversed().first { tier in
            eligiblePairCount >= tier.pairCount
        }
    }

    /// The next tier the user can unlock, or `nil` at eight pairs.
    public var nextTier: CalibrationPairTier? {
        CalibrationPairTier.allCases.first { tier in
            eligiblePairCount < tier.pairCount
        }
    }

    public var canStartComparisons: Bool {
        phase == .pairs && recommendedTier != nil
    }

    public func hasEnoughPairs(for tier: CalibrationPairTier) -> Bool {
        eligiblePairCount >= tier.pairCount
    }

    /// Adds newly selected pairs while the flow is still choosing pairs.
    /// Existing samples and duplicates are preserved exactly once.
    @discardableResult
    public mutating func addSamples(_ newSamples: [PairSample], now: Date = Date()) -> Int {
        guard phase == .pairs, !newSamples.isEmpty else { return 0 }

        var known = Set(samples.map(\.id))
        let additions = newSamples.filter { sample in
            known.insert(sample.id).inserted
        }
        guard !additions.isEmpty else { return 0 }

        samples.append(contentsOf: additions)
        touch(now: now)
        return additions.count
    }

    /// Starts AB with an explicit tier. Passing `nil` uses the recommended
    /// depth (the deepest tier supported by eligible pairs).
    @discardableResult
    public mutating func startComparisons(
        using tier: CalibrationPairTier? = nil,
        now: Date = Date()
    ) -> Bool {
        guard phase == .pairs,
              let chosen = tier ?? recommendedTier,
              hasEnoughPairs(for: chosen)
        else {
            return false
        }

        trainingPairIDs = Array(eligibleSamples.prefix(chosen.pairCount).map(\.id))
        selectedPairCount = chosen.pairCount
        answers = []
        comparisonIndex = 0
        skippedComparisonCount = 0
        profile = nil
        failure = nil
        phase = .comparisons
        touch(now: now)
        return true
    }

    // MARK: AB

    public var currentComparison: CalibrationComparison? {
        guard phase == .comparisons,
              comparisonIndex >= 0,
              comparisonIndex < CalibrationComparison.planned.count
        else {
            return nil
        }
        return CalibrationComparison.planned[comparisonIndex]
    }

    public var interactionCount: Int {
        min(max(comparisonIndex, 0), CalibrationLimits.plannedComparisonCount)
    }

    public var answeredComparisonCount: Int { answers.count }

    public var canFinishComparisons: Bool {
        interactionCount >= CalibrationLimits.minimumComparisonCount
    }

    public var remainingToFinish: Int {
        max(0, CalibrationLimits.minimumComparisonCount - interactionCount)
    }

    public var isABComplete: Bool {
        interactionCount >= CalibrationLimits.plannedComparisonCount
    }

    /// Records one AB answer. The eighth answer advances into the learning
    /// phase; the view model then starts the learner.
    @discardableResult
    public mutating func answerCurrent(choseA: Bool, now: Date = Date()) -> Bool {
        guard phase == .comparisons, let comparison = currentComparison else {
            return false
        }

        let option = choseA ? comparison.optionA : comparison.optionB
        answers.append(
            CalibrationAnswer(
                dimension: comparison.dimension,
                choseA: choseA,
                strengthDelta: option.strengthDelta
            )
        )
        comparisonIndex += 1
        if comparisonIndex >= CalibrationLimits.plannedComparisonCount {
            phase = .learning
        }
        touch(now: now)
        return true
    }

    /// Skips one card without recording an answer. It still counts toward the
    /// six-card minimum, matching the visible progress.
    @discardableResult
    public mutating func skipCurrentComparison(now: Date = Date()) -> Bool {
        guard phase == .comparisons, currentComparison != nil else { return false }

        comparisonIndex += 1
        skippedComparisonCount += 1
        if comparisonIndex >= CalibrationLimits.plannedComparisonCount {
            phase = .learning
        }
        touch(now: now)
        return true
    }

    /// Stops AB early once six cards have been seen, or confirms the automatic
    /// transition after the eighth card.
    @discardableResult
    public mutating func finishComparisons(now: Date = Date()) -> Bool {
        guard phase == .comparisons || phase == .learning else { return false }
        guard canFinishComparisons else { return false }

        if phase != .learning {
            phase = .learning
            touch(now: now)
        }
        return true
    }

    public var learningRequest: CalibrationLearningRequest? {
        let pairs = trainingSamples
        guard pairs.count == selectedPairCount,
              selectedPairCount >= CalibrationLimits.minimumPairCount
        else {
            return nil
        }
        return CalibrationLearningRequest(samples: pairs, answers: answers)
    }

    public var trainingSamples: [PairSample] {
        let byID = Dictionary(uniqueKeysWithValues: eligibleSamples.map { ($0.id, $0) })
        return trainingPairIDs.compactMap { byID[$0] }
    }

    public var skippedABEntirely: Bool {
        skippedComparisonCount == CalibrationLimits.plannedComparisonCount
    }

    // MARK: Learning / result

    @discardableResult
    public mutating func completeLearning(_ profile: StyleProfile, now: Date = Date()) -> Bool {
        guard phase == .learning else { return false }
        self.profile = profile
        failure = nil
        phase = .result
        touch(now: now)
        return true
    }

    @discardableResult
    public mutating func failLearning(
        _ failure: CalibrationFailure,
        now: Date = Date()
    ) -> Bool {
        guard phase == .learning else { return false }
        self.failure = failure
        phase = .failed
        touch(now: now)
        return true
    }

    @discardableResult
    public mutating func retryLearning(now: Date = Date()) -> Bool {
        guard phase == .failed else { return false }
        failure = nil
        phase = .learning
        touch(now: now)
        return true
    }

    /// Cancels learning or saving and keeps every pair and answer. The user can
    /// finish again from the comparison screen.
    @discardableResult
    public mutating func cancelLearning(now: Date = Date()) -> Bool {
        guard phase == .learning || phase == .failed else { return false }
        failure = nil
        phase = .comparisons
        touch(now: now)
        return true
    }

    /// Enters the saving phase for a natural default profile.
    @discardableResult
    public mutating func beginNaturalDefault(now: Date = Date()) -> Bool {
        guard phase != .result else { return false }
        failure = nil
        profile = nil
        phase = .learning
        touch(now: now)
        return true
    }

    /// A neutral profile that never requires a learner or account.
    public static func naturalDefaultProfile(now: Date = Date()) -> StyleProfile {
        StyleProfile(
            pairCount: 0,
            confidence: .trial,
            tags: [naturalDefaultTag],
            updatedAt: now
        )
    }

    public var isNaturalDefaultResult: Bool {
        profile?.tags.contains(Self.naturalDefaultTag) == true
    }

    public static let naturalDefaultTag = "calibration.tag.naturalDefault"

    // MARK: Reset / resume

    /// Returns to pair selection while keeping the samples. Answers, AB
    /// progress and the previous profile are cleared.
    @discardableResult
    public mutating func recalibrate(now: Date = Date()) -> Bool {
        guard !samples.isEmpty || phase != .pairs else { return false }

        selectedPairCount = 0
        trainingPairIDs = []
        answers = []
        comparisonIndex = 0
        skippedComparisonCount = 0
        profile = nil
        failure = nil
        phase = .pairs
        touch(now: now)
        return true
    }

    // MARK: Persistence

    public func makeDraft() -> CalibrationDraft {
        CalibrationDraft(
            revision: revision,
            phase: phase,
            selectedPairCount: selectedPairCount,
            trainingPairIDs: trainingPairIDs,
            answers: answers,
            comparisonIndex: comparisonIndex,
            skippedComparisonCount: skippedComparisonCount,
            profile: profile,
            updatedAt: updatedAt
        )
    }

    /// Merges a draft against the pair samples currently available on device.
    ///
    /// A completed result can always be restored. AB progress requires every
    /// selected pair id to be present; otherwise the flow stays on pair
    /// selection and returns `.missingPairs` instead of silently learning from
    /// a smaller set.
    @discardableResult
    public mutating func restore(from draft: CalibrationDraft) -> CalibrationRestoreOutcome {
        guard draft.version == CalibrationDraft.currentVersion else {
            return .incompatibleVersion(
                expected: CalibrationDraft.currentVersion,
                found: draft.version
            )
        }

        revision = max(revision, draft.revision)
        updatedAt = draft.updatedAt

        if draft.phase == .result, let restoredProfile = draft.profile {
            selectedPairCount = draft.selectedPairCount
            trainingPairIDs = draft.trainingPairIDs
            answers = draft.answers
            comparisonIndex = min(
                max(draft.comparisonIndex, 0),
                CalibrationLimits.plannedComparisonCount
            )
            skippedComparisonCount = min(
                max(draft.skippedComparisonCount, 0),
                comparisonIndex
            )
            profile = restoredProfile
            failure = nil
            phase = .result
            return .restored
        }

        if draft.phase == .pairs {
            selectedPairCount = 0
            trainingPairIDs = []
            answers = []
            comparisonIndex = 0
            skippedComparisonCount = 0
            profile = nil
            failure = nil
            phase = .pairs
            return .restored
        }

        guard let tier = CalibrationPairTier(rawValue: draft.selectedPairCount),
              draft.trainingPairIDs.count == tier.pairCount
        else {
            return .missingPairs(
                required: draft.selectedPairCount,
                available: eligiblePairCount
            )
        }

        let availableIDs = Set(eligibleSamples.map(\.id))
        let missingCount = draft.trainingPairIDs.filter { !availableIDs.contains($0) }.count
        guard missingCount == 0 else {
            return .missingPairs(
                required: draft.trainingPairIDs.count,
                available: draft.trainingPairIDs.count - missingCount
            )
        }

        selectedPairCount = tier.pairCount
        trainingPairIDs = draft.trainingPairIDs
        answers = Array(draft.answers.prefix(CalibrationLimits.plannedComparisonCount))
        comparisonIndex = min(
            max(draft.comparisonIndex, 0),
            CalibrationLimits.plannedComparisonCount
        )
        skippedComparisonCount = min(
            max(draft.skippedComparisonCount, 0),
            comparisonIndex
        )
        profile = nil
        failure = nil
        // Learning is restarted from the persisted answers; a failed save is
        // also retried from the comparison screen.
        phase = .comparisons
        return .restored
    }

    // MARK: Helpers

    public static func isEligible(_ sample: PairSample) -> Bool {
        sample.quality.grade != .rejected
    }

    private mutating func touch(now: Date) {
        revision += 1
        updatedAt = now
    }

    private static func deduplicated(_ samples: [PairSample]) -> [PairSample] {
        var seen = Set<UUID>()
        return samples.filter { seen.insert($0.id).inserted }
    }
}
