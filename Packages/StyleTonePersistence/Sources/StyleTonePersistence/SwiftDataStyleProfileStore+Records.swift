import Foundation
import StyleToneCore
import SwiftData

// MARK: - Edit history

public extension SwiftDataStyleProfileStore {
    /// Persists one edit session. Photos are never stored; only the opaque
    /// `inputReference` and the small adjustment blob are kept.
    @discardableResult
    func recordEdit(_ draft: EditDraft) async throws -> EditRecordSnapshot {
        let reference = draft.inputReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty, reference.count <= 256 else {
            throw StylePersistenceError.invalidRecord
        }

        let encodedAdjustments: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encodedAdjustments = try encoder.encode(draft.adjustments)
        } catch {
            throw StylePersistenceError.invalidRecord
        }

        let id = UUID()
        let now = dateProvider.now
        try withContext { context in
            let record = EditRecord(
                id: id,
                styleID: draft.styleID,
                inputReference: reference,
                adjustmentsData: encodedAdjustments,
                createdAt: now,
                exported: false,
                exportedAt: nil
            )
            context.insert(record)
            try context.save()
        }
        protectIndexFiles()

        return EditRecordSnapshot(
            id: id,
            styleID: draft.styleID,
            inputReference: reference,
            adjustments: draft.adjustments,
            createdAt: now,
            exported: false,
            exportedAt: nil
        )
    }

    /// Most recent edits first. Rows whose adjustment blob cannot be decoded are
    /// skipped rather than failing the whole history.
    func edits(limit: Int = 50) async throws -> [EditRecordSnapshot] {
        guard limit > 0 else {
            return []
        }
        let boundedLimit = min(limit, 500)
        return try withContext { context -> [EditRecordSnapshot] in
            let records = try context.fetch(FetchDescriptor<EditRecord>())
            return records
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(boundedLimit)
                .compactMap { record in
                    guard let adjustments = try? JSONDecoder().decode(
                        ManualAdjustments.self,
                        from: record.adjustmentsData
                    ) else {
                        return nil
                    }
                    return EditRecordSnapshot(
                        id: record.id,
                        styleID: record.styleID,
                        inputReference: record.inputReference,
                        adjustments: adjustments,
                        createdAt: record.createdAt,
                        exported: record.exported,
                        exportedAt: record.exportedAt
                    )
                }
        }
    }

    /// Marks an edit as successfully exported. The original export timestamp is
    /// preserved if the edit was already marked.
    func markEditExported(id: UUID, at date: Date? = nil) async throws {
        let timestamp = date ?? dateProvider.now
        let found = try withContext { context -> Bool in
            let records = try context.fetch(FetchDescriptor<EditRecord>())
            guard let record = records.first(where: { $0.id == id }) else {
                return false
            }
            record.exported = true
            record.exportedAt = record.exportedAt ?? timestamp
            try context.save()
            return true
        }
        guard found else {
            throw StylePersistenceError.recordNotFound
        }
        protectIndexFiles()
    }

    /// Idempotent: deleting a missing edit is a no-op.
    func deleteEdit(id: UUID) async throws {
        let deleted = try withContext { context -> Bool in
            let records = try context.fetch(FetchDescriptor<EditRecord>())
            guard let record = records.first(where: { $0.id == id }) else {
                return false
            }
            context.delete(record)
            try context.save()
            return true
        }
        if deleted {
            protectIndexFiles()
        }
    }

    func deleteAllEdits() async throws {
        try withContext { context in
            for record in try context.fetch(FetchDescriptor<EditRecord>()) {
                context.delete(record)
            }
            try context.save()
        }
        protectIndexFiles()
    }
}

// MARK: - Pairing sessions

public extension SwiftDataStyleProfileStore {
    /// Creates or updates a calibration session. Existing sessions keep their
    /// original `createdAt`; `updatedAt` is always refreshed.
    @discardableResult
    func savePairSession(_ draft: PairSessionDraft) async throws -> PairSessionSnapshot {
        let references = draft.pairReferences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard references.count <= 32,
              (3...8).contains(draft.targetPairCount),
              (0...64).contains(draft.abChoiceCount)
        else {
            throw StylePersistenceError.invalidRecord
        }

        let id = draft.id ?? UUID()
        let now = dateProvider.now
        let snapshot = try withContext { context -> PairSessionSnapshot in
            let records = try context.fetch(FetchDescriptor<PairSessionRecord>())
            let existing = records.first(where: { $0.id == id })
            let createdAt = existing?.createdAt ?? now

            let record: PairSessionRecord
            if let existing {
                record = existing
            } else {
                record = PairSessionRecord(
                    id: id,
                    pairReferences: references,
                    targetPairCount: draft.targetPairCount,
                    abChoiceCount: draft.abChoiceCount,
                    status: draft.status,
                    createdAt: createdAt,
                    updatedAt: now
                )
                context.insert(record)
            }

            record.pairReferences = references
            record.targetPairCount = draft.targetPairCount
            record.abChoiceCount = draft.abChoiceCount
            record.statusRawValue = draft.status.rawValue
            record.updatedAt = now
            try context.save()

            return PairSessionSnapshot(
                id: id,
                pairReferences: references,
                targetPairCount: draft.targetPairCount,
                abChoiceCount: draft.abChoiceCount,
                status: draft.status,
                createdAt: createdAt,
                updatedAt: now
            )
        }
        protectIndexFiles()
        return snapshot
    }

