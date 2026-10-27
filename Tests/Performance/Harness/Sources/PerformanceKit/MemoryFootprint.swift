import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// A physical memory footprint sample.
///
/// Uses `phys_footprint` on Darwin, which is the value Jetsam accounting is
/// based on, not `resident_size`.
public struct MemoryFootprint: Codable, Sendable, Equatable {
    public let bytes: UInt64

    public init(bytes: UInt64) {
        self.bytes = bytes
    }

    /// Decimal megabytes, matching the contracts §10 budget unit.
    public var megabytes: Double {
        Double(bytes) / 1_000_000
    }

    public var summary: String {
        String(format: "%.1f MB", megabytes)
    }
}

/// Source of footprint samples. Tests inject a closure-backed reader.
public protocol MemoryFootprintReading: Sendable {
    func currentFootprint() throws -> MemoryFootprint
}

/// Closure-backed reader for tests and deterministic scenarios.
public struct ClosureMemoryFootprintReader: MemoryFootprintReading {
    private let read: @Sendable () throws -> MemoryFootprint

    public init(_ read: @escaping @Sendable () throws -> MemoryFootprint) {
        self.read = read
    }

    public func currentFootprint() throws -> MemoryFootprint {
        try read()
    }
}

#if canImport(Darwin)
/// Reads the process `phys_footprint` through `task_vm_info`.
///
/// Available on macOS and iOS (device and simulator). The API returns the
/// process-wide value; callers measure deltas around the scenario so XCTest and
/// app baseline memory cancel out.
public struct DarwinMemoryFootprintReader: MemoryFootprintReading {
    public init() {}

    public func currentFootprint() throws -> MemoryFootprint {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            throw PerformanceKitError.memoryUnavailable(
                "task_info(TASK_VM_INFO) failed with kern_return_t \(result)"
            )
        }
        return MemoryFootprint(bytes: UInt64(info.phys_footprint))
    }
}
#endif

/// Unsupported-platform reader. The integration suite skips memory scenarios
/// when this is the only reader available.
public struct UnsupportedMemoryFootprintReader: MemoryFootprintReading {
    public init() {}

    public func currentFootprint() throws -> MemoryFootprint {
        throw PerformanceKitError.memoryUnavailable(
            "phys_footprint is only available on Darwin"
        )
    }
}

/// Tracks the peak footprint around a scenario.
///
/// - `start()` records the baseline (process memory before the scenario).
/// - `sample()` records the current footprint; call it after each heavy stage.
/// - `peakDelta` is what the budgets use because the XCTest host baseline is
///   not comparable across machines.
public struct MemoryPeakTracker: Sendable {
    private let reader: any MemoryFootprintReading
    public private(set) var baseline: MemoryFootprint?
    public private(set) var peak: MemoryFootprint?

    public init(reader: any MemoryFootprintReading) {
        self.reader = reader
    }

    /// Captures the baseline and resets the peak.
    public mutating func start() throws {
        let value = try reader.currentFootprint()
        baseline = value
        peak = value
    }

    /// Records one sample and keeps the maximum.
    public mutating func sample() throws {
        let value = try reader.currentFootprint()
        if let peak, peak.bytes >= value.bytes {
            return
        }
        peak = value
    }

    /// Peak minus baseline in decimal megabytes.
    public var peakDeltaMegabytes: Double {
        guard let baseline, let peak, peak.bytes >= baseline.bytes else { return 0 }
        return Double(peak.bytes - baseline.bytes) / 1_000_000
    }

    /// Absolute peak in decimal megabytes.
    public var peakMegabytes: Double {
        guard let peak else { return 0 }
        return peak.megabytes
    }

    /// Convenience measurement for the gate. The scenario decides whether it
    /// compares the delta or the absolute value.
    public func measurement(scenarioID: String, absolute: Bool = false) throws -> PerformanceMeasurement {
        let value = absolute ? peakMegabytes : peakDeltaMegabytes
        return try PerformanceMeasurement(
            scenarioID: scenarioID,
            unit: .megabytes,
            values: [value]
        )
    }
}
