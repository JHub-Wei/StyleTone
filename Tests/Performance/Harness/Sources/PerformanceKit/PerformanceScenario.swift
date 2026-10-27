import Foundation

// MARK: - Units and direction

/// Unit of one performance measurement.
public enum PerformanceUnit: String, Codable, Sendable, CaseIterable {
    /// Wall-clock seconds (lower is better).
    case seconds
    /// Frames per second (higher is better).
    case framesPerSecond
    /// Decimal megabytes (`bytes / 1_000_000`, lower is better).
    case megabytes
    /// Opaque count, e.g. cache misses (lower is better).
    case count

    /// Short symbol used in reports.
    public var symbol: String {
        switch self {
        case .seconds: return "s"
        case .framesPerSecond: return "fps"
        case .megabytes: return "MB"
        case .count: return "count"
        }
    }

    /// `true` when the unit describes memory.
    public var isMemory: Bool {
        self == .megabytes
    }
}

/// Direction in which a metric improves.
public enum PerformanceDirection: String, Codable, Sendable {
    case lowerIsBetter
    case higherIsBetter
}

// MARK: - Scenario

/// One measurable performance scenario with its contract budget.
///
/// A scenario carries the *contract* budget from `contracts.md` §10 and the
/// sample quality expected before a regression verdict is trusted. The
/// comparison against a recorded baseline lives in ``PerformanceGate`` so the
/// budget rule and the regression rule stay independently testable.
public struct PerformanceScenario: Codable, Sendable, Hashable, Identifiable {
    /// Stable machine identifier used in baselines, reports and signposts.
    public let id: String
    /// Human readable name for reports.
    public let displayName: String
    public let unit: PerformanceUnit
    public let direction: PerformanceDirection
    /// Contract budget in `unit`; `nil` for internal guard rails.
    public let contractTarget: Double?
    /// Minimum recorded samples before the p95 is considered trustworthy.
    public let minimumSamples: Int
    /// Absolute difference ignored before the relative 10 % rule is applied.
    ///
    /// This is a noise floor, not a relaxation of the 10 % rule: once the
    /// measured metric moves more than this absolute amount *and* more than
    /// 10 % from the baseline, the gate blocks. The floor only stops a 0.3 ms
    /// difference on a 25 ms frame from failing a shared CI runner.
    public let noiseFloor: Double
    /// How the metric is captured. Kept next to the scenario so a report is
    /// self-describing without a separate spreadsheet.
    public let method: String

    public init(
        id: String,
        displayName: String,
        unit: PerformanceUnit,
        direction: PerformanceDirection,
        contractTarget: Double? = nil,
        minimumSamples: Int = 5,
        noiseFloor: Double = 0,
        method: String
    ) {
        self.id = id
        self.displayName = displayName
        self.unit = unit
        self.direction = direction
        self.contractTarget = contractTarget.map { max(0, $0) }
        self.minimumSamples = max(1, minimumSamples)
        self.noiseFloor = max(0, noiseFloor)
        self.method = method
    }

    /// `true` when the scenario is checked against a contract §10 budget.
    public var isContractual: Bool {
        contractTarget != nil
    }

    /// Formats a value with the scenario unit.
    public func formatted(_ value: Double) -> String {
        if unit == .seconds || unit == .framesPerSecond {
            return String(format: "%.4f %@", value, unit.symbol)
        }
        return String(format: "%.2f %@", value, unit.symbol)
    }
}

// MARK: - Catalog

