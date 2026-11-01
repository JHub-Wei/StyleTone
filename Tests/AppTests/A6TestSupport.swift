import Foundation
import StyleToneCore
@testable import StyleTone

/// In-memory `StyleProfileStore` for flow tests. It never touches SwiftData or
/// the file system.
actor A6MockProfileStore: StyleProfileStore {
    private(set) var active: StyleProfile?
    private(set) var savedProfiles: [StyleProfile] = []
    private(set) var deleteAllCount = 0

    init(active: StyleProfile? = nil) {
        self.active = active
    }

    func loadActive() async throws -> StyleProfile? {
        active
    }

    func save(_ profile: StyleProfile) async throws {
        active = profile
        savedProfiles.append(profile)
    }

    func deleteAll() async throws {
        active = nil
        savedProfiles = []
        deleteAllCount += 1
    }
}
