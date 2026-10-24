import CoreFoundation
import Foundation
import StyleToneCore

/// Result of decoding one stored profile document.
public struct StyleProfileDecodingResult: Sendable, Equatable {
    public let profile: StyleProfile
    public let sourceSchemaVersion: Int
    /// True when the document was written with an older schema and should be
    /// rewritten in the current schema after a successful read.
    public let migrated: Bool

    public init(
        profile: StyleProfile,
        sourceSchemaVersion: Int,
        migrated: Bool
    ) {
        self.profile = profile
        self.sourceSchemaVersion = sourceSchemaVersion
        self.migrated = migrated
    }
}

/// Reads, migrates and writes the `StyleProfile` JSON document.
///
/// Migration is intentionally tolerant about missing keys (the current Core
/// types already provide defaults) but strict about structural damage:
///
/// | Source | Result |
/// |---|---|
/// | missing `schemaVersion` | treated as schema 1 and migrated |
/// | schema 1 | `tone.temp` renamed to `tone.temperature`; metadata repaired |
/// | schema 2 | current metadata defaults filled; `temp` renamed |
/// | schema 3 | decoded as-is; only legacy dates/metadata are normalized |
/// | schema > 3 | ``StylePersistenceError/profileUnsupportedSchema(version:)`` |
/// | unreadable JSON | ``StylePersistenceError/profileCorrupt`` |
///
/// The original bytes are never mutated by this type. The store keeps a copy
/// before replacing a migrated file.
public enum StyleProfileJSONMigrator {
    /// Decodes and, when needed, migrates a profile document.
    ///
    /// - Parameters:
    ///   - data: Raw JSON bytes from disk.
    ///   - now: Injected clock used when a legacy document has no usable
    ///     `updatedAt` value.
    public static func decode(
        _ data: Data,
        now: Date
    ) throws -> StyleProfileDecodingResult {
        guard !data.isEmpty else {
            throw StylePersistenceError.profileCorrupt
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw StylePersistenceError.profileCorrupt
        }
        guard var root = object as? [String: Any] else {
            throw StylePersistenceError.profileCorrupt
        }

        let sourceVersion = try schemaVersion(in: root)
        let currentVersion = StyleProfile.currentSchemaVersion
        guard sourceVersion <= currentVersion else {
            throw StylePersistenceError.profileUnsupportedSchema(version: sourceVersion)
        }
        let migrated = sourceVersion < currentVersion

        do {
            try normalize(&root, sourceVersion: sourceVersion, now: now)
            let normalizedData = try JSONSerialization.data(withJSONObject: root, options: [])
            let profile = try StyleProfileCoding.makeDecoder().decode(
                StyleProfile.self,
                from: normalizedData
            )
            return StyleProfileDecodingResult(
                profile: StyleProfileSanitizer.sanitized(profile),
                sourceSchemaVersion: sourceVersion,
                migrated: migrated
            )
        } catch let error as StylePersistenceError {
            throw error
        } catch {
            throw structuralFailure(for: sourceVersion)
        }
    }

    /// Encodes a canonical current-schema document with stable keys and ISO8601
    /// dates, as required by the shared JSON contract.
    public static func encode(_ profile: StyleProfile) throws -> Data {
        try StyleProfileCoding.makeEncoder().encode(
            StyleProfileSanitizer.sanitized(profile)
        )
    }

    /// Structural schema version, defaulting to 1 for pre-versioned documents.
    static func schemaVersion(in root: [String: Any]) throws -> Int {
        guard let raw = root["schemaVersion"] else {
            return 1
        }
        guard let number = raw as? NSNumber, !isBoolean(number) else {
            throw StylePersistenceError.profileCorrupt
        }
        let version = number.intValue
        guard version > 0 else {
            throw StylePersistenceError.profileCorrupt
        }
        return version
    }

    private static func structuralFailure(for sourceVersion: Int) -> StylePersistenceError {
        sourceVersion < StyleProfile.currentSchemaVersion
            ? .profileMigrationFailed(sourceVersion: sourceVersion)
            : .profileCorrupt
    }

    private static func normalize(
        _ root: inout [String: Any],
        sourceVersion: Int,
        now: Date
    ) throws {
        let structuralError = structuralFailure(for: sourceVersion)

        // Legacy `tone.temp` key (schema 1/2). Values are clamped by Core types.
        if let rawTone = root["tone"] {
            guard var tone = rawTone as? [String: Any] else {
                throw structuralError
            }
            if tone["temperature"] == nil, let legacyTemperature = tone.removeValue(forKey: "temp") {
                tone["temperature"] = legacyTemperature
            } else {
                tone.removeValue(forKey: "temp")
            }
            root["tone"] = tone
        }

        for key in ["skin", "face", "body", "finish"] {
            if let value = root[key], !(value is [String: Any]) {
                throw structuralError
            }
        }

        root["schemaVersion"] = StyleProfile.currentSchemaVersion
        root["updatedAt"] = normalizedDateString(root["updatedAt"], now: now)
        normalizeTags(&root)
        normalizeConfidence(&root)
        normalizeAlgorithmVersion(&root)
        normalizePairCount(&root)
    }

    private static func normalizeTags(_ root: inout [String: Any]) {
        guard let raw = root["tags"] else {
            return
        }
        if let values = raw as? [Any] {
            root["tags"] = values.compactMap { $0 as? String }
        } else {
            root.removeValue(forKey: "tags")
        }
    }

    private static func normalizeConfidence(_ root: inout [String: Any]) {
        guard let raw = root["confidence"] else {
            return
        }
        if let value = raw as? String, ConfidenceLevel(rawValue: value) != nil {
            return
        }
        root.removeValue(forKey: "confidence")
    }

    private static func normalizeAlgorithmVersion(_ root: inout [String: Any]) {
        guard let raw = root["algorithmVersion"] else {
            return
        }
        guard let value = raw as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            root.removeValue(forKey: "algorithmVersion")
            return
        }
    }

    private static func normalizePairCount(_ root: inout [String: Any]) {
        guard let raw = root["pairCount"] else {
            return
        }
        guard let number = raw as? NSNumber, !isBoolean(number) else {
            root.removeValue(forKey: "pairCount")
            return
        }
        root["pairCount"] = max(0, number.intValue)
    }

    /// Accepts ISO8601 strings (with or without fractional seconds) and numeric
    /// epoch values. Unusable values fall back to `now` instead of failing the
    /// whole profile.
    private static func normalizedDateString(_ raw: Any?, now: Date) -> String {
        if let string = raw as? String, let date = parseISO8601(string) {
            return formatISO8601(date)
        }
        if let number = raw as? NSNumber, !isBoolean(number) {
            let value = number.doubleValue
            if value.isFinite, value > 0 {
                let seconds = value > 10_000_000_000 ? value / 1_000 : value
                let date = Date(timeIntervalSince1970: seconds)
                if date.timeIntervalSince1970 > 0 {
                    return formatISO8601(date)
                }
            }
        }
        return formatISO8601(now)
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID()
    }
}
