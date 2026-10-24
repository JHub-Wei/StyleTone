import Foundation
import StyleToneCore

// MARK: - Slots and targets

/// One of the two photographs that make a pair.
public enum PairingSlot: String, CaseIterable, Identifiable, Sendable, Codable {
    /// The photo the user started from.
    case original
    /// The edited/retouched result the user wants the app to learn from.
    case edited

    public var id: String { rawValue }

    /// The other slot. A pair always has exactly one of each.
    public var counterpart: PairingSlot {
        switch self {
        case .original: return .edited
        case .edited: return .original
        }
    }
}

/// How many usable pairs the user is aiming for.
///
/// The product flow offers 3, 5 and 8 pairs: three is the trial minimum, five
/// reaches the standard confidence band and eight the stable one. The UI never
/// forces a target; it only shows progress towards the selected one.
public enum PairingTarget: Int, CaseIterable, Identifiable, Sendable {
    case three = 3
    case five = 5
    case eight = 8

    public var id: Int { rawValue }

    /// Number of usable pairs the target asks for.
    public var count: Int { rawValue }

    /// Compact label for the selector and the progress counter.
    public var label: String { "\(rawValue)" }

    /// The trial target used for a fresh session.
    public static let defaultTarget: PairingTarget = .three

    public init?(count: Int) {
        self.init(rawValue: count)
    }
}

/// The lifecycle stage of the pairing session.
public enum PairingStage: String, Sendable, Codable, Equatable {
    /// The user is adding and reviewing pairs.
    case editing
    /// The user finished with enough usable pairs.
    case completed
    /// The user skipped calibration and will use the natural default.
    case skipped

    public var isTerminal: Bool {
        self != .editing
    }
}

// MARK: - Photos

/// A picked photo with the metadata the pairing UI needs.
///
/// The pixels stay in memory for the lifetime of the session. The metadata
/// (source size, byte count, optional asset identifier) is what the session
/// store persists, so it never writes photographs to disk.
public struct PairingPhoto: Sendable, Equatable {
    /// Downsampled, color-managed image used for display and quality checks.
    public let asset: ImageAsset
    /// Pixel size of the file the user picked, before downsampling.
    public let sourcePixelSize: PixelSize
    /// Opaque photo-library identifier, when the picker provides one.
    public let sourceIdentifier: String?
    /// Size of the encoded payload that was decoded.
    public let byteCount: Int
    /// When the photo was imported.
    public let importedAt: Date

    public init(
        asset: ImageAsset,
        sourcePixelSize: PixelSize,
        sourceIdentifier: String? = nil,
        byteCount: Int,
        importedAt: Date
    ) {
        self.asset = asset
        self.sourcePixelSize = sourcePixelSize
        self.sourceIdentifier = sourceIdentifier
        self.byteCount = byteCount
        self.importedAt = importedAt
    }

    /// Size of the in-memory image shown in the pairing card.
    public var displayPixelSize: PixelSize { asset.pixelSize }

    /// Photos compare by provenance and display geometry, never by pixels.
    public static func == (lhs: PairingPhoto, rhs: PairingPhoto) -> Bool {
        lhs.asset.pixelSize == rhs.asset.pixelSize
            && lhs.sourcePixelSize == rhs.sourcePixelSize
            && lhs.sourceIdentifier == rhs.sourceIdentifier
            && lhs.byteCount == rhs.byteCount
            && lhs.importedAt == rhs.importedAt
    }
}

/// A payload handed from the system photo picker to the import pipeline.
///
/// `Data` is deliberate: the picker copies the selection into the app's
/// temporary directory, and the importer decodes it without retaining a file
/// URL. Nothing is copied into a shared container.
public struct PairingPickedPhoto: Sendable, Equatable {
    public let data: Data
    public let sourceIdentifier: String?

    public init(data: Data, sourceIdentifier: String? = nil) {
        self.data = data
        self.sourceIdentifier = sourceIdentifier
    }
}

/// Which photos the next system picker presentation asks for.
public enum PairingPickMode: Sendable, Equatable {
    /// Pick the original first, then the edited photo in one presentation.
    case pair
    /// Pick a single photo for one slot (add or replace).
    case slot(PairingSlot)

