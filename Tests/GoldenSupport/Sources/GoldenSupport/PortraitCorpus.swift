import Foundation
import StyleToneCore

// MARK: - Sample dimensions

/// Body silhouette family used by the synthetic portrait corpus.
///
/// The values are deliberately qualitative: the renderer maps each family to
/// shoulder/waist/hip proportions, the quality gates only require that every
/// family is represented. This keeps the corpus readable and leaves room for
/// the renderer to be tuned without rewriting 100 sample descriptions.
public enum PortraitBodyType: String, Codable, Sendable, CaseIterable {
    case slim
    case average
    case curvy
    case plus
    case tall
    case petite
}

/// How much of the subject is inside the frame.
public enum PortraitFraming: String, Codable, Sendable, CaseIterable {
    case headshot
    case halfBody
    case fullBody

    /// Human-readable label used in reports.
    public var displayName: String {
        switch self {
        case .headshot: return "headshot"
        case .halfBody: return "half-body"
        case .fullBody: return "full-body"
        }
    }
}

/// Background family of a synthetic portrait.
public enum PortraitBackgroundKind: String, Codable, Sendable, CaseIterable {
    case doorFrame
    case floorTiles
    case doorFrameAndTiles
    case window
    case tableEdge
    case plain

    /// `true` when the renderer draws straight man-made structure.
    public var hasStraightStructure: Bool {
        self != .plain
    }

    /// Human-readable label used in reports.
    public var displayName: String {
        switch self {
        case .doorFrame: return "door-frame"
        case .floorTiles: return "floor-tiles"
        case .doorFrameAndTiles: return "door-frame+tiles"
        case .window: return "window"
        case .tableEdge: return "table-edge"
        case .plain: return "plain"
        }
    }
}

/// Deliberate occlusion family. Occlusion is a first-class corpus dimension
/// because the geometry/retouch pipeline behaves differently when a face, arm
/// or torso is partially hidden.
public enum PortraitOcclusion: String, Codable, Sendable, CaseIterable {
    case none
    case hairOverFace
    case handAtChin
    case armAcrossTorso
    case objectInFront
    case scarf
    case looseSleeves

    /// Human-readable label used in reports.
    public var displayName: String {
        switch self {
        case .none: return "none"
        case .hairOverFace: return "hair-over-face"
        case .handAtChin: return "hand-at-chin"
        case .armAcrossTorso: return "arm-across-torso"
        case .objectInFront: return "object-in-front"
        case .scarf: return "scarf"
        case .looseSleeves: return "loose-sleeves"
        }
    }
}

/// Lighting setup. It changes the rendered exposure/tint, not the ground truth.
public enum PortraitLighting: String, Codable, Sendable, CaseIterable {
    case softKey
    case sideKey
    case backlit
    case lowKey
    case highKey
    case mixed

    /// Human-readable label used in reports.
    public var displayName: String {
        switch self {
        case .softKey: return "soft-key"
        case .sideKey: return "side-key"
        case .backlit: return "backlit"
        case .lowKey: return "low-key"
        case .highKey: return "high-key"
        case .mixed: return "mixed"
        }
    }
}

/// Role of one person in a sample.
public enum PortraitSubjectRole: String, Codable, Sendable, CaseIterable {
    case primary
    case partner
    case extra
}

// MARK: - Sample description

/// One person inside a synthetic sample.
public struct PortraitSubjectSpec: Codable, Sendable, Equatable {
    /// Role; the first subject must be `.primary`.
    public var role: PortraitSubjectRole
    /// Fitzpatrick-style skin band I...VI.
    public var skinTone: SkinToneBand
    /// Body silhouette family.
    public var bodyType: PortraitBodyType
    /// Deliberate occlusion applied to this subject. Secondary subjects use
    /// `.none` in the committed corpus.
    public var occlusion: PortraitOcclusion
    /// Horizontal shift relative to the frame centre, in `-0.4...0.4`.
    public var xOffset: Double
    /// Scale relative to the primary subject, in `0.5...1.0`. The primary
    /// subject is always `1`.
    public var scale: Double
    /// Deterministic seed for hair, clothing and blemish variation.
    public var seed: UInt64

