import Foundation
import SwiftData

/// SwiftData metadata for one local edit session.
///
/// The record deliberately does not store pixels or file names: `inputReference`
/// is an opaque local token owned by the App (for example a UUID), and the
/// adjustments are a small Codable JSON blob. Photos never enter this package.
@Model
public final class EditRecord {
    @Attribute(.unique) public var id: UUID
    /// Identifier of the style profile that produced the edit, when known.
    public var styleID: UUID?
    /// Opaque local reference; never a file path or photo-library identifier.
    public var inputReference: String
    /// JSON-encoded ``ManualAdjustments``.
    public var adjustmentsData: Data
    public var createdAt: Date
    public var exported: Bool
    public var exportedAt: Date?

    public init(
        id: UUID,
        styleID: UUID?,
        inputReference: String,
        adjustmentsData: Data,
        createdAt: Date,
        exported: Bool,
        exportedAt: Date?
    ) {
        self.id = id
        self.styleID = styleID
        self.inputReference = inputReference
        self.adjustmentsData = adjustmentsData
        self.createdAt = createdAt
        self.exported = exported
        self.exportedAt = exportedAt
    }
}
