import Foundation
import SwiftData

/// SwiftData metadata for a 3/5/8-pair calibration session.
///
/// Only opaque pair references are persisted; the images themselves stay in the
/// App's in-memory session and are never copied into this store.
@Model
public final class PairSessionRecord {
    @Attribute(.unique) public var id: UUID
    /// Opaque local tokens, one per accepted pair. Never photo-library IDs.
    public var pairReferences: [String]
    /// Requested tier: 3, 5 or 8 (the store accepts 3...8).
    public var targetPairCount: Int
    public var abChoiceCount: Int
    /// Raw value of ``PairSessionStatus``.
    public var statusRawValue: String
    public var createdAt: Date
    public var updatedAt: Date

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
        self.abChoiceCount = max(0, abChoiceCount)
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Typed view of ``statusRawValue``. Not persisted.
    public var status: PairSessionStatus {
        get { PairSessionStatus(rawValue: statusRawValue) ?? .draft }
        set { statusRawValue = newValue.rawValue }
    }
}