    public init(
        role: PortraitSubjectRole,
        skinTone: SkinToneBand,
        bodyType: PortraitBodyType,
        occlusion: PortraitOcclusion = .none,
        xOffset: Double = 0,
        scale: Double = 1,
        seed: UInt64 = 1
    ) {
        self.role = role
        self.skinTone = skinTone
        self.bodyType = bodyType
        self.occlusion = occlusion
        self.xOffset = min(max(xOffset, -0.4), 0.4)
        self.scale = min(max(scale, 0.5), 1)
        self.seed = seed
    }

    /// Human-readable coverage label, e.g. `IV/curvy`.
    public var coverageLabel: String {
        "\(skinTone.roman)/\(bodyType.rawValue)"
    }
}

/// One synthetic portrait sample.
public struct PortraitSampleSpec: Codable, Sendable, Equatable, Identifiable {
    /// Stable identifier, `ps-001`...`ps-100` for the committed corpus.
    public var id: String
    /// Master deterministic seed for background variation and texture.
    public var seed: UInt64
    public var width: Int
    public var height: Int
    public var framing: PortraitFraming
    public var background: PortraitBackgroundKind
    public var lighting: PortraitLighting
    /// Subjects, primary first, at most three.
    public var subjects: [PortraitSubjectSpec]
    /// Short reviewer note. Contains no personal data.
    public var note: String

    public init(
        id: String,
        seed: UInt64,
        width: Int = 360,
        height: Int = 480,
        framing: PortraitFraming,
        background: PortraitBackgroundKind,
        lighting: PortraitLighting,
        subjects: [PortraitSubjectSpec],
        note: String = ""
    ) {
        self.id = id
        self.seed = seed
        self.width = width
        self.height = height
        self.framing = framing
        self.background = background
        self.lighting = lighting
        self.subjects = subjects
        self.note = note
    }

    /// Renderer pixel size.
    public var pixelSize: PixelSize {
        PixelSize(width: width, height: height)
    }

    /// The primary subject. Corpus validation guarantees it exists and is first.
    public var primarySubject: PortraitSubjectSpec {
        subjects.first ?? PortraitSubjectSpec(
            role: .primary,
            skinTone: .iii,
            bodyType: .average
        )
    }

    /// `true` when more than one person is in the frame.
    public var isMultiPerson: Bool {
        subjects.count > 1
    }

    /// `true` when a deliberate occlusion is applied to any subject.
    public var hasOcclusion: Bool {
        subjects.contains { $0.occlusion != .none }
    }

    /// Structural validation. Does not check corpus-wide coverage quotas.
    public func validate() throws {
        guard !id.isEmpty else {
            throw GoldenSupportError.invalidManifest(reason: "portrait sample id is empty")
        }
        guard width >= 96, height >= 128, width <= 4096, height <= 4096 else {
            throw GoldenSupportError.invalidManifest(
                reason: "portrait sample '\(id)' has unsupported dimensions \(width)x\(height)"
            )
        }
        guard subjects.count >= 1, subjects.count <= 3 else {
            throw GoldenSupportError.invalidManifest(
                reason: "portrait sample '\(id)' must contain 1...3 subjects"
            )
        }
        guard subjects[0].role == .primary else {
            throw GoldenSupportError.invalidManifest(
                reason: "portrait sample '\(id)' must list the primary subject first"
            )
        }
        guard subjects.filter({ $0.role == .primary }).count == 1 else {
            throw GoldenSupportError.invalidManifest(
                reason: "portrait sample '\(id)' must contain exactly one primary subject"
            )
        }
        for subject in subjects {
            guard subject.scale > 0, subject.scale <= 1.0001 else {
                throw GoldenSupportError.invalidManifest(
                    reason: "portrait sample '\(id)' has an invalid subject scale"
                )
            }
            guard abs(subject.xOffset) <= 0.4 else {
                throw GoldenSupportError.invalidManifest(
                    reason: "portrait sample '\(id)' has a subject outside the frame"
                )
            }
        }
        if framing == .headshot, subjects.contains(where: { $0.occlusion == .armAcrossTorso }) {
            throw GoldenSupportError.invalidManifest(
                reason: "portrait sample '\(id)' uses arm occlusion in a headshot"
            )
        }
    }