    /// Most recently updated sessions first.
    func pairSessions(limit: Int = 20) async throws -> [PairSessionSnapshot] {
        guard limit > 0 else {
            return []
        }
        let boundedLimit = min(limit, 100)
        return try withContext { context -> [PairSessionSnapshot] in
            let records = try context.fetch(FetchDescriptor<PairSessionRecord>())
            return records
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(boundedLimit)
                .map { record in
                    PairSessionSnapshot(
                        id: record.id,
                        pairReferences: record.pairReferences,
                        targetPairCount: record.targetPairCount,
                        abChoiceCount: record.abChoiceCount,
                        status: record.status,
                        createdAt: record.createdAt,
                        updatedAt: record.updatedAt
                    )
                }
        }
    }

    func latestPairSession() async throws -> PairSessionSnapshot? {
        let sessions = try await pairSessions(limit: 1)
        return sessions.first
    }

    /// Idempotent: deleting a missing session is a no-op.
    func deletePairSession(id: UUID) async throws {
        let deleted = try withContext { context -> Bool in
            let records = try context.fetch(FetchDescriptor<PairSessionRecord>())
            guard let record = records.first(where: { $0.id == id }) else {
                return false
            }
            context.delete(record)
            try context.save()
            return true
        }
        if deleted {
            protectIndexFiles()
        }
    }

    func deleteAllPairSessions() async throws {
        try withContext { context in
            for record in try context.fetch(FetchDescriptor<PairSessionRecord>()) {
                context.delete(record)
            }
            try context.save()
        }
        protectIndexFiles()
    }
}

// MARK: - Free-export quota

public extension SwiftDataStyleProfileStore {
    /// Current local quota. Reading never creates a row.
    func quota() async throws -> QuotaSnapshot {
        let now = dateProvider.now
        return try withContext { context -> QuotaSnapshot in
            let records = try context.fetch(FetchDescriptor<QuotaRecord>())
            let record = records.first { $0.key == QuotaPolicy.singletonKey }
            return QuotaSnapshot(
                freeExportsUsed: record?.freeExportsUsed ?? 0,
                updatedAt: record?.updatedAt ?? now
            )
        }
    }

    /// Counts one successful export. Failed or cancelled exports must not call
    /// this method.
    @discardableResult
    func recordSuccessfulExport() async throws -> QuotaSnapshot {
        let now = dateProvider.now
        let snapshot = try withContext { context -> QuotaSnapshot in
            let records = try context.fetch(FetchDescriptor<QuotaRecord>())
            let existing = records.first { $0.key == QuotaPolicy.singletonKey }
            let record: QuotaRecord
            if let existing {
                record = existing
            } else {
                record = QuotaRecord(freeExportsUsed: 0, updatedAt: now)
                context.insert(record)
            }
            if record.freeExportsUsed < Int.max {
                record.freeExportsUsed += 1
            }
            record.updatedAt = now
            try context.save()
            return QuotaSnapshot(
                freeExportsUsed: record.freeExportsUsed,
                updatedAt: now
            )
        }
        protectIndexFiles()
        return snapshot
    }

    /// Resets the local quota. Deleting all data also resets it.
    @discardableResult
    func resetQuota() async throws -> QuotaSnapshot {
        let now = dateProvider.now
        let snapshot = try withContext { context -> QuotaSnapshot in
            let records = try context.fetch(FetchDescriptor<QuotaRecord>())
            guard let record = records.first(where: { $0.key == QuotaPolicy.singletonKey }) else {
                return QuotaSnapshot(freeExportsUsed: 0, updatedAt: now)
            }
            record.freeExportsUsed = 0
            record.updatedAt = now
            try context.save()
            return QuotaSnapshot(freeExportsUsed: 0, updatedAt: now)
        }
        protectIndexFiles()
        return snapshot
    }
}
