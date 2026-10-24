import Foundation

/// Storage for the tiny calibration draft that enables cancel/resume.
///
/// This is intentionally not the app-wide `StyleProfileStore`: WP-08 remains
/// the owner of the active profile. The calibration draft contains only pair
/// identifiers, answers and the optional finished profile, never image data.
public protocol CalibrationProgressStoring: Sendable {
    func loadDraft() async throws -> CalibrationDraft?
    func saveDraft(_ draft: CalibrationDraft) async throws
    func clearDraft() async throws
}

public enum CalibrationProgressStoreError: Error, Sendable, Equatable {
    case unavailable
    case corrupted
}

/// A local JSON file store under Application Support.
///
/// No account, network or shared container is involved. All reads and writes
/// happen inside the actor, off the main thread. The caller may inject a
/// directory for tests or for a host that wants its own location.
public actor FileCalibrationProgressStore: CalibrationProgressStoring {
    private let directoryURL: URL?
    private let fileName: String

    public init(
        directoryURL: URL? = nil,
        fileName: String = "calibration-progress.json"
    ) {
        self.directoryURL = directoryURL
        self.fileName = fileName
    }

    public func loadDraft() async throws -> CalibrationDraft? {
        let url = try resolvedFileURL(createDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try Self.makeDecoder().decode(CalibrationDraft.self, from: data)
        } catch is DecodingError {
            throw CalibrationProgressStoreError.corrupted
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSFileReadNoSuchFileError
            {
                return nil
            }
            throw CalibrationProgressStoreError.unavailable
        }
    }

    public func saveDraft(_ draft: CalibrationDraft) async throws {
        let url = try resolvedFileURL(createDirectory: true)
        do {
            let data = try Self.makeEncoder().encode(draft)
            try data.write(to: url, options: .atomic)
        } catch {
            throw CalibrationProgressStoreError.unavailable
        }
    }

    public func clearDraft() async throws {
        let url = try resolvedFileURL(createDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSFileNoSuchFileError
            {
                return
            }
            throw CalibrationProgressStoreError.unavailable
        }
    }

    private func resolvedFileURL(createDirectory: Bool) throws -> URL {
        do {
            let directory: URL
            if let directoryURL {
                directory = directoryURL
            } else {
                let applicationSupport = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                directory = applicationSupport
                    .appendingPathComponent("StyleTone", isDirectory: true)
                    .appendingPathComponent("Calibration", isDirectory: true)
            }

            if createDirectory {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }
            return directory.appendingPathComponent(fileName, isDirectory: false)
        } catch {
            throw CalibrationProgressStoreError.unavailable
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// An in-memory store for tests, previews and hosts that persist pairs but not
/// calibration drafts.
public actor CalibrationInMemoryProgressStore: CalibrationProgressStoring {
    public private(set) var storedDraft: CalibrationDraft?
    public private(set) var saveCount = 0
    public private(set) var clearCount = 0

    private let loadError: CalibrationProgressStoreError?
    private let saveError: CalibrationProgressStoreError?
    private let clearError: CalibrationProgressStoreError?

    public init(
        draft: CalibrationDraft? = nil,
        loadError: CalibrationProgressStoreError? = nil,
        saveError: CalibrationProgressStoreError? = nil,
        clearError: CalibrationProgressStoreError? = nil
    ) {
        self.storedDraft = draft
        self.loadError = loadError
        self.saveError = saveError
        self.clearError = clearError
    }

    public func loadDraft() async throws -> CalibrationDraft? {
        if let loadError {
            throw loadError
        }
        return storedDraft
    }

    public func saveDraft(_ draft: CalibrationDraft) async throws {
        saveCount += 1
        if let saveError {
            throw saveError
        }
        if draft.revision >= (storedDraft?.revision ?? -1) {
            storedDraft = draft
        }
    }

    public func clearDraft() async throws {
        clearCount += 1
        if let clearError {
            throw clearError
        }
        storedDraft = nil
    }
}
