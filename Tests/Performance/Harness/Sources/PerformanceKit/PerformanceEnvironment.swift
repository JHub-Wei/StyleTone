import Foundation

/// Where a performance run happened.
///
/// A baseline is only valid for the environment that produced it. The gate
/// refuses to compare an iPhone 13 baseline with a debug macOS CI run, and a
/// `debug` baseline with a `release` build.
public struct PerformanceEnvironment: Codable, Sendable, Hashable, Identifiable {
    /// Broad category of the run.
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        /// The product reference device (iPhone 13 class).
        case referenceDevice
        /// A device in the low-end degradation matrix.
        case lowEndDevice
        /// macOS CI runner used for threshold checks.
        case ci
        /// iOS Simulator; never a release sign-off environment.
        case simulator
        /// Unknown host.
        case unknown
    }

    /// Swift build configuration of the code under test.
    public enum BuildConfiguration: String, Codable, Sendable, Hashable, CaseIterable {
        case debug
        case release
    }

    /// Stable identifier, for example `device.iphone13`, `ci.macos.arm64`.
    public let id: String
    public let kind: Kind
    /// Hardware identifier or runner name, no user data.
    public let deviceModel: String
    public let osVersion: String
    public let architecture: String
    public let buildConfiguration: BuildConfiguration
    /// Physical memory in decimal megabytes; `0` when unknown.
    public let physicalMemoryMegabytes: Int
    /// Optional free-form note (for example the CI run URL).
    public let notes: String

    public init(
        id: String,
        kind: Kind,
        deviceModel: String,
        osVersion: String,
        architecture: String,
        buildConfiguration: BuildConfiguration,
        physicalMemoryMegabytes: Int,
        notes: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.architecture = architecture
        self.buildConfiguration = buildConfiguration
        self.physicalMemoryMegabytes = max(0, physicalMemoryMegabytes)
        self.notes = notes
    }

    /// `true` when a baseline from the same environment may be compared.
    public func isComparable(with other: PerformanceEnvironment) -> Bool {
        id == other.id && buildConfiguration == other.buildConfiguration
    }

    /// One-line description used in reports.
    public var summary: String {
        "\(id) (\(deviceModel), \(osVersion), \(architecture), \(buildConfiguration.rawValue))"
    }
}

/// One scenario measurement paired with the environment and source that
/// produced it.
public struct PerformanceObservation: Codable, Sendable, Equatable {
    public let measurement: PerformanceMeasurement
    public let environment: PerformanceEnvironment
    /// ISO-8601 timestamp.
    public let capturedAt: String
    /// Test name, CI job or device run label.
    public let source: String
    public let notes: String?

    public init(
        measurement: PerformanceMeasurement,
        environment: PerformanceEnvironment,
        capturedAt: String,
        source: String,
        notes: String? = nil
    ) {
        self.measurement = measurement
        self.environment = environment
        self.capturedAt = capturedAt
        self.source = source
        self.notes = notes
    }
}
