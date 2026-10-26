import Foundation

/// Bounded undo/redo history for editor state snapshots.
///
/// Continuous gestures are grouped by the view model: it records the state
/// captured at the start of the gesture once, so dragging a slider from 0 to 1
/// is one undo step, not sixty. The capacity is at least 20 steps (the product
/// requirement) and defaults to 30.
public struct EditorHistory: Sendable, Equatable {
    public static let minimumCapacity = 20
    public static let defaultCapacity = 30
    public static let maximumCapacity = 100

    public let capacity: Int
    public private(set) var past: [EditorEditState]
    public private(set) var future: [EditorEditState]

    public init(capacity: Int = EditorHistory.defaultCapacity) {
        self.capacity = min(max(capacity, Self.minimumCapacity), Self.maximumCapacity)
        self.past = []
        self.future = []
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var undoCount: Int { past.count }
    public var redoCount: Int { future.count }

    /// Records the state before a completed edit. A new edit always clears the
    /// redo branch.
    public mutating func record(_ previous: EditorEditState) {
        past.append(previous)
        trimPast()
        future.removeAll()
    }

    /// Pops one previous state and stores `current` on the redo stack.
    public mutating func undo(current: EditorEditState) -> EditorEditState? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        trimFuture()
        return previous
    }

    /// Pops one redo state and stores `current` on the undo stack.
    public mutating func redo(current: EditorEditState) -> EditorEditState? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        trimPast()
        return next
    }

    public mutating func clear() {
        past.removeAll()
        future.removeAll()
    }

    private mutating func trimPast() {
        let overflow = past.count - capacity
        if overflow > 0 {
            past.removeFirst(overflow)
        }
    }

    private mutating func trimFuture() {
        let overflow = future.count - capacity
        if overflow > 0 {
            future.removeFirst(overflow)
        }
    }
}
