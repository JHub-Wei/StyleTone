import Foundation

// MARK: - Reason

/// Why a foreground action was interrupted.
public enum InterruptionReason: String, CaseIterable, Sendable, Codable, Hashable {
    /// An incoming call took the screen.
    case incomingCall
    /// Siri or another system assistant took the screen.
    case siri
    /// A system alert, permission prompt or Control Center.
    case systemAlert
    /// The app moved to the background.
    case background
    /// The system warned about memory pressure.
    case memoryPressure
}

/// The stored evidence of one interruption. Path-free by construction.
public struct InterruptionRecord: Sendable, Equatable {
    public let reason: InterruptionReason
    public let jobID: UUID
    public let error: ErrorState

    public init(reason: InterruptionReason, jobID: UUID, error: ErrorState) {
        self.reason = reason
        self.jobID = jobID
        self.error = error
    }
}

// MARK: - Coordinator

/// Tracks one in-flight user action across a system interruption.
///
/// A page begins a job, calls ``interrupt(_:)`` from the scene-phase / call
/// notification, and calls ``resume()`` when the user returns. The coordinator
/// is deliberately synchronous and idempotent:
///
/// - interrupting twice keeps the first reason and shows one card;
/// - resuming twice returns `true` once and `false` afterwards, so the page can
///   never enqueue the same render or export twice;
/// - an interruption outside a job returns `nil` and changes nothing.
///
/// It does not own the page's task. The page must cancel its task on
/// interruption and restart it only after `resume()` returns `true`.
@MainActor
public final class InterruptionCoordinator {
    public enum Phase: Sendable, Equatable {
        case idle
        case running(UUID)
        case interrupted(UUID, InterruptionReason)
        case completed(UUID)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var lastInterruption: InterruptionRecord?
    public private(set) var interruptionCount = 0
    public private(set) var resumeCount = 0

    private let context: ErrorContext

    public init(context: ErrorContext = .editor) {
        self.context = context
    }

    // MARK: Queries

    public var isInterrupted: Bool {
        if case .interrupted = phase { return true }
        return false
    }

    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// The job token while running or interrupted.
    public var activeJobID: UUID? {
        switch phase {
        case .idle, .completed(_):
            return nil
        case let .running(jobID), let .interrupted(jobID, _):
            return jobID
        }
    }

    // MARK: Lifecycle

    /// Starts a new job. Any previous running/interrupted job is discarded.
    @discardableResult
    public func beginJob() -> UUID {
        let jobID = UUID()
        phase = .running(jobID)
        lastInterruption = nil
        return jobID
    }

    /// Records an interruption for the running job.
    ///
    /// Returns the state to present, or `nil` when there is nothing to resume
    /// (idle, already interrupted, or completed).
    public func interrupt(_ reason: InterruptionReason) -> ErrorState? {
        guard case let .running(jobID) = phase else { return nil }

        let state = ErrorState(
            kind: .interrupted,
            context: context,
            sourceCode: "INTERRUPTION_\(reason.rawValue.uppercased())"
        )
        phase = .interrupted(jobID, reason)
        lastInterruption = InterruptionRecord(
            reason: reason,
            jobID: jobID,
            error: state
        )
        interruptionCount += 1
        return state
    }

    /// Marks the interrupted job as running again.
    ///
    /// Returns `true` exactly once per interruption; the caller may then restart
    /// its task. Repeated calls are no-ops, which keeps a double tap or a
    /// duplicate lifecycle callback from starting two jobs.
    public func resume() -> Bool {
        guard case let .interrupted(jobID, _) = phase else { return false }
        phase = .running(jobID)
        resumeCount += 1
        return true
    }

    /// Marks the active job as finished; safe to call from any phase.
    public func complete() {
        switch phase {
        case let .running(jobID), let .interrupted(jobID, _):
            phase = .completed(jobID)
        case .idle, .completed(_):
            break
        }
    }

    /// Returns to idle without reporting success or failure.
    public func reset() {
        phase = .idle
        lastInterruption = nil
    }
}
