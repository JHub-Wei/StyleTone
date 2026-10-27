import Foundation

/// Builds the code users paste into a support message.
///
/// The code contains only the app version, build, OS family and major version,
/// the diagnostics on/off state, the entry count and a checksum. It contains no
/// device identifier and no user data.
public enum SettingsDiagnosticCode {
    /// Prefix used by every code emitted by this build.
    public static let prefix = "ST21"

    /// Maximum accepted length, including the checksum.
    public static let maximumLength = 96

    /// Builds a code such as `ST21-0.1.0-1-iOS17-ON-3-4F2A9C1D`.
    public static func make(
        version: SettingsVersionInfo,
        isEnabled: Bool,
        entryCount: Int
    ) -> String {
        let versionToken = SettingsVersionInfo.sanitizedToken(version.marketingVersion, maxLength: 16)
        let buildToken = SettingsVersionInfo.sanitizedToken(version.buildNumber, maxLength: 12)
        let platformToken = version.platformToken
        let state = isEnabled ? "ON" : "OFF"
        let count = min(max(entryCount, 0), SettingsDiagnosticsLimits.maximumCodeEntryCount)
        let base = "\(prefix)-\(versionToken)-\(buildToken)-\(platformToken)-\(state)-\(count)"
        return "\(base)-\(checksum(base))"
    }

    /// FNV-1a over ASCII bytes, rendered as eight uppercase hex digits.
    ///
    /// A checksum is enough to notice a truncated or hand-edited code; it is not
    /// a security primitive and carries no identifying information.
    public static func checksum(_ value: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08X", hash)
    }

    /// Whether a string looks like a code produced by ``make``.
    public static func isWellFormed(_ code: String) -> Bool {
        guard code.hasPrefix("\(prefix)-"), code.count <= maximumLength else { return false }
        guard code.unicodeScalars.allSatisfy({ scalar in
            let value = scalar.value
            return (48...57).contains(value)
                || (65...90).contains(value)
                || (97...122).contains(value)
                || value == 46 // "."
                || value == 45 // "-"
        }) else {
            return false
        }

        let parts = code.split(separator: "-")
        guard parts.count >= 7 else { return false }
        guard parts.contains(where: { String($0) == "ON" || String($0) == "OFF" }) else {
            return false
        }
        guard let checksumPart = parts.last, checksumPart.count == 8 else { return false }
        return checksumPart.allSatisfy { character in
            guard let scalar = character.unicodeScalars.first,
                  character.unicodeScalars.count == 1
            else {
                return false
            }
            let value = scalar.value
            return (48...57).contains(value) || (65...70).contains(value)
        }
    }
}
