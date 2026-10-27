import Foundation
import StyleToneCore
import StyleToneUI

// MARK: - Date

/// Deterministic date provider for presenter history and log assertions.
struct EdgeCaseDateProvider: DateProviding, Sendable {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)

    let now: Date

    init(_ date: Date = EdgeCaseDateProvider.reference) {
        self.now = date
    }
}

// MARK: - Logger

/// Thread-safe recording logger for diagnostics assertions.
final class EdgeCaseRecordingLogger: AppLogging, @unchecked Sendable {
    struct Entry: Sendable, Equatable {
        let level: LogLevel
        let message: String
        let metadata: [String: String]
    }

    private let lock = NSLock()
    private var storage: [Entry] = []

    func log(_ level: LogLevel, _ message: String, metadata: [String: String]) {
        lock.lock()
        storage.append(Entry(level: level, message: message, metadata: metadata))
        lock.unlock()
    }

    var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var metadataValues: [String] {
        entries.flatMap { $0.metadata.values }
    }
}

// MARK: - Errors

/// An error whose localized description contains obvious PII.
///
/// The unified surface must never read or render this string.
struct EdgeCasePIIError: Error, LocalizedError {
    var errorDescription: String? {
        "/Users/alice/Photos/private-portrait.jpg — alice@example.com"
    }
}

/// An error with no useful diagnostic detail.
struct EdgeCaseOpaqueError: Error {}

// MARK: - Helpers

/// Reference-type recovery recorder, so escaping closures do not capture a
/// mutable local variable under strict concurrency.
@MainActor
final class EdgeCaseRecoverySpy {
    private(set) var received: [(RecoveryAction, ErrorState)] = []

    var count: Int {
        received.count
    }

    func record(_ action: RecoveryAction, _ state: ErrorState) {
        received.append((action, state))
    }
}

@MainActor
final class EdgeCaseCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

enum EdgeCaseFixtures {
    static let reference = EdgeCaseDateProvider.reference

    static func cocoaError(
        _ code: CocoaError.Code,
        path: String? = "/Users/alice/Photos/private-portrait.jpg"
    ) -> NSError {
        var userInfo: [String: Any] = [:]
        if let path {
            userInfo[NSFilePathErrorKey] = path
        }
        return NSError(
            domain: NSCocoaErrorDomain,
            code: code.rawValue,
            userInfo: userInfo
        )
    }

    static func containsPathLikeText(_ text: String) -> Bool {
        // `%@` is a localization placeholder, not an email address.
        let withoutPlaceholders = text.replacingOccurrences(of: "%@", with: "")
        return withoutPlaceholders.contains("/")
            || withoutPlaceholders.contains("\\")
            || withoutPlaceholders.contains(".jpg")
            || withoutPlaceholders.contains(".heic")
            || withoutPlaceholders.contains("@")
            || withoutPlaceholders.contains("Users")
    }
}