    /// Maximum number of photos the picker should accept.
    public var selectionLimit: Int {
        switch self {
        case .pair: return 2
        case .slot: return 1
        }
    }

    /// Slots in the order the picker returns photos.
    public var slots: [PairingSlot] {
        switch self {
        case .pair: return [.original, .edited]
        case let .slot(slot): return [slot]
        }
    }

    /// Instruction shown above the pair list before the picker opens.
    public var isPairSelection: Bool {
        if case .pair = self { return true }
        return false
    }
}

/// A pending system-picker presentation for one pair.
public struct PairingPickRequest: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let pairID: UUID
    public let mode: PairingPickMode

    public init(id: UUID = UUID(), pairID: UUID, mode: PairingPickMode) {
        self.id = id
        self.pairID = pairID
        self.mode = mode
    }
}

// MARK: - Picker availability

/// Why the system photo picker cannot be shown.
public enum PairingPickerUnavailableReason: String, Sendable, Equatable, CaseIterable {
    /// The current platform has no PHPicker (macOS unit tests, previews).
    case notSupportedOnThisPlatform
    /// The system restricts photo access, for example by parental controls.
    case photoLibraryRestricted
    /// No cause could be determined.
    case unknown
}

/// Whether the system photo picker can be presented.
///
/// PHPicker runs out of process and needs no photo-library authorization, so
/// the normal value is `.available` even when the user never granted access.
public enum PairingPickerAvailability: Sendable, Equatable {
    case available
    case unavailable(PairingPickerUnavailableReason)

    public var isAvailable: Bool {
        self == .available
    }
}

/// Supplies the picker availability, so a host can react to system
/// restrictions without the screen importing Photos.
public protocol PairingPickerAvailabilityProviding: Sendable {
    func currentAvailability() async -> PairingPickerAvailability
}

/// Default availability: the picker is available wherever PHPicker exists.
public struct SystemPairingPickerAvailability: PairingPickerAvailabilityProviding {
    public init() {}

    public func currentAvailability() async -> PairingPickerAvailability {
        #if canImport(UIKit) && canImport(PhotosUI)
        return .available
        #else
        return .unavailable(.notSupportedOnThisPlatform)
        #endif
    }
}

// MARK: - Quality state

/// Why a quality check could not finish.
public enum PairingAssessmentFailureCode: String, Sendable, Equatable, Codable, CaseIterable {
    /// No `PairQualityAnalyzing` implementation was injected (WP-05 not wired).
    case analyzerUnavailable
    /// The analyzer ran but failed.
    case analysisFailed
    /// The check was cancelled because the pair changed.
    case cancelled
    /// An unexpected error.
    case unknown
}

/// A failed quality check with enough information to offer a retry.
public struct PairingAssessmentFailure: Error, Sendable, Equatable {
    public let code: PairingAssessmentFailureCode
    public let isRetryable: Bool

    public init(code: PairingAssessmentFailureCode, isRetryable: Bool = true) {
        self.code = code
        self.isRetryable = isRetryable
    }

    /// Maps an analyzer error onto the UI taxonomy without leaking details.
    public static func map(_ error: Error) -> PairingAssessmentFailure {
        if error is CancellationError {
            return PairingAssessmentFailure(code: .cancelled)
        }
        if let styleToneError = error as? StyleToneError {
            switch styleToneError {
            case .cancelled:
                return PairingAssessmentFailure(code: .cancelled)
            case .invalidState:
                return PairingAssessmentFailure(code: .analyzerUnavailable)
            case .imageAnalysisFailed, .invalidImage, .imageDecodingFailed:
                return PairingAssessmentFailure(code: .analysisFailed)
            default:
                return PairingAssessmentFailure(code: .unknown)
            }
        }
        return PairingAssessmentFailure(code: .unknown)
    }
}

/// The quality-check state of one pair.
public enum PairingAssessmentState: Sendable, Equatable {
    /// At least one slot is empty.
    case waitingForImages
    /// The analyzer is running.
    case assessing
    /// A grade is available.
    case completed(PairQuality)
    /// The check failed and can be retried.
    case failed(PairingAssessmentFailure)

