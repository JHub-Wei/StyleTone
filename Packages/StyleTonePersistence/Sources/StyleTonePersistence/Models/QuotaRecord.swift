import Foundation
import SwiftData

/// SwiftData singleton for the free-export quota.
///
/// The quota is local-only and has no account or server counterpart. Deleting
/// all data resets it, which the product contract explicitly allows.
@Model
public final class QuotaRecord {
    @Attribute(.unique) public var key: String
    public var freeExportsUsed: Int
    public var updatedAt: Date

    public init(
        key: String = QuotaPolicy.singletonKey,
        freeExportsUsed: Int,
        updatedAt: Date
    ) {
        self.key = key
        self.freeExportsUsed = max(0, freeExportsUsed)
        self.updatedAt = updatedAt
    }
}
