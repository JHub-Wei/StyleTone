import Foundation
import StyleToneCore

/// Fixed limits for the 3/5/8 calibration flow.
///
/// The pair-stage target is a product budget, not a timer that blocks the user:
/// three pairs should be comfortable to finish within four minutes. The AB
/// stage plans eight cards but lets the user finish after six.
public enum CalibrationLimits {
    public static let minimumPairCount = 3
    public static let mediumPairCount = 5
    public static let maximumPairCount = 8
    public static let minimumComparisonCount = 6
    public static let plannedComparisonCount = 8
    public static let pairStageTargetSeconds: TimeInterval = 4 * 60
}

/// One of the three supported calibration depths.
public enum CalibrationPairTier: Int, CaseIterable, Codable, Sendable, Identifiable {
    case three = 3
    case five = 5
    case eight = 8

    public var id: Int { rawValue }

    public var pairCount: Int { rawValue }

    /// The next deeper tier, or `nil` at eight pairs.
    public var next: CalibrationPairTier? {
        switch self {
        case .three: return .five
        case .five: return .eight
        case .eight: return nil
        }
    }
}

/// The durable part of the calibration flow.
public enum CalibrationPhase: String, Codable, Sendable, Equatable {
    /// Choosing three, five or eight pairs.
    case pairs
    /// Answering AB cards or skipping individual cards.
    case comparisons
    /// Calling the learner or saving the resulting profile.
    case learning
    /// A profile is ready.
    case result
    /// Learning or saving failed. Pairs and answers are retained.
    case failed
}

/// A recoverable calibration failure.
public struct CalibrationFailure: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case learning
        case savingProfile
        case restoring
        case missingPairs
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    /// Whether retrying the failed operation can help.
    public var canRetry: Bool {
        switch kind {
        case .learning, .savingProfile: return true
        case .restoring, .missingPairs: return false
        }
    }
}

/// A non-blocking message shown above the current stage.
public enum CalibrationNotice: String, Sendable, Equatable {
    case restored
    case cancelledLearning
    case progressUnavailable
    case missingPairs
}

/// A single AB option. It is a rendering placeholder until WP-11/WP-17 wire
/// previews; only the preference and strength direction are learned.
public struct CalibrationComparisonOption: Sendable, Equatable {
    public enum Variant: String, Sendable, Equatable {
        case low
        case high
    }

    public let variant: Variant
    public let detailKey: LocalizationKey
    /// -1...1 direction used by `CalibrationAnswer`.
    public let strengthDelta: Double

    public init(variant: Variant, detailKey: LocalizationKey, strengthDelta: Double) {
        self.variant = variant
        self.detailKey = detailKey
        self.strengthDelta = min(max(strengthDelta, -1), 1)
    }
}

/// One AB card. Cards are deterministic so a restored session asks the same
/// question again.
public struct CalibrationComparison: Identifiable, Sendable, Equatable {
    public let index: Int
    public let dimension: CalibrationDimension
    public let optionA: CalibrationComparisonOption
    public let optionB: CalibrationComparisonOption

    public var id: Int { index }

    public var dimensionKey: LocalizationKey {
        CalibrationCopy.dimensionKey(for: dimension)
    }

    public init(
        index: Int,
        dimension: CalibrationDimension,
        optionA: CalibrationComparisonOption,
        optionB: CalibrationComparisonOption
    ) {
        self.index = index
        self.dimension = dimension
        self.optionA = optionA
        self.optionB = optionB
    }

    /// The deterministic 8-card plan. Every dimension appears at least once;
    /// naturalness appears twice because it modulates the whole look.
    public static let planned: [CalibrationComparison] = {
        let sequence: [(dimension: CalibrationDimension, swapsSides: Bool)] = [
            (.tone, false),
            (.skinTone, true),
            (.smoothing, false),
            (.naturalness, true),
            (.faceSlim, false),
            (.bodySlim, true),
            (.legLength, false),
            (.naturalness, false),
        ]

        return sequence.enumerated().map { index, item in
            let low = CalibrationComparisonOption(
                variant: .low,
                detailKey: CalibrationCopy.detailKey(for: item.dimension, variant: .low),
                strengthDelta: -0.35
            )
            let high = CalibrationComparisonOption(
                variant: .high,
                detailKey: CalibrationCopy.detailKey(for: item.dimension, variant: .high),
                strengthDelta: 0.35
            )
            return CalibrationComparison(
                index: index,
                dimension: item.dimension,
                optionA: item.swapsSides ? high : low,
                optionB: item.swapsSides ? low : high
            )
        }
    }()
}

/// The small JSON payload persisted for cancel/resume.
///
/// Images are never copied into this payload. Only pair identifiers selected
/// from the local pairing session are stored; the caller supplies the current
/// `PairSample` values when restoring.
public struct CalibrationDraft: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var revision: Int
    public var phase: CalibrationPhase
    public var selectedPairCount: Int
    public var trainingPairIDs: [UUID]
    public var answers: [CalibrationAnswer]
    public var comparisonIndex: Int
    public var skippedComparisonCount: Int
    public var profile: StyleProfile?
    public var updatedAt: Date

    public init(
        version: Int = CalibrationDraft.currentVersion,
        revision: Int = 0,
        phase: CalibrationPhase = .pairs,
        selectedPairCount: Int = 0,
        trainingPairIDs: [UUID] = [],
        answers: [CalibrationAnswer] = [],
        comparisonIndex: Int = 0,
        skippedComparisonCount: Int = 0,
        profile: StyleProfile? = nil,
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.revision = revision
        self.phase = phase
        self.selectedPairCount = selectedPairCount
        self.trainingPairIDs = trainingPairIDs
        self.answers = answers
        self.comparisonIndex = comparisonIndex
        self.skippedComparisonCount = skippedComparisonCount
        self.profile = profile
        self.updatedAt = updatedAt
    }
}

/// Result of merging a persisted draft into a flow that already has local
/// pair samples.
public enum CalibrationRestoreOutcome: Sendable, Equatable {
    case restored
    case incompatibleVersion(expected: Int, found: Int)
    case missingPairs(required: Int, available: Int)
}
