import Foundation

public enum ConfidenceLevel: String, Codable, Sendable, CaseIterable {
    case trial
    case standard
    case stable
}

/// The persisted personal style profile.
///
/// `tags` are localization keys, not display strings. `schemaVersion` is
/// independent from `algorithmVersion`; WP-08 owns migration.
public struct StyleProfile: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 3
    public static let currentAlgorithmVersion = "st-3.0.0"

    public var schemaVersion: Int
    public var algorithmVersion: String
    public var pairCount: Int
    public var confidence: ConfidenceLevel
    public var tone: ToneParameters
    public var skin: SkinParameters
    public var face: FaceParameters
    public var body: BodyParameters
    public var finish: FinishParameters
    public var tags: [String]
    public var updatedAt: Date

    public init(
        schemaVersion: Int = StyleProfile.currentSchemaVersion,
        algorithmVersion: String = StyleProfile.currentAlgorithmVersion,
        pairCount: Int = 0,
        confidence: ConfidenceLevel = .trial,
        tone: ToneParameters = .neutral,
        skin: SkinParameters = .neutral,
        face: FaceParameters = .neutral,
        body: BodyParameters = .neutral,
        finish: FinishParameters = .neutral,
        tags: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.algorithmVersion = algorithmVersion
        self.pairCount = max(0, pairCount)
        self.confidence = confidence
        self.tone = tone
        self.skin = skin
        self.face = face
        self.body = body
        self.finish = finish
        self.tags = tags
        self.updatedAt = updatedAt
    }

    public static func neutral(updatedAt: Date = Date()) -> StyleProfile {
        StyleProfile(updatedAt: updatedAt)
    }

    public var isNeutral: Bool {
        tone == .neutral
            && skin == .neutral
            && face == .neutral
            && body == .neutral
            && finish == .neutral
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion

        guard schemaVersion <= Self.currentSchemaVersion, schemaVersion > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported StyleProfile schema version: \(schemaVersion)"
            )
        }

        self.init(
            schemaVersion: schemaVersion,
            algorithmVersion: try container.decodeIfPresent(String.self, forKey: .algorithmVersion)
                ?? Self.currentAlgorithmVersion,
            pairCount: try container.decodeIfPresent(Int.self, forKey: .pairCount) ?? 0,
            confidence: try container.decodeIfPresent(ConfidenceLevel.self, forKey: .confidence) ?? .trial,
            tone: try container.decodeIfPresent(ToneParameters.self, forKey: .tone) ?? .neutral,
            skin: try container.decodeIfPresent(SkinParameters.self, forKey: .skin) ?? .neutral,
            face: try container.decodeIfPresent(FaceParameters.self, forKey: .face) ?? .neutral,
            body: try container.decodeIfPresent(BodyParameters.self, forKey: .body) ?? .neutral,
            finish: try container.decodeIfPresent(FinishParameters.self, forKey: .finish) ?? .neutral,
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(algorithmVersion, forKey: .algorithmVersion)
        try container.encode(pairCount, forKey: .pairCount)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(tone, forKey: .tone)
        try container.encode(skin, forKey: .skin)
        try container.encode(face, forKey: .face)
        try container.encode(body, forKey: .body)
        try container.encode(finish, forKey: .finish)
        try container.encode(tags, forKey: .tags)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case algorithmVersion
        case pairCount
        case confidence
        case tone
        case skin
        case face
        case body
        case finish
        case tags
        case updatedAt
    }
}

/// Stable JSON configuration for profiles.
public enum StyleProfileCoding {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
