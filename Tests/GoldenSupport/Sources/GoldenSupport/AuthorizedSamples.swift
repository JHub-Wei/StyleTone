import Foundation

/// Category of an authorized real-photo sample.
///
/// Samples are **never** committed to the repository: only their manifest
/// entries are. The project owner drops the files into a local, git-ignored
/// directory; see `Fixtures/README.md`.
public enum AuthorizedSampleCategory: String, Codable, Sendable, CaseIterable {
    case portrait
    case pairOriginal = "pair-original"
    case pairEdited = "pair-edited"
    case background
}

/// Fitzpatrick-style skin tone band used to keep coverage honest.
public enum SkinToneBand: Int, Codable, Sendable, CaseIterable {
    case i = 1
    case ii
    case iii
    case iv
    case v
    case vi

    public var roman: String {
        switch self {
        case .i: return "I"
        case .ii: return "II"
        case .iii: return "III"
        case .iv: return "IV"
        case .v: return "V"
        case .vi: return "VI"
        }
    }
}

/// One manifest entry for a locally stored, authorized photo.
public struct AuthorizedSample: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// File name relative to the local sample directory (never an absolute path).
    public var fileName: String
    public var category: AuthorizedSampleCategory
    public var skinTone: SkinToneBand?
    public var bodyType: String?
    /// Consent / license reference, e.g. `"written-consent-2026-01"`.
    public var license: String
    public var authorizedBy: String
    /// ISO-8601 date the sample was authorized.
    public var addedAt: String
    public var notes: String?

    public init(
        id: String,
        fileName: String,
        category: AuthorizedSampleCategory,
        skinTone: SkinToneBand? = nil,
        bodyType: String? = nil,
        license: String,
        authorizedBy: String,
        addedAt: String,
        notes: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.category = category
        self.skinTone = skinTone
        self.bodyType = bodyType
        self.license = license
        self.authorizedBy = authorizedBy
        self.addedAt = addedAt
        self.notes = notes
    }
}

/// The authorized sample manifest (`Fixtures/samples/manifest.json`).
///
/// The committed manifest is intentionally empty: real photos must not enter
/// the repository. Tests validate the schema and the no-committed-photos rule.
public struct AuthorizedSampleManifest: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var description: String
    public var samples: [AuthorizedSample]

    public init(
        schemaVersion: Int = AuthorizedSampleManifest.currentSchemaVersion,
        description: String,
        samples: [AuthorizedSample] = []
    ) {
        self.schemaVersion = schemaVersion
        self.description = description
        self.samples = samples
    }

    /// Validates the schema and rejects paths that could escape the local
    /// sample directory.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw GoldenSupportError.invalidManifest(
                reason: "unsupported sample manifest schemaVersion \(schemaVersion)"
            )
        }
        let identifiers = Set(samples.map(\.id))
        guard identifiers.count == samples.count else {
            throw GoldenSupportError.invalidManifest(reason: "sample ids are not unique")
        }
        for sample in samples {
            guard !sample.id.isEmpty, !sample.fileName.isEmpty else {
                throw GoldenSupportError.invalidManifest(reason: "sample id or file name is empty")
            }
            guard !sample.fileName.contains(".."),
                  !sample.fileName.contains("/"),
                  !sample.fileName.contains("\\")
            else {
                throw GoldenSupportError.invalidManifest(
                    reason: "sample '\(sample.id)' has an unsafe file name"
                )
            }
            guard !sample.license.isEmpty, !sample.authorizedBy.isEmpty else {
                throw GoldenSupportError.invalidManifest(
                    reason: "sample '\(sample.id)' is missing license or authorization"
                )
            }
            guard !sample.addedAt.isEmpty else {
                throw GoldenSupportError.invalidManifest(
                    reason: "sample '\(sample.id)' is missing addedAt"
                )
            }
        }
    }

    public func encodedJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        if prettyPrinted {
            formatting.insert(.prettyPrinted)
        }
        encoder.outputFormatting = formatting
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> AuthorizedSampleManifest {
        try JSONDecoder().decode(AuthorizedSampleManifest.self, from: data)
    }
}
