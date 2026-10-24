import Foundation
import StyleToneCore
import SwiftData

/// SwiftData + JSON implementation of ``StyleProfileStore``.
///
/// ## Storage layout
///
/// ```text
/// <base>/
///   style-index.store                 SwiftData index (metadata only)
///   style-profiles/{uuid}.json        canonical profile documents
///   style-profile-migration-backups/  originals superseded by a migration
///   style-profile-recovery/           quarantined unreadable profiles
///   style-index-recovery/             quarantined SwiftData stores
///   style-thumbnails/                 owned by the UI/Imaging layers
/// ```
///
/// The JSON document is the source of truth; SwiftData only indexes it. If the
/// index cannot be opened, it is quarantined and rebuilt from the JSON files on
/// the next read, so a damaged index never destroys a profile.
///
/// ## Concurrency
///
/// The store is an `actor`: every read/modify/write transaction is serialized
/// and all file/SwiftData work happens on the actor's executor, never on the
/// main actor. The initializer only stores configuration, so creating the store
/// on the main thread does not touch the file system.
public actor SwiftDataStyleProfileStore: StyleProfileStore {
    let configuration: PersistenceConfiguration
    let paths: PersistencePaths
    let fileSystem: any PersistenceFileSystem
    let logger: any AppLogging
    let dateProvider: any DateProviding

    private var container: ModelContainer?

    public init(
        configuration: PersistenceConfiguration = PersistenceConfiguration(),
        fileSystem: any PersistenceFileSystem = LocalPersistenceFileSystem(),
        logger: any AppLogging = NoopLogger(),
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.configuration = configuration
        self.paths = PersistencePaths(baseDirectory: configuration.baseDirectory)
        self.fileSystem = fileSystem
        self.logger = logger
        self.dateProvider = dateProvider
    }

    // MARK: - StyleProfileStore

    /// Loads the active profile, or `nil` when the user has not calibrated yet.
    ///
    /// Legacy documents are migrated and rewritten once, with the original
    /// bytes retained in `style-profile-migration-backups/`. A newer schema or
    /// unreadable JSON is reported with a recalibration recovery action and the
    /// original file is left untouched.
    public func loadActive() async throws -> StyleProfile? {
        let active = try withContext { context -> ActiveProfileDescriptor? in
            let records = try context.fetch(FetchDescriptor<StyleProfileRecord>())
            guard let record = activeRecord(in: records) else {
                return nil
            }
            return ActiveProfileDescriptor(id: record.id, fileName: record.fileName)
        }

        if let active {
            let url = paths.profilesDirectory.appendingPathComponent(active.fileName)
            guard fileSystem.exists(url) else {
                logger.log(.warning, "Active style profile file is missing; rebuilding the index", metadata: [:])
                try deactivateAllProfiles()
                return try rebuildActiveProfile()
            }

            let decoded = try readProfile(at: url)
            if decoded.migrated {
                do {
                    try updateIndexAfterMigration(recordID: active.id, profile: decoded.profile)
                } catch {
                    logger.log(.warning, "Migrated style profile but could not refresh its index row", metadata: [:])
                }
            }
            return decoded.profile
        }

        return try rebuildActiveProfile()
    }

    /// Writes the profile JSON, then makes it the single active index row.
    ///
    /// Saving an existing active profile reuses its UUID and file name, so the
    /// identity is stable across edits and no orphan files accumulate.
    public func save(_ profile: StyleProfile) async throws {
        let sanitized = StyleProfileSanitizer.sanitized(profile)
        let data: Data
        do {
            data = try StyleProfileJSONMigrator.encode(sanitized)
        } catch {
            throw StylePersistenceError.invalidRecord
        }

        let target = try withContext { context -> (id: UUID, fileName: String) in
            let records = try context.fetch(FetchDescriptor<StyleProfileRecord>())
            let active = records
                .filter { $0.isActive }
                .max { $0.updatedAt < $1.updatedAt }
            if let active, !active.fileName.isEmpty, active.fileName.hasSuffix(".json") {
                return (active.id, active.fileName)
            }
            let id = UUID()
            return (id, "\(id.uuidString.lowercased()).json")
        }

        try ensureDirectory(paths.profilesDirectory)
        let profileURL = paths.profilesDirectory.appendingPathComponent(target.fileName)
        do {
            try fileSystem.write(data, to: profileURL, protection: configuration.fileProtection)
        } catch {
            throw StylePersistenceError.ioFailed
        }

        let now = dateProvider.now
        try withContext { context in
            let records = try context.fetch(FetchDescriptor<StyleProfileRecord>())
            let existing = records.first { $0.id == target.id }
            for record in records where record.id != target.id {
                record.isActive = false
            }

            let record: StyleProfileRecord
            if let existing {
                record = existing
            } else {
                record = StyleProfileRecord(
                    id: target.id,
                    fileName: target.fileName,
                    pairCount: sanitized.pairCount,
                    confidence: sanitized.confidence,
                    tagKeys: sanitized.tags,
                    createdAt: now,
                    updatedAt: sanitized.updatedAt,
                    isActive: true
                )
                context.insert(record)
            }

            apply(sanitized, to: record)
            record.isActive = true
            try context.save()
        }
        protectIndexFiles()

        logger.log(.info, "Saved style profile", metadata: [
            "schema": "\(sanitized.schemaVersion)",
            "confidence": sanitized.confidence.rawValue
        ])
    }

    /// Deletes every profile, edit, pairing session, quota row and cached file.
    ///
    /// The SwiftData store file is removed when the file system allows it. Even
    /// when the file itself cannot be unlinked, all rows have already been
    /// deleted and the file contains no user data.
    public func deleteAll() async throws {
        var databaseError: StylePersistenceError?
        if container != nil {
            do {
                try withContext { context in
                    try deleteAllRows(in: context)
                    try context.save()
                }
            } catch let error as StylePersistenceError {
                databaseError = error
            } catch {
                databaseError = .storeUnavailable
            }
        }
        container = nil

        var fileError: StylePersistenceError?
        let directories = [
            paths.profilesDirectory,
            paths.thumbnailsDirectory,
            paths.migrationBackupsDirectory,
            paths.profileRecoveryDirectory,
            paths.indexRecoveryDirectory
        ]
        for directory in directories {
            do {
                try fileSystem.removeIfExists(directory)
            } catch {
                fileError = fileError ?? .ioFailed
            }
        }

        let indexRemoved = removeIndexFiles()
        if let fileError {
            throw fileError
        }
        if let databaseError, !indexRemoved {
            throw databaseError
        }

        logger.log(.info, "Deleted all local persistence data", metadata: [:])
    }

    // MARK: - Active profile metadata

    /// Metadata for the active profile. Triggers the same recovery/migration as
    /// ``loadActive()`` so the result is never based on a stale index alone.
    public func activeProfileMetadata() async throws -> StyleProfileMetadata? {
        let profile = try await loadActive()
        guard profile != nil else {
            return nil
        }
        return try withContext { context -> StyleProfileMetadata? in
            let records = try context.fetch(FetchDescriptor<StyleProfileRecord>())
            guard let active = records
                .filter({ $0.isActive })
                .max(by: { $0.updatedAt < $1.updatedAt })
            else {
                return nil
            }
            return StyleProfileMetadata(
                id: active.id,
                schemaVersion: active.schemaVersion,
                algorithmVersion: active.algorithmVersion,
                pairCount: active.pairCount,
                confidence: active.confidence,
                tags: active.tagKeys,
                createdAt: active.createdAt,
                updatedAt: active.updatedAt
            )
        }
    }

    /// Stable identity of the active profile, if any.
    public func activeProfileID() async throws -> UUID? {
        let metadata = try await activeProfileMetadata()
        return metadata?.id
    }

    /// Moves the active profile JSON into `style-profile-recovery/` and clears
    /// its active flag. Used after presenting a corruption/schema error so the
    /// user can recalibrate without losing the rest of their local data.
    ///
    /// - Returns: `true` when an active profile row was found.
    @discardableResult
    public func quarantineActiveProfile() async throws -> Bool {
        let fileName = try withContext { context -> String? in
            let records = try context.fetch(FetchDescriptor<StyleProfileRecord>())
            let active = records
                .filter { $0.isActive }
                .max { $0.updatedAt < $1.updatedAt }
            return active?.fileName
        }
        guard let fileName else {
            return false
        }

        let source = paths.profilesDirectory.appendingPathComponent(fileName)
        if fileSystem.exists(source) {
            try ensureDirectory(paths.profileRecoveryDirectory)
            let timestamp = Int64(dateProvider.now.timeIntervalSince1970 * 1_000)
            let suffix = UUID().uuidString.prefix(8)
            let base = source.deletingPathExtension().lastPathComponent
            let destination = paths.profileRecoveryDirectory
                .appendingPathComponent("\(base)-\(timestamp)-\(suffix).json")
            do {
                try fileSystem.move(source, to: destination)
            } catch {
                throw StylePersistenceError.ioFailed
            }
        }

        try deactivateAllProfiles()
        logger.log(.info, "Quarantined the active style profile", metadata: [:])
        return true
    }

    // MARK: - Index

    func withContext<T>(_ operation: (ModelContext) throws -> T) throws -> T {
        do {
            return try operation(ModelContext(try indexContainer()))
        } catch let error as StylePersistenceError {
            throw error
        } catch {
            logger.log(.warning, "Local style index failed; quarantining and rebuilding it", metadata: [:])
            guard let recovered = try? recoverIndex() else {
                throw StylePersistenceError.storeUnavailable
            }
            do {
                return try operation(ModelContext(recovered))
            } catch let error as StylePersistenceError {
                throw error
            } catch {
                throw StylePersistenceError.storeUnavailable
            }
        }
    }

    private func indexContainer() throws -> ModelContainer {
        if let container {
            return container
        }
        try ensureDirectory(paths.baseDirectory)

        do {
            let created = try makeContainer()
            container = created
            protectIndexFiles()
            return created
        } catch {
            logger.log(.warning, "Local style index could not be opened; rebuilding it", metadata: [:])
            guard try quarantineIndexFiles() else {
                throw StylePersistenceError.storeUnavailable
            }
            do {
                let recovered = try makeContainer()
                container = recovered
                protectIndexFiles()
                return recovered
            } catch {
                throw StylePersistenceError.storeUnavailable
            }
        }
    }

    private func recoverIndex() throws -> ModelContainer {
        container = nil
        guard try quarantineIndexFiles() else {
            throw StylePersistenceError.storeUnavailable
        }
        let recovered = try makeContainer()
        container = recovered
        protectIndexFiles()
        return recovered
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            StyleProfileRecord.self,
            EditRecord.self,
            PairSessionRecord.self,
            QuotaRecord.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: paths.indexStoreURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: StyleProfileRecord.self,
            EditRecord.self,
            PairSessionRecord.self,
            QuotaRecord.self,
            configurations: modelConfiguration
        )
    }

    /// Moves every `style-index.store*` file aside. Returns `false` when the
    /// index was never created (nothing to recover from).
    private func quarantineIndexFiles() throws -> Bool {
        let files: [URL]
        do {
            files = try fileSystem.files(in: paths.baseDirectory)
        } catch {
            throw StylePersistenceError.ioFailed
        }
        let candidates = files.filter {
            $0.lastPathComponent.hasPrefix(PersistencePaths.indexStoreName)
        }
        guard !candidates.isEmpty else {
            return false
        }

        try ensureDirectory(paths.indexRecoveryDirectory)
        let timestamp = Int64(dateProvider.now.timeIntervalSince1970 * 1_000)
        let suffix = UUID().uuidString.prefix(8)
        let destination = paths.indexRecoveryDirectory
            .appendingPathComponent("index-\(timestamp)-\(suffix)", isDirectory: true)
        try ensureDirectory(destination)

        for file in candidates {
            do {
                try fileSystem.move(file, to: destination.appendingPathComponent(file.lastPathComponent))
            } catch {
                throw StylePersistenceError.ioFailed
            }
        }
        return true
    }

    private func removeIndexFiles() -> Bool {
        var removedAll = true
        if fileSystem.exists(paths.indexStoreURL) {
            do {
                try fileSystem.remove(paths.indexStoreURL)
            } catch {
                removedAll = false
            }
        }
        do {
            let files = try fileSystem.files(in: paths.baseDirectory)
            for file in files where file.lastPathComponent.hasPrefix(PersistencePaths.indexStoreName) {
                do {
                    try fileSystem.remove(file)
                } catch {
                    removedAll = false
                }
            }
            return removedAll
        } catch {
            return false
        }
    }

    func protectIndexFiles() {
        guard let files = try? fileSystem.files(in: paths.baseDirectory) else {
            return
        }
        for file in files where file.lastPathComponent.hasPrefix(PersistencePaths.indexStoreName) {
            try? fileSystem.setProtection(configuration.fileProtection, at: file)
        }
    }

    // MARK: - Profile loading and migration

    private func readProfile(at url: URL) throws -> StyleProfileDecodingResult {
        let data: Data
        do {
            data = try fileSystem.read(url)
        } catch {
            throw StylePersistenceError.ioFailed
        }

        let decoded: StyleProfileDecodingResult
        do {
            decoded = try StyleProfileJSONMigrator.decode(data, now: dateProvider.now)
        } catch let error as StylePersistenceError {
            throw error
        } catch {
            throw StylePersistenceError.profileCorrupt
        }

        if decoded.migrated {
            try rewriteMigratedProfile(
                originalData: data,
                decoded: decoded,
                at: url
            )
        }
        return decoded
    }

    private func rewriteMigratedProfile(
        originalData: Data,
        decoded: StyleProfileDecodingResult,
        at url: URL
    ) throws {
        let encoded: Data
        do {
            encoded = try StyleProfileJSONMigrator.encode(decoded.profile)
        } catch {
            throw StylePersistenceError.profileMigrationFailed(
                sourceVersion: decoded.sourceSchemaVersion
            )
        }

        try ensureDirectory(paths.migrationBackupsDirectory)
        let timestamp = Int64(dateProvider.now.timeIntervalSince1970 * 1_000)
        let suffix = UUID().uuidString.prefix(8)
        let base = url.deletingPathExtension().lastPathComponent
        let backupURL = paths.migrationBackupsDirectory.appendingPathComponent(
            "\(base)-v\(decoded.sourceSchemaVersion)-\(timestamp)-\(suffix).json"
        )

        do {
            try fileSystem.write(
                originalData,
                to: backupURL,
                protection: configuration.fileProtection
            )
            try fileSystem.write(
                encoded,
                to: url,
                protection: configuration.fileProtection
            )
        } catch {
            throw StylePersistenceError.ioFailed
        }

        logger.log(.info, "Migrated style profile document", metadata: [
            "from": "\(decoded.sourceSchemaVersion)",
            "to": "\(StyleProfile.currentSchemaVersion)"
        ])
    }

    private func rebuildActiveProfile() throws -> StyleProfile? {
        let allFiles: [URL]
        do {
            allFiles = try fileSystem.files(in: paths.profilesDirectory)
        } catch {
            throw StylePersistenceError.ioFailed
        }
        let files = allFiles.filter { $0.pathExtension.lowercased() == "json" }
        guard !files.isEmpty else {
            return nil
        }

        var best: (url: URL, decoded: StyleProfileDecodingResult)?
        var firstError: StylePersistenceError?
        for url in files {
            do {
                let decoded = try readProfile(at: url)
                if best == nil || decoded.profile.updatedAt > best!.decoded.profile.updatedAt {
                    best = (url, decoded)
                }
            } catch let error as StylePersistenceError {
                firstError = firstError ?? error
            } catch {
                firstError = firstError ?? .profileCorrupt
            }
        }

        guard let best else {
            if let firstError {
                throw firstError
            }
            return nil
        }

        try activate(
            profile: best.decoded.profile,
            fileName: best.url.lastPathComponent
        )
        return best.decoded.profile
    }

    private func activate(profile: StyleProfile, fileName: String) throws {
        let now = dateProvider.now
        try withContext { context in
            let records = try context.fetch(FetchDescriptor<StyleProfileRecord>())
            let existingByFile = records.first { $0.fileName == fileName }
            let fileBase = URL(fileURLWithPath: fileName)
                .deletingPathExtension()
                .lastPathComponent
            let id = existingByFile?.id ?? UUID(uuidString: fileBase) ?? UUID()
            let existing = records.first { $0.id == id } ?? existingByFile

            for record in records where record.id != id {
                record.isActive = false
            }

            let record: StyleProfileRecord
            if let existing {
                record = existing
            } else {
                record = StyleProfileRecord(
                    id: id,
                    fileName: fileName,
                    pairCount: profile.pairCount,
                    confidence: profile.confidence,
                    tagKeys: profile.tags,
                    createdAt: now,
                    updatedAt: profile.updatedAt,
                    isActive: true
                )
                context.insert(record)
            }
            record.fileName = fileName
            apply(profile, to: record)
            record.isActive = true
            try context.save()
        }
        protectIndexFiles()
    }

    private func updateIndexAfterMigration(recordID: UUID, profile: StyleProfile) throws {
        try withContext { context in
            let records = try context.fetch(FetchDescriptor<StyleProfileRecord>())
            guard let record = records.first(where: { $0.id == recordID }) else {
                return
            }
            apply(profile, to: record)
            record.isActive = true
            try context.save()
        }
        protectIndexFiles()
    }

    private func deactivateAllProfiles() throws {
        try withContext { context in
            let records = try context.fetch(FetchDescriptor<StyleProfileRecord>())
            guard records.contains(where: { $0.isActive }) else {
                return
            }
            for record in records {
                record.isActive = false
            }
            try context.save()
        }
        protectIndexFiles()
    }

    // MARK: - Shared helpers

    func ensureDirectory(_ url: URL) throws {
        do {
            try fileSystem.createDirectory(at: url, protection: configuration.fileProtection)
            try? fileSystem.setProtection(configuration.fileProtection, at: url)
        } catch {
            throw StylePersistenceError.ioFailed
        }
    }
}

// MARK: - File-scoped helpers

private struct ActiveProfileDescriptor: Sendable {
    let id: UUID
    let fileName: String
}

private func activeRecord(in records: [StyleProfileRecord]) -> StyleProfileRecord? {
    records
        .filter { $0.isActive }
        .max { $0.updatedAt < $1.updatedAt }
}

private func apply(_ profile: StyleProfile, to record: StyleProfileRecord) {
    record.schemaVersion = profile.schemaVersion
    record.algorithmVersion = profile.algorithmVersion
    record.pairCount = profile.pairCount
    record.confidenceRawValue = profile.confidence.rawValue
    record.tagKeys = profile.tags
    record.updatedAt = profile.updatedAt
}

private func deleteAllRows(in context: ModelContext) throws {
    for record in try context.fetch(FetchDescriptor<StyleProfileRecord>()) {
        context.delete(record)
    }
    for record in try context.fetch(FetchDescriptor<EditRecord>()) {
        context.delete(record)
    }
    for record in try context.fetch(FetchDescriptor<PairSessionRecord>()) {
        context.delete(record)
    }
    for record in try context.fetch(FetchDescriptor<QuotaRecord>()) {
        context.delete(record)
    }
}
