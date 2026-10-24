import Foundation
import StyleToneCore

// MARK: - Snapshot

/// Persistable session metadata.
///
/// This is deliberately metadata only: pair identities, timestamps, source
/// dimensions and quality grades. Photo bytes never enter the snapshot, so the
/// pairing UI cannot copy a library photo into the app container, a shared
/// container or anywhere else.
public struct PairingSessionSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let targetCount: Int
    public let stage: PairingStage
    public let startedAt: Date
    public let updatedAt: Date
    public let lastActivityAt: Date
    public let completedPairTimestamps: [Date]
    public let pairs: [PairingPairRecord]

    public init(
        schemaVersion: Int = PairingSessionSnapshot.currentSchemaVersion,
        targetCount: Int,
        stage: PairingStage,
        startedAt: Date,
        updatedAt: Date,
        lastActivityAt: Date,
        completedPairTimestamps: [Date] = [],
        pairs: [PairingPairRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.targetCount = targetCount
        self.stage = stage
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.lastActivityAt = lastActivityAt
        self.completedPairTimestamps = completedPairTimestamps
        self.pairs = pairs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case targetCount
        case stage
        case startedAt
        case updatedAt
        case lastActivityAt
        case completedPairTimestamps
        case pairs
    }

    /// Decodes with defaults for fields added after schema 1, so a stored
    /// session never fails to load because a new optional field is absent.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        targetCount = try container.decodeIfPresent(Int.self, forKey: .targetCount)
            ?? PairingTarget.defaultTarget.count
        stage = try container.decodeIfPresent(PairingStage.self, forKey: .stage) ?? .editing
        let decodedStart = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        startedAt = decodedStart ?? Date(timeIntervalSince1970: 0)
        let decodedUpdate = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        updatedAt = decodedUpdate ?? startedAt
        lastActivityAt = try container.decodeIfPresent(Date.self, forKey: .lastActivityAt)
            ?? updatedAt
        completedPairTimestamps = try container.decodeIfPresent(
            [Date].self,
            forKey: .completedPairTimestamps
        ) ?? []
        pairs = try container.decodeIfPresent([PairingPairRecord].self, forKey: .pairs) ?? []
    }
}

/// Persistable metadata for one pair.
public struct PairingPairRecord: Codable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let contentRevision: Int
    public let original: PairingPhotoRecord?
    public let edited: PairingPhotoRecord?
    public let quality: PairQuality?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        contentRevision: Int,
        original: PairingPhotoRecord?,
        edited: PairingPhotoRecord?,
        quality: PairQuality?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contentRevision = contentRevision
        self.original = original
        self.edited = edited
        self.quality = quality
    }
}

/// Persistable metadata for one picked photo.
public struct PairingPhotoRecord: Codable, Sendable, Equatable {
    /// Opaque picker identifier; never logged and never used for networking.
    public let sourceIdentifier: String?
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let displayWidth: Int
    public let displayHeight: Int
    public let byteCount: Int
    public let importedAt: Date

    public init(
        sourceIdentifier: String?,
        sourceWidth: Int,
        sourceHeight: Int,
        displayWidth: Int,
        displayHeight: Int,
        byteCount: Int,
        importedAt: Date
    ) {
        self.sourceIdentifier = sourceIdentifier
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.byteCount = byteCount
        self.importedAt = importedAt
    }

    public var sourcePixelSize: PixelSize {
        PixelSize(width: sourceWidth, height: sourceHeight)
    }

    public var displayPixelSize: PixelSize {
        PixelSize(width: displayWidth, height: displayHeight)
    }
}

// MARK: - Session conversion

public extension PairingSessionState {
    /// Captures the session as metadata for the store.
    func snapshot() -> PairingSessionSnapshot {
        PairingSessionSnapshot(
            targetCount: target.count,
            stage: stage,
            startedAt: timeline.startedAt,
            updatedAt: updatedAt,
            lastActivityAt: timeline.lastActivityAt,
            completedPairTimestamps: timeline.completedPairTimestamps,
            pairs: pairs.map(PairingPairRecord.init(pair:))
        )
    }

    /// Restores a session from metadata.
    ///
    /// Photos are intentionally absent after a relaunch: only their metadata
    /// was stored. Each originally filled slot is flagged for re-selection so
    /// the pair itself is never lost, and the previous quality grade stays in
    /// the record until both photos are picked again.
    init(snapshot: PairingSessionSnapshot, restoredAt: Date) throws {
        guard snapshot.schemaVersion == PairingSessionSnapshot.currentSchemaVersion else {
            throw PairingSessionStoreError.unsupportedSchema(version: snapshot.schemaVersion)
        }

        var timeline = PairingTimeline(startedAt: snapshot.startedAt)
        timeline.lastActivityAt = snapshot.lastActivityAt
        timeline.completedPairTimestamps = snapshot.completedPairTimestamps

        self.init(
            target: PairingTarget(count: snapshot.targetCount) ?? .defaultTarget,
            stage: snapshot.stage,
            pairs: snapshot.pairs.prefix(Self.maximumPairs).map { $0.makePairState() },
            timeline: timeline,
            lastDeletion: nil,
            updatedAt: snapshot.updatedAt
        )
    }
}

extension PairingPairRecord {
    init(pair: PairingPairState) {
        self.init(
            id: pair.id,
            createdAt: pair.createdAt,
            updatedAt: pair.updatedAt,
            contentRevision: pair.contentRevision,
            original: pair.original.map(PairingPhotoRecord.init(photo:)),
            edited: pair.edited.map(PairingPhotoRecord.init(photo:)),
            quality: pair.quality
        )
    }

    func makePairState() -> PairingPairState {
        var assessment: PairingAssessmentState = .waitingForImages
        if let quality {
            assessment = .completed(quality)
        }
        return PairingPairState(
            id: id,
            createdAt: createdAt,
            original: nil,
            edited: nil,
            assessment: assessment,
            updatedAt: updatedAt,
            contentRevision: contentRevision,
            needsReselectOriginal: original != nil,
            needsReselectEdited: edited != nil
        )
    }
}

extension PairingPhotoRecord {
    init(photo: PairingPhoto) {
        self.init(
            sourceIdentifier: photo.sourceIdentifier,
            sourceWidth: photo.sourcePixelSize.width,
            sourceHeight: photo.sourcePixelSize.height,
            displayWidth: photo.displayPixelSize.width,
            displayHeight: photo.displayPixelSize.height,
            byteCount: photo.byteCount,
            importedAt: photo.importedAt
        )
    }
}
