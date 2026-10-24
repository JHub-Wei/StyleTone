import Foundation
import StyleToneCore

/// A `DateProviding` double pinned to one instant.
public struct FixedDateProvider: DateProviding, Sendable {
    /// 2026-01-01T00:00:00Z, the project reference date.
    public static let reference = Date(timeIntervalSince1970: 1_767_225_600)

    public let now: Date

    public init(_ date: Date = FixedDateProvider.reference) {
        self.now = date
    }
}

/// A thread-safe `DateProviding` double that can be advanced or reset.
///
/// Useful for expiry/grace-period tests without waiting on wall-clock time.
public final class AdjustableTestClock: DateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(now: Date = FixedDateProvider.reference) {
        self.current = now
    }

    public var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }

    public func set(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }
}
