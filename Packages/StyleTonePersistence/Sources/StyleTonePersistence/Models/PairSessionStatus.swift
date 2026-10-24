import Foundation

/// Lifecycle of a local calibration pairing session.
public enum PairSessionStatus: String, Codable, Sendable, CaseIterable {
    /// The user is still selecting or replacing pairs.
    case draft
    /// The session reached its target pair count.
    case completed
    /// The user explicitly skipped calibration.
    case skipped
    /// The session was abandoned.
    case cancelled
}