    /// Human-readable category label for reports.
    public var coverageLabel: String {
        let tones = subjects.map(\.skinTone.roman).joined(separator: "/")
        return "\(tones) \(bodyTypeLabel) \(framing.displayName) "
            + "\(background.displayName) \(occlusionLabel) \(subjects.count)p"
    }

    /// Primary body type raw value.
    public var bodyTypeLabel: String {
        primarySubject.bodyType.rawValue
    }

    /// Occlusion labels, primary first.
    public var occlusionLabel: String {
        subjects
            .map(\.occlusion)
            .filter { $0 != .none }
            .map(\.displayName)
            .joined(separator: "+")
    }
}

// MARK: - Corpus document

/// Coverage counts derived from a corpus. Every dictionary is keyed by the
/// stable raw value or Roman numeral so the committed baseline can be diffed.
public struct PortraitCorpusCoverage: Codable, Sendable, Equatable {
    public var sampleCount: Int
    public var skinTones: [String: Int]
    public var bodyTypes: [String: Int]
    public var backgrounds: [String: Int]
    public var framings: [String: Int]
    public var personCounts: [String: Int]
    public var occlusions: [String: Int]
    public var multiPersonSamples: Int
    public var occlusionSamples: Int
    public var doorFrameSamples: Int
    public var floorTileSamples: Int
    public var straightStructureSamples: Int
    public var skinToneBandsCovered: Int

    public init(
        sampleCount: Int,
        skinTones: [String: Int],
        bodyTypes: [String: Int],
        backgrounds: [String: Int],
        framings: [String: Int],
        personCounts: [String: Int],
        occlusions: [String: Int],
        multiPersonSamples: Int,
        occlusionSamples: Int,
        doorFrameSamples: Int,
        floorTileSamples: Int,
        straightStructureSamples: Int,
        skinToneBandsCovered: Int
    ) {
        self.sampleCount = sampleCount
        self.skinTones = skinTones
        self.bodyTypes = bodyTypes
        self.backgrounds = backgrounds
        self.framings = framings
        self.personCounts = personCounts
        self.occlusions = occlusions
        self.multiPersonSamples = multiPersonSamples
        self.occlusionSamples = occlusionSamples
        self.doorFrameSamples = doorFrameSamples
        self.floorTileSamples = floorTileSamples
        self.straightStructureSamples = straightStructureSamples
        self.skinToneBandsCovered = skinToneBandsCovered
    }

    /// Markdown table for the CI job summary / README.
    public func markdown() -> String {
        var lines: [String] = []
        lines.append("| dimension | coverage |")
        lines.append("|---|---|")
        lines.append("| samples | \(sampleCount) |")
        lines.append(
            "| skin tone I...VI | "
                + SkinToneBand.allCases.map { "\($0.roman)=\(skinTones[$0.roman] ?? 0)" }
                .joined(separator: ", ")
                + " |"
        )
        lines.append(
            "| body types | "
                + PortraitBodyType.allCases.map { "\($0.rawValue)=\(bodyTypes[$0.rawValue] ?? 0)" }
                .joined(separator: ", ")
                + " |"
        )
        lines.append(
            "| backgrounds | "
                + PortraitBackgroundKind.allCases
                .map { "\($0.displayName)=\(backgrounds[$0.rawValue] ?? 0)" }
                .joined(separator: ", ")
                + " |"
        )
        lines.append(
            "| framing | "
                + PortraitFraming.allCases.map { "\($0.displayName)=\(framings[$0.rawValue] ?? 0)" }
                .joined(separator: ", ")
                + " |"
        )
        lines.append("| multi-person | \(multiPersonSamples) |")
        lines.append("| occlusion | \(occlusionSamples) |")
        lines.append("| door frames | \(doorFrameSamples) |")
        lines.append("| floor tiles | \(floorTileSamples) |")
        lines.append("| straight structure | \(straightStructureSamples) |")
        return lines.joined(separator: "\n")
    }
}

