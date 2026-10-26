import Foundation

/// Preview quality tiers used when the device cannot keep up.
///
/// Only the preview proxy changes; the full-resolution render and export never
/// degrade.
public enum EditorPerformanceLevel: String, CaseIterable, Sendable, Equatable {
    case full
    case reduced
    case minimal

    public var previewLongEdge: Int {
        switch self {
        case .full:
            return 1280
        case .reduced:
            return 960
        case .minimal:
            return 640
        }
    }

    public var isDegraded: Bool {
        self != .full
    }

    fileprivate var degraded: EditorPerformanceLevel {
        switch self {
        case .full:
            return .reduced
        case .reduced, .minimal:
            return .minimal
        }
    }

    fileprivate var recovered: EditorPerformanceLevel {
        switch self {
        case .full, .reduced:
            return .full
        case .minimal:
            return .reduced
        }
    }
}

/// Adaptive preview policy.
///
/// The governor consumes completed preview durations (not wall-clock timers, so
/// tests never sleep). Two slow previews step the proxy down one tier; three
/// fast previews step it back up. The high-quality render is the source of
/// truth and never changes tier.
public struct EditorPerformanceGovernor: Sendable, Equatable {
    /// A preview slower than this is considered too slow for interactive use.
    public static let slowPreviewThreshold: TimeInterval = 0.28
    /// A preview faster than this counts toward recovery.
    public static let fastPreviewThreshold: TimeInterval = 0.10
    public static let slowSamplesBeforeDegrading = 2
    public static let fastSamplesBeforeRecovering = 3

    public private(set) var level: EditorPerformanceLevel
    public private(set) var previewSampleCount: Int
    private var slowStreak: Int
    private var fastStreak: Int

    public init(level: EditorPerformanceLevel = .full) {
        self.level = level
        self.previewSampleCount = 0
        self.slowStreak = 0
        self.fastStreak = 0
    }

    public var previewLongEdge: Int {
        level.previewLongEdge
    }

    public var isDegraded: Bool {
        level.isDegraded
    }

    /// Records one completed preview. Full renders are ignored on purpose.
    public mutating func record(duration: TimeInterval, quality: EditorRenderQuality) {
        guard quality == .preview, duration.isFinite, duration >= 0 else { return }
        previewSampleCount += 1

        if duration >= Self.slowPreviewThreshold {
            slowStreak += 1
            fastStreak = 0
            if slowStreak >= Self.slowSamplesBeforeDegrading {
                slowStreak = 0
                level = level.degraded
            }
            return
        }

        if duration <= Self.fastPreviewThreshold {
            fastStreak += 1
            slowStreak = 0
            if fastStreak >= Self.fastSamplesBeforeRecovering {
                fastStreak = 0
                level = level.recovered
            }
            return
        }

        slowStreak = 0
        fastStreak = 0
    }

    public mutating func reset() {
        level = .full
        previewSampleCount = 0
        slowStreak = 0
        fastStreak = 0
    }
}
