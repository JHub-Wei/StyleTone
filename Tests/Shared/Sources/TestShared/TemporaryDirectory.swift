import Foundation
import GoldenSupport

/// A unique temporary directory that removes itself on `deinit` and on
/// ``remove()``.
///
/// Prefer ``withTemporaryDirectory(_:)`` so cleanup also happens when the body
/// throws.
public final class TemporaryDirectory: @unchecked Sendable {
    public let url: URL

    public init(prefix: String = "StyleToneTests") throws {
        let sanitizedPrefix = prefix.isEmpty ? "StyleToneTests" : prefix
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "\(sanitizedPrefix)-\(UUID().uuidString)",
                isDirectory: true
            )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw GoldenSupportError.fileOperationFailed(
                reason: "temporary directory could not be created"
            )
        }
        self.url = directory
    }

    deinit {
        remove()
    }

    /// Removes the directory; safe to call more than once.
    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates a fresh directory, runs `body`, then removes the directory.
    public static func withTemporaryDirectory<T>(
        prefix: String = "StyleToneTests",
        _ body: (URL) throws -> T
    ) throws -> T {
        let directory = try TemporaryDirectory(prefix: prefix)
        defer { directory.remove() }
        return try body(directory.url)
    }

    /// Async variant of ``withTemporaryDirectory(_:)``.
    public static func withTemporaryDirectoryAsync<T>(
        prefix: String = "StyleToneTests",
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let directory = try TemporaryDirectory(prefix: prefix)
        defer { directory.remove() }
        return try await body(directory.url)
    }
}
