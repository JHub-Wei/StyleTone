import Foundation

#if canImport(os)
import os
#endif

/// Stable Instruments signpost events emitted by the integration suite.
///
/// Names are compile-time literals because `OSSignposter` requires
/// `StaticString`. Scenario identifiers are listed in `PerformanceScenario`
/// and mapped to these events by the test support.
public enum PerformanceSignpostEvent: String, Sendable, CaseIterable {
    case firstFrame
    case previewFrame
    case sliderResponse
    case analysis
    case learning
    case export
    case memory
    case cancellation
    case proxyScale

    /// Static signpost name shown in Instruments.
    public var staticName: StaticString {
        switch self {
        case .firstFrame: return "first-frame"
        case .previewFrame: return "preview-frame"
        case .sliderResponse: return "slider-response"
        case .analysis: return "analysis"
        case .learning: return "learning"
        case .export: return "export"
        case .memory: return "memory"
        case .cancellation: return "cancellation"
        case .proxyScale: return "proxy-scale"
        }
    }

    /// Recommended Instruments subsystem.
    public static let subsystem = "com.styletone.performance"
    /// Recommended Instruments category.
    public static let category = "performance"
}

/// Thin wrapper around `OSSignposter` that compiles on every platform.
///
/// On Darwin the interval shows up in the Instruments "Points of Interest"
/// track and can be recorded with `xctrace record --template 'Time Profiler'`
/// plus the `os-signpost` instrument. On other platforms it is a no-op.
public struct PerformanceSignposter: Sendable {
    public let subsystem: String
    public let category: String

    public init(
        subsystem: String = PerformanceSignpostEvent.subsystem,
        category: String = PerformanceSignpostEvent.category
    ) {
        self.subsystem = subsystem
        self.category = category
    }

    /// Wraps a synchronous operation in one signpost interval.
    public func withInterval<T>(
        _ event: PerformanceSignpostEvent,
        _ body: () throws -> T
    ) rethrows -> T {
        #if canImport(os)
        let signposter = OSSignposter(subsystem: subsystem, category: category)
        let state = signposter.beginInterval(event.staticName)
        defer { signposter.endInterval(event.staticName, state) }
        return try body()
        #else
        return try body()
        #endif
    }

    /// Emits a one-off event, e.g. a memory checkpoint.
    public func event(_ event: PerformanceSignpostEvent) {
        #if canImport(os)
        let signposter = OSSignposter(subsystem: subsystem, category: category)
        signposter.emitEvent(event.staticName)
        #endif
    }
}