    public var quality: PairQuality? {
        if case let .completed(quality) = self { return quality }
        return nil
    }

    public var failure: PairingAssessmentFailure? {
        if case let .failed(failure) = self { return failure }
        return nil
    }

    public var isAssessing: Bool {
        if case .assessing = self { return true }
        return false
    }

    public var isWaitingForImages: Bool {
        if case .waitingForImages = self { return true }
        return false
    }
}

// MARK: - Pairs

/// One original/edited pair and its current quality state.
public struct PairingPairState: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public internal(set) var original: PairingPhoto?
    public internal(set) var edited: PairingPhoto?
    public internal(set) var assessment: PairingAssessmentState
    public internal(set) var updatedAt: Date
    /// Increments whenever a photo is attached or removed. Async quality
    /// results are dropped when the revision moved on.
    public internal(set) var contentRevision: Int
    /// The persisted session had an original that is not in memory any more.
    public internal(set) var needsReselectOriginal: Bool
    /// The persisted session had an edited photo that is not in memory.
    public internal(set) var needsReselectEdited: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        original: PairingPhoto? = nil,
        edited: PairingPhoto? = nil,
        assessment: PairingAssessmentState = .waitingForImages,
        updatedAt: Date,
        contentRevision: Int = 0,
        needsReselectOriginal: Bool = false,
        needsReselectEdited: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.original = original
        self.edited = edited
        self.assessment = assessment
        self.updatedAt = updatedAt
        self.contentRevision = contentRevision
        self.needsReselectOriginal = needsReselectOriginal
        self.needsReselectEdited = needsReselectEdited
    }

    public func photo(for slot: PairingSlot) -> PairingPhoto? {
        switch slot {
        case .original: return original
        case .edited: return edited
        }
    }

    public func needsReselect(for slot: PairingSlot) -> Bool {
        switch slot {
        case .original: return needsReselectOriginal
        case .edited: return needsReselectEdited
        }
    }

    /// Both slots hold a photo.
    public var isComplete: Bool {
        original != nil && edited != nil
    }

    /// Slots without a photo, in picker order.
    public var missingSlots: [PairingSlot] {
        var slots: [PairingSlot] = []
        if original == nil { slots.append(.original) }
        if edited == nil { slots.append(.edited) }
        return slots
    }

    /// Usable photos that survived a relaunch but need to be picked again.
    public var staleSlots: [PairingSlot] {
        PairingSlot.allCases.filter { needsReselect(for: $0) }
    }

    public var quality: PairQuality? { assessment.quality }

    public var grade: PairQualityGrade? { quality?.grade }

    /// A completed check that is not red.
    public var isLearnable: Bool {
        guard isComplete, let quality else { return false }
        return quality.grade != .rejected
    }

    /// Red pairs never reach learning.
    public var isRejected: Bool {
        quality?.grade == .rejected
    }
}

/// A pair plus the 1-based number shown in the list.
public struct PairingPairRow: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let number: Int
    public let pair: PairingPairState

    public init(number: Int, pair: PairingPairState) {
        self.id = pair.id
        self.number = number
        self.pair = pair
    }
}

// MARK: - Progress, timing, summary

/// Everything the progress header renders, derived from the session.
public struct PairingProgress: Sendable, Equatable {
    /// Pairs that count towards the target (complete and not rejected).
    public let eligible: Int
    public let target: Int
    public let good: Int
    public let warning: Int
    public let rejected: Int
    /// Pairs still waiting for a photo or a quality result.
    public let pending: Int
    /// All pairs in the session, including empty placeholders.
    public let total: Int

    public init(
        eligible: Int,
        target: Int,
        good: Int,
        warning: Int,
        rejected: Int,
        pending: Int,
        total: Int
    ) {
        self.eligible = max(0, eligible)
        self.target = max(1, target)
        self.good = max(0, good)
        self.warning = max(0, warning)
        self.rejected = max(0, rejected)
        self.pending = max(0, pending)
        self.total = max(0, total)
    }

    public var fraction: Double {
        min(1, Double(eligible) / Double(target))
    }

    /// Compact counter such as `1/3`, `1/5` or `1/8`.
    public var label: String {
        "\(min(eligible, target))/\(target)"
    }

