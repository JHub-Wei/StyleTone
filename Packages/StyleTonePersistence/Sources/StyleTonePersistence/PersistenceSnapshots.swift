import Foundation
import StyleToneCore

/// Sendable projection of `StyleProfileRecord` for callers outside the store.
public struct StyleProfileMetadata: Sendable, Equatable {
    public let id: UUID
    public let schemaVersion: Int
    public let algorithmVersion: String
    public let pairCount: Int
    public let confidence: ConfidenceLevel
    public let tags: [String]
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        schemaVersion: Int,
        algorithmVersion: String,
        pairCount: Int,
        confidence: ConfidenceLevel,
        tags: [String],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.algorithmVersion = algorithmVersion
        self.pairCount = pairCount
        self.confidence = confidence
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Input for ``SwiftDataStyleProfileStore/recordEdit(_:)``.
public struct EditDraft: Sendable, Equatable {
    /// Opaque local token for the edited photo; never a path or library ID.
    public var inputReference: String
    public var adjustments: ManualAdjustments
    public var styleID: UUID?

    public init(
        inputReference: String,
        adjustments: ManualAdjustments,
        styleID: UUID? = nil
    ) {
        self.inputReference = inputReference
        self.adjustments = adjustments
        self.styleID = styleID
    }
}

/// Sendable projection of `EditRecord`.
public struct EditRecordSnapshot: Sendable, Equatable {
    public let id: UUID
    public let styleID: UUID?
    public let inputReference: String
    public let adjustments: ManualAdjustments
    public let createdAt: Date
    public let exported: Bool
    public let exportedAt: Date?

    public init(
        id: UUID,
        styleID: UUID?,
        inputReference: String,
        adjustments: ManualAdjustments,
        createdAt: Date,
        exported: Bool,
        exportedAt: Date?
    ) {
        self.id = id
        self.styleID = styleID
        self.inputReference = inputReference
        self.adjustments = adjustments
        self.createdAt = createdAt
        self.exported = exported
        self.exportedAt = exportedAt
    }
}

/// Input for ``SwiftDataStyleProfileStore/savePairSession(_:)``.
///
/// Pass an existing `id` to update a session in place; omit it to create one.
public struct PairSessionDraft: Sendable, Equatable {
    public var id: UUID?
    public var pairReferences: [String]
    public var targetPairCount: Int
    public var abChoiceCount: Int
    public var status: PairSessionStatus

    public init(
        id: UUID? = nil,
        pairReferences: [String],
        targetPairCount: Int,
        abChoiceCount: Int = 0,
        status: PairSessionStatus = .draft
    ) {
        self.id = id
        self.pairReferences = pairReferences
        self.targetPairCount = targetPairCount
        self.abChoiceCount = abChoiceCount
        self.status = status
    }
}

/// Sendable projection of `PairSessionRecord`.
public struct PairSessionSnapshot: Sendable, Equatable {
    public let id: UUID
    public let pairReferences: [String]
    public let targetPairCount: Int
    public let abChoiceCount: Int
    public let status: PairSessionStatus
    public let createdAt: Date
    public let updatedAt: Date

    public var pairCount: Int { pairReferences.count }

    public init(
        id: UUID,
        pairReferences: [String],
        targetPairCount: Int,
        abChoiceCount: Int,
        status: PairSessionStatus,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.pairReferences = pairReferences
        self.targetPairCount = targetPairCount
        self.abChoiceCount = abChoiceCount
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Local quota policy shared by the store and its snapshots.
public enum QuotaPolicy: Sendable {
    /// Stable singleton key. A future multi-profile store can add scopes here.
    public static let singletonKey = "default"
    /// Number of successful exports counted against the free tier.
    public static let freeExportLimit = 3
}

/// Sendable view of the local free-export quota.
public struct QuotaSnapshot: Sendable, Equatable {
    public static let freeExportLimit = QuotaPolicy.freeExportLimit

    public let freeExportsUsed: Int
    public let updatedAt: Date

    public var remainingFreeExports: Int {
        max(0, Self.freeExportLimit - freeExportsUsed)
    }

    public var isFreeExportAvailable: Bool {
        freeExportsUsed < Self.freeExportLimit
    }

    public init(freeExportsUsed: Int, updatedAt: Date) {
        self.freeExportsUsed = max(0, freeExportsUsed)
        self.updatedAt = updatedAt
    }
}