extension PerformanceScenario {
    /// All scenarios owned by WP-24.
    ///
    /// The contract targets mirror `contracts.md` §10. The internal scenarios
    /// (`cancellation.*`, `preview.proxy.*`) have no contract budget; they act
    /// as guard rails for the optimizations this work package introduced.
    public static let catalog: [PerformanceScenario] = [
        PerformanceScenario(
            id: "launch.coldStart",
            displayName: "Cold start",
            unit: .seconds,
            direction: .lowerIsBetter,
            contractTarget: 2.0,
            minimumSamples: 5,
            noiseFloor: 0.05,
            method: "XCUIApplication launch metric on a signpost-instrumented device build; "
                + "Instruments App Launch template records the same interval."
        ),
        PerformanceScenario(
            id: "preview.firstFrame",
            displayName: "First frame",
            unit: .seconds,
            direction: .lowerIsBetter,
            contractTarget: 1.5,
            minimumSamples: 5,
            noiseFloor: 0.03,
            method: "12 MP HEIC/JPEG → 2048 px preview decode plus the 1280 px editor proxy; "
                + "the image is assigned to the canvas immediately after decode."
        ),
        PerformanceScenario(
            id: "preview.sliderResponse",
            displayName: "Slider response",
            unit: .seconds,
            direction: .lowerIsBetter,
            contractTarget: 0.1,
            minimumSamples: 10,
            noiseFloor: 0.005,
            method: "setAdjustment → preview proxy scale → geometry frame → main-actor delivery."
        ),
        PerformanceScenario(
            id: "preview.frameTime",
            displayName: "Warp preview frame",
            unit: .seconds,
            direction: .lowerIsBetter,
            contractTarget: 1.0 / 30.0,
            minimumSamples: 8,
            noiseFloor: 0.001,
            method: "1080p Metal mesh warp, 32×32 grid, offscreen texture without CPU readback."
        ),
        PerformanceScenario(
            id: "learning.fivePairs",
            displayName: "5-pair style learning",
            unit: .seconds,
            direction: .lowerIsBetter,
            contractTarget: 90,
            minimumSamples: 3,
            noiseFloor: 0.20,
            method: "StyleLearningEngine over five 160×160 synthetic portrait pairs."
        ),
        PerformanceScenario(
            id: "learning.eightPairs",
            displayName: "8-pair style learning",
            unit: .seconds,
            direction: .lowerIsBetter,
            contractTarget: 150,
            minimumSamples: 3,
            noiseFloor: 0.30,
            method: "StyleLearningEngine over eight 160×160 synthetic portrait pairs."
        ),
        PerformanceScenario(
            id: "export.twelveMegapixel",
            displayName: "12 MP export",
            unit: .seconds,
            direction: .lowerIsBetter,
            contractTarget: 6,
            minimumSamples: 3,
            noiseFloor: 0.15,
            method: "Full-resolution render plus platform HEIC/JPEG encode and temp-file write."
        ),
        PerformanceScenario(
            id: "preview.memoryPeak",
            displayName: "Preview memory",
            unit: .megabytes,
            direction: .lowerIsBetter,
            contractTarget: 300,
            minimumSamples: 1,
            noiseFloor: 5,
            method: "Peak phys_footprint minus process baseline while opening and previewing a 12 MP photo."
        ),
        PerformanceScenario(
            id: "export.memoryPeak",
            displayName: "Export memory",
            unit: .megabytes,
            direction: .lowerIsBetter,
            contractTarget: 500,
            minimumSamples: 1,
            noiseFloor: 5,
            method: "Peak phys_footprint minus process baseline during a 12 MP render and encode."
        ),
        PerformanceScenario(
            id: "cancellation.latency",
            displayName: "Cancellation latency",
            unit: .seconds,
            direction: .lowerIsBetter,
            minimumSamples: 5,
            noiseFloor: 0.005,
            method: "cancelAll → the render worker becomes idle; a cancelled result is never delivered."
        ),
        PerformanceScenario(
            id: "preview.proxyCacheHit",
            displayName: "Preview proxy cache hit",
            unit: .seconds,
            direction: .lowerIsBetter,
            minimumSamples: 5,
            noiseFloor: 0.001,
            method: "Repeat preparePreview for the same image and tier; the scaler must run once."
        ),
        PerformanceScenario(
            id: "preview.proxyScale",
            displayName: "Preview proxy scale",
            unit: .seconds,
            direction: .lowerIsBetter,
            minimumSamples: 5,
            noiseFloor: 0.005,
            method: "CoreGraphicsPreviewScaler from 2048 px to the 1280 px preview tier."
        )
    ]

    /// Looks up a scenario by its stable identifier.
    public static func scenario(id: String) -> PerformanceScenario? {
        catalog.first { $0.id == id }
    }
}