    public var reachedTarget: Bool {
        eligible >= target
    }

    public var hasAnyPair: Bool {
        total > 0
    }
}

/// Wall-clock instrumentation for the 12-pairs-in-6-minutes acceptance check.
public struct PairingTimeline: Sendable, Equatable {
    public let startedAt: Date
    public internal(set) var lastActivityAt: Date
    /// One timestamp per pair that became complete (both photos present).
    public internal(set) var completedPairTimestamps: [Date]

    public init(startedAt: Date) {
        self.startedAt = startedAt
        self.lastActivityAt = startedAt
        self.completedPairTimestamps = []
    }

    public func elapsed(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(startedAt))
    }

    public func averageSecondsPerPair(at date: Date) -> TimeInterval? {
        guard !completedPairTimestamps.isEmpty else { return nil }
        let last = completedPairTimestamps[completedPairTimestamps.count - 1]
        return max(0, last.timeIntervalSince(startedAt)) / Double(completedPairTimestamps.count)
    }

    /// `true` when the session spent at most `budget` seconds up to `date`.
    public func meetsTimeBudget(at date: Date, budget: TimeInterval) -> Bool {
        elapsed(at: date) <= budget
    }
}

/// Counts reported to the calibration flow after the user finishes or skips.
public struct PairingSessionSummary: Sendable, Equatable {
    public let stage: PairingStage
    public let target: Int
    public let totalPairs: Int
    public let goodCount: Int
    public let warningCount: Int
    public let rejectedCount: Int
    public let learnableCount: Int
    public let elapsed: TimeInterval
    public let budgetPairCount: Int
    public let budgetSeconds: TimeInterval

    public init(
        stage: PairingStage,
        target: Int,
        totalPairs: Int,
        goodCount: Int,
        warningCount: Int,
        rejectedCount: Int,
        learnableCount: Int,
        elapsed: TimeInterval,
        budgetPairCount: Int,
        budgetSeconds: TimeInterval
    ) {
        self.stage = stage
        self.target = target
        self.totalPairs = totalPairs
        self.goodCount = goodCount
        self.warningCount = warningCount
        self.rejectedCount = rejectedCount
        self.learnableCount = learnableCount
        self.elapsed = max(0, elapsed)
        self.budgetPairCount = budgetPairCount
        self.budgetSeconds = budgetSeconds
    }

    /// The acceptance target: 12 pairs inside six minutes.
    public var metTimeBudget: Bool {
        elapsed <= budgetSeconds
    }
}

// MARK: - Deletion backup

/// One level of undo for a deleted pair or a removed photo.
public struct PairingDeletionBackup: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        /// A whole pair, with the index it occupied.
        case pair(PairingPairState, index: Int)
        /// One photo of a pair, plus the state to restore with it.
        case photo(
            slot: PairingSlot,
            photo: PairingPhoto,
            previousAssessment: PairingAssessmentState,
            previousNeedsReselect: Bool
        )
    }

    public let pairID: UUID
    public let content: Content
    public let deletedAt: Date

    public init(pairID: UUID, content: Content, deletedAt: Date) {
        self.pairID = pairID
        self.content = content
        self.deletedAt = deletedAt
    }

    public var deletedSlot: PairingSlot? {
        if case let .photo(slot, _, _, _) = content { return slot }
        return nil
    }

    public var isPairDeletion: Bool {
        if case .pair = content { return true }
        return false
    }
}

// MARK: - Save state

/// The state of the metadata-only session save.
public enum PairingSaveState: Sendable, Equatable {
    case idle
    case saving
    case saved(Date)
    case failed

    public var isSaving: Bool {
        self == .saving
    }

    public var didFail: Bool {
        self == .failed
    }
}

// MARK: - Default analyzer

/// Stand-in used until the host injects WP-05's analyzer.
///
/// It deliberately fails instead of guessing a grade: an ungraded pair must
/// never reach learning, so the UI keeps "continue" disabled and offers a
/// retry while this is installed.
public struct UnavailablePairQualityAnalyzer: PairQualityAnalyzing {
    public init() {}

    public func assess(original: ImageAsset, edited: ImageAsset) async throws -> PairQuality {
        throw StyleToneError.invalidState
    }
}
