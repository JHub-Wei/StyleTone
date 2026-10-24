import Foundation

/// File-protection class requested for every artifact this package writes.
///
/// The App target owns the platform entitlement; this package applies the
/// attribute per file (and per directory) on iOS-family platforms. macOS has no
/// per-file data-protection classes, so the local implementation is a no-op
/// there. Storing the requested level in the configuration keeps the policy
/// observable and testable on every platform.
public enum PersistenceFileProtection: String, Sendable, Equatable, CaseIterable {
    /// `NSFileProtectionComplete`: unreadable while the device is locked.
    case complete
    /// `NSFileProtectionCompleteUnlessOpen`.
    case completeUnlessOpen
    /// `NSFileProtectionCompleteUntilFirstUserAuthentication`.
    case completeUntilFirstUserAuthentication
    /// `NSFileProtectionNone` (tests/previews only).
    case none
}

/// Where the local store lives and how its files are protected.
///
/// The default base directory is `Application Support/StyleTone`. It is not
/// created by ``SwiftDataStyleProfileStore`` until the first operation, so
/// constructing the store on the main thread does not touch the file system.
public struct PersistenceConfiguration: Sendable, Equatable {
    public let baseDirectory: URL
    public let fileProtection: PersistenceFileProtection

    public init(
        baseDirectory: URL = PersistenceConfiguration.defaultBaseDirectory,
        fileProtection: PersistenceFileProtection = .complete
    ) {
        self.baseDirectory = baseDirectory
        self.fileProtection = fileProtection
    }

    /// `Application Support/StyleTone` in the current user domain.
    public static var defaultBaseDirectory: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("StyleTone", isDirectory: true)
    }
}

/// Known paths below the configured base directory.
///
/// The profile JSON layout is frozen by the shared persistence contract:
/// `style-profiles/{uuid}.json` and, when implemented, `style-thumbnails/`.
struct PersistencePaths: Sendable {
    static let indexStoreName = "style-index.store"

    let baseDirectory: URL

    var profilesDirectory: URL {
        baseDirectory.appendingPathComponent("style-profiles", isDirectory: true)
    }

    var thumbnailsDirectory: URL {
        baseDirectory.appendingPathComponent("style-thumbnails", isDirectory: true)
    }

    var migrationBackupsDirectory: URL {
        baseDirectory.appendingPathComponent("style-profile-migration-backups", isDirectory: true)
    }

    var profileRecoveryDirectory: URL {
        baseDirectory.appendingPathComponent("style-profile-recovery", isDirectory: true)
    }

    var indexRecoveryDirectory: URL {
        baseDirectory.appendingPathComponent("style-index-recovery", isDirectory: true)
    }

    var indexStoreURL: URL {
        baseDirectory.appendingPathComponent(Self.indexStoreName, isDirectory: false)
    }
}
