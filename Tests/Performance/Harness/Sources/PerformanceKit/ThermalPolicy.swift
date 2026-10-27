import Foundation

// MARK: - Inputs

/// Thermal pressure reported by `ProcessInfo.thermalState`.
public enum ThermalPressure: String, Codable, Sendable, CaseIterable, Comparable {
    case nominal
    case fair
    case serious
    case critical

    public static func < (lhs: ThermalPressure, rhs: ThermalPressure) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        }
    }
}

/// Battery saver state from `ProcessInfo.isLowPowerModeEnabled`.
public enum PowerReserve: String, Codable, Sendable {
    case normal
    case lowPower
}

/// Device class used by the degradation matrix.
///
/// The host decides the class from the hardware identifier and physical
/// memory; WP-24 never guesses from a benchmark result at runtime.
public enum DevicePerformanceClass: String, Codable, Sendable, CaseIterable {
    /// iPhone 13 class reference device.
    case reference
    /// iPhone SE / older 4 GB devices in the low-end matrix.
    case lowEnd
    /// Simulator or CI; performance policy is exercised but not applied to UI.
    case unknown
}

/// Preview proxy tier. Raw values and long edges match WP-17
/// `EditorPerformanceLevel` so the host can map them one-to-one.
public enum PreviewQualityTier: String, Codable, Sendable, CaseIterable, Comparable {
    case full
    case reduced
    case minimal

    public var previewLongEdge: Int {
        switch self {
        case .full: return 1280
        case .reduced: return 960
        case .minimal: return 640
        }
    }

    public static func < (lhs: PreviewQualityTier, rhs: PreviewQualityTier) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .full: return 0
        case .reduced: return 1
        case .minimal: return 2
        }
    }
}

/// Why the preview was degraded.
public enum DegradationReason: String, Codable, Sendable, Hashable, CaseIterable {
    case lowEndDevice
    case lowPowerMode
    case thermalFair
    case thermalSerious
    case thermalCritical
    case adaptiveGovernor
}

// MARK: - Output

/// Effective preview policy for the current thermal/power/device state.
///
/// Only the interactive proxy is degraded. Export keeps its requested
/// resolution and quality at all times; under critical thermal the UI warns and
/// defers the next full render until the device cools, but it never silently
/// writes a lower-quality file.
public struct PerformanceDegradation: Codable, Sendable, Equatable {
    /// Effective preview tier (maximum of device, thermal, power and governor).
    public let tier: PreviewQualityTier
    /// Effective preview long edge in pixels.
    public let previewLongEdge: Int
    /// All reasons that contributed to the tier, in stable order.
    public let reasons: [DegradationReason]
    /// Full-quality render is allowed for the current gesture.
    public let allowsHighQualityRender: Bool
    /// Export is always allowed so the user can save their work.
    public let allowsExport: Bool
    /// The UI should show a one-line notice.
    public let showsNotice: Bool
    /// Notice localization key owned by the UI work package; `nil` when none.
    public let noticeLocalizationKey: String?
    /// The export button should show a "device is hot" warning before starting.
    public let showsExportWarning: Bool

    public init(
        tier: PreviewQualityTier,
        reasons: [DegradationReason],
        allowsHighQualityRender: Bool,
        allowsExport: Bool,
        showsNotice: Bool,
        noticeLocalizationKey: String?,
        showsExportWarning: Bool
    ) {
        self.tier = tier
        self.previewLongEdge = tier.previewLongEdge
        self.reasons = reasons
        self.allowsHighQualityRender = allowsHighQualityRender
        self.allowsExport = allowsExport
        self.showsNotice = showsNotice
        self.noticeLocalizationKey = noticeLocalizationKey
        self.showsExportWarning = showsExportWarning
    }

    /// One-line summary for diagnostics.
    public var summary: String {
        "preview=\(tier.rawValue) longEdge=\(previewLongEdge) "
            + "reasons=\(reasons.map(\.rawValue).joined(separator: ",")) "
            + "highQuality=\(allowsHighQualityRender) export=\(allowsExport)"
    }
}

// MARK: - Policy

/// Maps thermal, power and device class into an effective preview policy.
///
/// The policy is deterministic and independent of UI so it can be tested on CI
/// and shared by the editor, the export screen and the settings diagnostics.
public struct ThermalPerformancePolicy: Sendable {
    public init() {}

    /// Resolves the effective degradation.
    ///
    /// - Parameters:
    ///   - thermal: Current `ProcessInfo.thermalState` mapped to
    ///     ``ThermalPressure``.
    ///   - power: Low-power mode state.
    ///   - deviceClass: Hardware class supplied by the host.
    ///   - governorTier: Tier chosen by WP-17's adaptive
    ///     `EditorPerformanceGovernor`.
    public func degradation(
        thermal: ThermalPressure,
        power: PowerReserve,
        deviceClass: DevicePerformanceClass,
        governorTier: PreviewQualityTier = .full
    ) -> PerformanceDegradation {
        var reasons: [DegradationReason] = []
        var tier = PreviewQualityTier.full

        if deviceClass == .lowEnd {
            reasons.append(.lowEndDevice)
            tier = max(tier, .reduced)
        }

        switch thermal {
        case .nominal:
            break
        case .fair:
            reasons.append(.thermalFair)
            tier = max(tier, .reduced)
        case .serious:
            reasons.append(.thermalSerious)
            tier = max(tier, .minimal)
        case .critical:
            reasons.append(.thermalCritical)
            tier = max(tier, .minimal)
        }

        if power == .lowPower {
            reasons.append(.lowPowerMode)
            tier = max(tier, .reduced)
        }

        if governorTier != .full {
            reasons.append(.adaptiveGovernor)
            tier = max(tier, governorTier)
        }

        let allowsHighQualityRender = thermal < .critical
        let showsNotice = !reasons.isEmpty
        let key = noticeLocalizationKey(
            thermal: thermal,
            power: power,
            deviceClass: deviceClass
        )

        return PerformanceDegradation(
            tier: tier,
            reasons: reasons,
            allowsHighQualityRender: allowsHighQualityRender,
            allowsExport: true,
            showsNotice: showsNotice,
            noticeLocalizationKey: showsNotice ? key : nil,
            showsExportWarning: thermal >= .serious
        )
    }

    /// Notice key for the most severe active state.
    ///
    /// The keys are proposals to the editor/UI owner; they are not added to
    /// `Localizable.xcstrings` by WP-24.
    public func noticeLocalizationKey(
        thermal: ThermalPressure,
        power: PowerReserve,
        deviceClass: DevicePerformanceClass
    ) -> String? {
        switch thermal {
        case .critical:
            return "editor.performance.thermalCritical"
        case .serious:
            return "editor.performance.thermalSerious"
        case .fair:
            if power == .lowPower {
                return "editor.performance.lowPower"
            }
            return "editor.performance.thermalFair"
        case .nominal:
            if power == .lowPower {
                return "editor.performance.lowPower"
            }
            if deviceClass == .lowEnd {
                return "editor.performance.lowEnd"
            }
            return nil
        }
    }
}