/// The committed 100-sample synthetic portrait corpus document.
///
/// The corpus is metadata only: the pixels are regenerated deterministically by
/// ``PortraitRenderer``. No photograph, face derived from a photograph or
/// biometric template is stored in the repository.
public struct PortraitCorpus: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    /// Acceptance corpus size (task card WP-25).
    public static let acceptanceSampleCount = 100

    public var schemaVersion: Int
    public var corpusVersion: String
    public var generator: String
    public var description: String
    public var samples: [PortraitSampleSpec]

    public init(
        schemaVersion: Int = PortraitCorpus.currentSchemaVersion,
        corpusVersion: String,
        generator: String,
        description: String,
        samples: [PortraitSampleSpec]
    ) {
        self.schemaVersion = schemaVersion
        self.corpusVersion = corpusVersion
        self.generator = generator
        self.description = description
        self.samples = samples
    }

    /// Decodes a corpus document.
    public static func decode(_ data: Data) throws -> PortraitCorpus {
        do {
            return try JSONDecoder().decode(PortraitCorpus.self, from: data)
        } catch let error as GoldenSupportError {
            throw error
        } catch {
            throw GoldenSupportError.invalidManifest(
                reason: "portrait corpus is not valid JSON: \(error.localizedDescription)"
            )
        }
    }

    /// Encodes the corpus with sorted keys for stable reviews.
    public func encodedJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        if prettyPrinted {
            formatting.insert(.prettyPrinted)
        }
        encoder.outputFormatting = formatting
        return try encoder.encode(self)
    }

    /// Structural validation of every sample.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw GoldenSupportError.invalidManifest(
                reason: "unsupported portrait corpus schemaVersion \(schemaVersion)"
            )
        }
        guard !corpusVersion.isEmpty, !generator.isEmpty else {
            throw GoldenSupportError.invalidManifest(
                reason: "portrait corpus metadata is empty"
            )
        }
        guard samples.count >= Self.acceptanceSampleCount else {
            throw GoldenSupportError.invalidManifest(
                reason: "portrait corpus has \(samples.count) samples, "
                    + "expected at least \(Self.acceptanceSampleCount)"
            )
        }
        let identifiers = Set(samples.map(\.id))
        guard identifiers.count == samples.count else {
            throw GoldenSupportError.invalidManifest(
                reason: "portrait sample ids are not unique"
            )
        }
        for sample in samples {
            try sample.validate()
        }
    }

    /// Validates the acceptance coverage quotas from the WP-25 card.
    ///
    /// The quotas are intentionally explicit so a future "cleanup" cannot
    /// silently drop a skin tone, body type, occlusion or structure class.
    public func validateCoverage() throws {
        let coverage = self.coverage
        guard coverage.sampleCount == Self.acceptanceSampleCount else {
            throw GoldenSupportError.invalidManifest(
                reason: "acceptance corpus must contain exactly "
                    + "\(Self.acceptanceSampleCount) samples"
            )
        }
        guard coverage.skinToneBandsCovered == 6 else {
            throw GoldenSupportError.invalidManifest(
                reason: "corpus must cover Fitzpatrick I...VI"
            )
        }
        for tone in SkinToneBand.allCases {
            let count = coverage.skinTones[tone.roman] ?? 0
            guard count >= 10 else {
                throw GoldenSupportError.invalidManifest(
                    reason: "skin tone \(tone.roman) has only \(count) samples (expected >= 10)"
                )
            }
        }
        for bodyType in PortraitBodyType.allCases {
            let count = coverage.bodyTypes[bodyType.rawValue] ?? 0
            guard count >= 10 else {
                throw GoldenSupportError.invalidManifest(
                    reason: "body type \(bodyType.rawValue) has only \(count) samples "
                        + "(expected >= 10)"
                )
            }
        }
        for background in PortraitBackgroundKind.allCases where background.hasStraightStructure {
            let count = coverage.backgrounds[background.rawValue] ?? 0
            guard count >= 10 else {
                throw GoldenSupportError.invalidManifest(
                    reason: "background \(background.displayName) has only \(count) samples "
                        + "(expected >= 10)"
                )
            }
        }
        guard coverage.doorFrameSamples >= 30 else {
            throw GoldenSupportError.invalidManifest(
                reason: "corpus must contain >= 30 door-frame samples"
            )
        }
        guard coverage.floorTileSamples >= 30 else {
            throw GoldenSupportError.invalidManifest(
                reason: "corpus must contain >= 30 floor-tile samples"
            )
        }
        for framing in PortraitFraming.allCases {
            let count = coverage.framings[framing.rawValue] ?? 0
            guard count >= 15 else {
                throw GoldenSupportError.invalidManifest(
                    reason: "framing \(framing.displayName) has only \(count) samples "
                        + "(expected >= 15)"
                )
            }
        }
        guard coverage.multiPersonSamples >= 25 else {
            throw GoldenSupportError.invalidManifest(
                reason: "corpus must contain >= 25 multi-person samples"
            )
        }
        guard coverage.occlusionSamples >= 30 else {
            throw GoldenSupportError.invalidManifest(
                reason: "corpus must contain >= 30 occluded samples"
            )
        }
    }

    /// Derived coverage counts.
    public var coverage: PortraitCorpusCoverage {
        var skinTones: [String: Int] = [:]
        var bodyTypes: [String: Int] = [:]
        var backgrounds: [String: Int] = [:]
        var framings: [String: Int] = [:]
        var personCounts: [String: Int] = [:]
        var occlusions: [String: Int] = [:]
        var multiPersonSamples = 0
        var occlusionSamples = 0
        var doorFrameSamples = 0
        var floorTileSamples = 0
        var straightStructureSamples = 0

        for sample in samples {
            skinTones[sample.primarySubject.skinTone.roman, default: 0] += 1
            bodyTypes[sample.primarySubject.bodyType.rawValue, default: 0] += 1
            backgrounds[sample.background.rawValue, default: 0] += 1
            framings[sample.framing.rawValue, default: 0] += 1
            personCounts[String(sample.subjects.count), default: 0] += 1
            if sample.subjects.count > 1 {
                multiPersonSamples += 1
            }
            if sample.hasOcclusion {
                occlusionSamples += 1
            }
            for subject in sample.subjects where subject.occlusion != .none {
                occlusions[subject.occlusion.rawValue, default: 0] += 1
            }
            if sample.background == .doorFrame || sample.background == .doorFrameAndTiles {
                doorFrameSamples += 1
            }
            if sample.background == .floorTiles || sample.background == .doorFrameAndTiles {
                floorTileSamples += 1
            }
            if sample.background.hasStraightStructure {
                straightStructureSamples += 1
            }
        }

        return PortraitCorpusCoverage(
            sampleCount: samples.count,
            skinTones: skinTones,
            bodyTypes: bodyTypes,
            backgrounds: backgrounds,
            framings: framings,
            personCounts: personCounts,
            occlusions: occlusions,
            multiPersonSamples: multiPersonSamples,
            occlusionSamples: occlusionSamples,
            doorFrameSamples: doorFrameSamples,
            floorTileSamples: floorTileSamples,
            straightStructureSamples: straightStructureSamples,
            skinToneBandsCovered: skinTones.keys.count
        )
    }
}
