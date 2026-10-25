import Foundation

/// Version and platform information shown in Settings and embedded in the
/// diagnostic code.
///
/// The value deliberately excludes device names, advertising identifiers and
/// other device-specific data: version, build, platform and OS major are enough
/// for support without becoming a fingerprint.
public struct SettingsVersionInfo: Sendable, Equatable, Hashable {
    public let marketingVersion: String
    public let buildNumber: String
    public let platform: String
    public let osVersion: String

    public init(
        marketingVersion: String,
        buildNumber: String,
        platform: String,
        osVersion: String
    ) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
        self.platform = platform
        self.osVersion = osVersion
    }

    /// Fallback used by previews and by a host without a configured bundle.
    public static let fallback = SettingsVersionInfo(
        marketingVersion: "0.0.0",
        buildNumber: "0",
        platform: "unknown",
        osVersion: "0.0"
    )

    /// A development version used by the placeholder dependency container.
    public static let preview = SettingsVersionInfo(
        marketingVersion: "0.1.0",
        buildNumber: "1",
        platform: currentPlatform,
        osVersion: currentOSMajor
    )

    /// "0.1.0 (1)".
    public var displayVersion: String {
        "\(marketingVersion) (\(buildNumber))"
    }

    /// "iOS 17.4".
    public var systemDescription: String {
        "\(platform) \(osVersion)"
    }

    /// Compact, ASCII-only platform token for the diagnostic code.
    public var platformToken: String {
        let major = osVersion.split(separator: ".").first.map(String.init) ?? "0"
        return Self.sanitizedToken("\(platform)\(major)", maxLength: 20)
    }

    /// Keeps a token within a safe ASCII alphabet.
    ///
    /// Diagnostic codes are pasted into support messages, so every segment must
    /// be stable, bounded and free of separators or user-provided text.
    public static func sanitizedToken(_ rawValue: String, maxLength: Int = 20) -> String {
        var output = ""
        for scalar in rawValue.unicodeScalars {
            let value = scalar.value
            let isAllowed = (48...57).contains(value)
                || (65...90).contains(value)
                || (97...122).contains(value)
                || value == 46 // "."
                || value == 45 // "-"
            if isAllowed, let character = Unicode.Scalar(value) {
                output.append(Character(character))
            } else {
                output.append("-")
            }
        }
        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        guard !trimmed.isEmpty else { return "0" }
        return String(trimmed.prefix(maxLength))
    }

    /// Compile-time platform label. Only the OS family is exposed.
    public static var currentPlatform: String {
        #if os(iOS)
        return "iOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(visionOS)
        return "visionOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "unknown"
        #endif
    }

    /// Major and minor OS version, e.g. "17.4".
    public static var currentOSMajor: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }
}

/// Supplies version information to the settings screen.
public protocol SettingsVersionProviding: Sendable {
    func currentVersion() -> SettingsVersionInfo
}

/// Reads `CFBundleShortVersionString` and `CFBundleVersion` once.
///
/// The provider captures the two strings in `init` so the value can cross actor
/// boundaries without carrying a `Bundle`.
public struct BundleSettingsVersionProvider: SettingsVersionProviding {
    private let marketingVersion: String
    private let buildNumber: String
    private let platform: String
    private let osVersion: String

    public init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary
        marketingVersion = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        buildNumber = info?["CFBundleVersion"] as? String ?? "0"
        platform = SettingsVersionInfo.currentPlatform
        osVersion = SettingsVersionInfo.currentOSMajor
    }

    public func currentVersion() -> SettingsVersionInfo {
        SettingsVersionInfo(
            marketingVersion: marketingVersion,
            buildNumber: buildNumber,
            platform: platform,
            osVersion: osVersion
        )
    }
}

/// A provider with a fixed answer, for previews, tests and the placeholder
/// dependency container.
public struct StaticSettingsVersionProvider: SettingsVersionProviding {
    public let version: SettingsVersionInfo

    public init(_ version: SettingsVersionInfo = .preview) {
        self.version = version
    }

    public func currentVersion() -> SettingsVersionInfo {
        version
    }
}
