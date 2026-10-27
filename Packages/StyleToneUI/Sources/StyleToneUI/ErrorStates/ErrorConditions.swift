import Foundation

// MARK: - Thermal

/// Coarse thermal pressure, mirroring the meaningful system thresholds without
/// importing a platform enum into the models.
public enum ThermalPressure: Int, CaseIterable, Sendable, Codable, Hashable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    public var isElevated: Bool {
        self == .serious || self == .critical
    }
}

// MARK: - Conditions

/// A snapshot of the non-fatal device conditions the UI reacts to.
///
/// The values are injected by the host rather than read from platform APIs, so
/// every advisory path is deterministic in tests and the error unit stays free
/// of platform imports.
public struct DeviceConditions: Sendable, Equatable {
    public var isOffline: Bool
    public var isLowPowerModeEnabled: Bool
    /// `0...1`, or `nil` when unknown. Out-of-range values are clamped and
    /// non-finite values become `nil`.
    public var batteryLevel: Double?
    public var isCharging: Bool
    public var thermalState: ThermalPressure
    /// Free space in bytes, or `nil` when unknown.
    public var availableDiskBytes: Int64?

    public init(
        isOffline: Bool = false,
        isLowPowerModeEnabled: Bool = false,
        batteryLevel: Double? = nil,
        isCharging: Bool = false,
        thermalState: ThermalPressure = .nominal,
        availableDiskBytes: Int64? = nil
    ) {
        self.isOffline = isOffline
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        if let batteryLevel, batteryLevel.isFinite {
            self.batteryLevel = min(max(batteryLevel, 0), 1)
        } else {
            self.batteryLevel = nil
        }
        self.isCharging = isCharging
        self.thermalState = thermalState
        self.availableDiskBytes = availableDiskBytes
    }

    /// Healthy defaults: online, plenty of power and space, nominal thermal.
    public static let healthy = DeviceConditions(
        batteryLevel: 1,
        availableDiskBytes: 32_000_000_000
    )
}

// MARK: - Capability

/// A product capability whose availability can depend on the network.
public enum AppFeature: String, CaseIterable, Sendable, Codable, Hashable {
    case onboarding
    case pairing
    case calibration
    case styleLearning
    case styleProfiles
    case editing
    case previewRendering
    case fullRendering
    case exportRendering
    case savingToPhotos
    case sharing
    case diagnostics
    case purchase
    case restorePurchase
    case productLoading
}

public enum FeatureAvailability: String, Sendable, Codable, Hashable {
    case available
    case requiresConnection
}

/// The offline contract for the whole app.
///
/// Everything the user needs to create a photo is local. Only the store calls
/// (product loading, purchase and restore) require a connection; the purchase
/// surface must offer "Continue editing" when they fail.
public enum OfflineCapability {
    public static let networkFeatures: Set<AppFeature> = [
        .purchase,
        .restorePurchase,
        .productLoading,
    ]

    public static let coreFeatures: [AppFeature] =
        AppFeature.allCases.filter { !networkFeatures.contains($0) }

    public static func availability(
        of feature: AppFeature,
        isOffline: Bool
    ) -> FeatureAvailability {
        if isOffline, networkFeatures.contains(feature) {
            return .requiresConnection
        }
        return .available
    }

    /// Whether every core capability, including export and saving to Photos,
    /// works with the radio off.
    public static var coreIsOfflineReady: Bool {
        coreFeatures.allSatisfy {
            availability(of: $0, isOffline: true) == .available
        }
    }
}

// MARK: - Storage

public enum StorageAssessment: String, Sendable, Codable, Hashable {
    case sufficient
    case low
    case unknown
}

public enum StorageHeadroom {
    /// Compares free space with the space an operation needs.
    ///
    /// Unknown free space is not treated as low: the operation should proceed
    /// and let the real write report `ENOSPC` rather than blocking on guesswork.
    public static func assess(
        availableBytes: Int64?,
        requiredBytes: Int64
    ) -> StorageAssessment {
        guard let availableBytes else { return .unknown }
        let required = max(0, requiredBytes)
        return availableBytes < required ? .low : .sufficient
    }
}

// MARK: - Advisor

/// Turns device conditions into non-blocking advisories.
///
/// Offline is intentionally absent: losing the network does not stop editing,
/// so there is no passive "offline error". A network action that fails produces
/// `.offline` through ``ErrorMapper`` instead.
public struct ErrorAdvisor: Sendable, Equatable {
    /// Battery percentage at or below which a notice is shown.
    public let lowBatteryThreshold: Double
    /// Free-space floor for the export preflight notice.
    public let lowStorageThresholdBytes: Int64

    public init(
        lowBatteryThreshold: Double = 0.2,
        lowStorageThresholdBytes: Int64 = 300_000_000
    ) {
        self.lowBatteryThreshold = min(max(lowBatteryThreshold, 0), 1)
        self.lowStorageThresholdBytes = max(0, lowStorageThresholdBytes)
    }

    public static let standard = ErrorAdvisor()

    /// Stable order: battery, thermal, storage.
    public func advisories(
        for conditions: DeviceConditions,
        context: ErrorContext = .general
    ) -> [ErrorState] {
        var states: [ErrorState] = []

        let batteryLow = conditions.batteryLevel.map {
            $0 <= lowBatteryThreshold
        } ?? false
        if conditions.isLowPowerModeEnabled || batteryLow {
            states.append(
                ErrorState(
                    kind: .lowBattery,
                    context: context,
                    sourceCode: conditions.isLowPowerModeEnabled
                        ? "LOW_POWER_MODE"
                        : "BATTERY_LOW"
                )
            )
        }

        if conditions.thermalState.isElevated {
            states.append(
                ErrorState(
                    kind: .thermalPressure,
                    context: context,
                    sourceCode: "THERMAL_\(conditions.thermalState.name.uppercased())"
                )
            )
        }

        let storage = StorageHeadroom.assess(
            availableBytes: conditions.availableDiskBytes,
            requiredBytes: lowStorageThresholdBytes
        )
        if storage == .low {
            states.append(
                ErrorState(
                    kind: .storageLow,
                    context: context,
                    sourceCode: "STORAGE_BELOW_RESERVE"
                )
            )
        }

        return states
    }
}

private extension ThermalPressure {
    var name: String {
        switch self {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        }
    }
}
