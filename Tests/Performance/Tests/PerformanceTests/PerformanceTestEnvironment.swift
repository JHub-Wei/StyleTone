import Foundation
import PerformanceKit

#if canImport(Darwin)
import Darwin
#endif

/// Captures the host environment for a performance run.
///
/// The identifier is deliberately coarse enough to be stable across CI
/// machines of the same class, and specific enough that a device baseline is
/// never compared with a simulator or a macOS runner.
enum PerformanceTestEnvironment {
    static var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] == "true"
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static var physicalMemoryMegabytes: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_000_000)
    }

    static var buildConfiguration: PerformanceEnvironment.BuildConfiguration {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    static var hardwareIdentifier: String {
        #if canImport(Darwin)
        var info = utsname()
        guard uname(&info) == 0 else { return "unknown" }
        return withUnsafeBytes(of: &info.machine) { raw in
            guard let base = raw.baseAddress else { return "unknown" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        #else
        return "unknown"
        #endif
    }

    /// Device model used in the environment.
    ///
    /// The simulator exposes the simulated hardware through
    /// `SIMULATOR_MODEL_IDENTIFIER`; a physical device uses `uname`.
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulated.isEmpty {
            return simulated
        }
        return hardwareIdentifier
    }

    static var deviceClass: DevicePerformanceClass {
        if isSimulator {
            return .unknown
        }
        if isReferenceModel(deviceModel) {
            return .reference
        }
        if isLowEndModel(deviceModel) || physicalMemoryMegabytes < 3_500 {
            return .lowEnd
        }
        return .unknown
    }

    static var isReferenceDevice: Bool {
        deviceClass == .reference && !isSimulator
    }

    static var isLowEndDevice: Bool {
        deviceClass == .lowEnd && !isSimulator
    }

    /// Builds the environment descriptor for the current process.
    static func detect() -> PerformanceEnvironment {
        let kind: PerformanceEnvironment.Kind
        let id: String
        let displayModel: String

        if isSimulator {
            kind = .simulator
            displayModel = "\(deviceModel) Simulator"
            id = "simulator.\(deviceModel).\(architecture)"
        } else if isReferenceModel(deviceModel) {
            kind = .referenceDevice
            displayModel = referenceName(for: deviceModel)
            id = "device.iphone13"
        } else if isLowEndModel(deviceModel) {
            kind = .lowEndDevice
            displayModel = deviceModel
            id = "device.\(deviceModel)"
        } else if isCI {
            kind = .ci
            displayModel = "\(hardwareIdentifier) macOS runner"
            id = "ci.macos.\(architecture)"
        } else if hardwareIdentifier == "arm64" || hardwareIdentifier == "x86_64" {
            kind = .unknown
            displayModel = "\(hardwareIdentifier) macOS host"
            id = "local.macos.\(architecture)"
        } else {
            kind = .unknown
            displayModel = deviceModel
            id = "unknown.\(deviceModel).\(architecture)"
        }

        let version = ProcessInfo.processInfo.operatingSystemVersion
        return PerformanceEnvironment(
            id: id,
            kind: kind,
            deviceModel: displayModel,
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            architecture: architecture,
            buildConfiguration: buildConfiguration,
            physicalMemoryMegabytes: physicalMemoryMegabytes,
            notes: "CI=\(isCI)"
        )
    }

    // MARK: - Model tables

    private static func isReferenceModel(_ model: String) -> Bool {
        // iPhone 13 family (iPhone14,x).
        ["iPhone14,5", "iPhone14,2", "iPhone14,3", "iPhone14,4"]
            .contains(model)
    }

    private static func isLowEndModel(_ model: String) -> Bool {
        // 4 GB or older devices in the low-end matrix; SE models are the floor.
        [
            "iPhone12,8",  // SE (2nd generation)
            "iPhone14,6",  // SE (3rd generation)
            "iPhone13,1",  // 12 mini
            "iPhone12,1",  // 11
            "iPhone12,3",  // 11 Pro
            "iPhone12,5",  // 11 Pro Max
            "iPhone11,2",  // XS
            "iPhone11,4",  // XS Max
            "iPhone11,6",  // XS Max (China)
            "iPhone11,8"   // XR
        ].contains(model)
    }

    private static func referenceName(for model: String) -> String {
        switch model {
        case "iPhone14,5": return "iPhone 13"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,4": return "iPhone 13 mini"
        default: return model
        }
    }
}

/// Environment-variable switches used by the suite.
enum PerformanceTestProfile {
    static var heavy: Bool {
        PerformanceTestEnvironment.isReferenceDevice
            || ProcessInfo.processInfo.environment["ST_PERF_HEAVY"] == "1"
    }

    /// Contract §10 budgets are enforced on the reference/low-end device.
    /// Shared debug CI runners record them but rely on baseline regression.
    static var enforcesContractBudget: Bool {
        PerformanceTestEnvironment.isReferenceDevice
            || PerformanceTestEnvironment.isLowEndDevice
            || ProcessInfo.processInfo.environment["ST_PERF_STRICT"] == "1"
    }

    static var requiresBaseline: Bool {
        ProcessInfo.processInfo.environment["ST_PERF_REQUIRE_BASELINE"] == "1"
    }
}
