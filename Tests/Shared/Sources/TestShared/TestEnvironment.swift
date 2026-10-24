import Foundation
import GoldenSupport

/// Locates the checked-out repository so tests can read committed fixtures and
/// manifests without bundling them into the test target.
///
/// Resolution order:
/// 1. `ST_REPO_ROOT` environment override.
/// 2. Walk up from this source file until a directory containing both
///    `Package.swift` and `Fixtures` is found.
///
/// Tests that need the repository should `XCTSkip` when
/// ``repositoryRoot`` is `nil` (for example when a test bundle is copied to
/// another machine) instead of failing.
public struct TestEnvironment: Sendable {
    public static let repositoryRootEnvironmentKey = "ST_REPO_ROOT"

    public let repositoryRoot: URL?
    public let isCI: Bool

    public init(
        repositoryRoot: URL? = TestEnvironment.locateRepositoryRoot(),
        isCI: Bool = TestEnvironment.detectCI()
    ) {
        self.repositoryRoot = repositoryRoot
        self.isCI = isCI
    }

    public var fixturesDirectory: URL? {
        repositoryRoot?.appendingPathComponent("Fixtures", isDirectory: true)
    }

    public var referenceDirectory: URL? {
        fixturesDirectory?.appendingPathComponent("reference", isDirectory: true)
    }

    public var samplesDirectory: URL? {
        fixturesDirectory?.appendingPathComponent("samples", isDirectory: true)
    }

    public var fixtureManifestURL: URL? {
        fixturesDirectory?.appendingPathComponent("manifest.json")
    }

    public var samplesManifestURL: URL? {
        samplesDirectory?.appendingPathComponent("manifest.json")
    }

    public func requireRepositoryRoot() throws -> URL {
        guard let repositoryRoot else {
            throw GoldenSupportError.invalidConfiguration(
                reason: "repository root not found; set ST_REPO_ROOT"
            )
        }
        return repositoryRoot
    }

    public func requireFixtureManifestURL() throws -> URL {
        guard let url = fixtureManifestURL else {
            throw GoldenSupportError.invalidConfiguration(
                reason: "Fixtures/manifest.json not found; set ST_REPO_ROOT"
            )
        }
        return url
    }

    public func requireSamplesManifestURL() throws -> URL {
        guard let url = samplesManifestURL else {
            throw GoldenSupportError.invalidConfiguration(
                reason: "Fixtures/samples/manifest.json not found; set ST_REPO_ROOT"
            )
        }
        return url
    }

    /// Resolves a path below `Fixtures`, rejecting traversal and absolute paths.
    public func fixtureURL(relativePath: String) throws -> URL {
        let fixtures = try requireFixturesDirectory()
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.contains(".."),
              !trimmed.contains("\\")
        else {
            throw GoldenSupportError.invalidConfiguration(reason: "unsafe fixture path")
        }
        return fixtures.appendingPathComponent(trimmed)
    }

    public func requireFixturesDirectory() throws -> URL {
        guard let fixturesDirectory else {
            throw GoldenSupportError.invalidConfiguration(
                reason: "Fixtures directory not found; set ST_REPO_ROOT"
            )
        }
        return fixturesDirectory
    }

    public static func locateRepositoryRoot(startingAt path: String = #filePath) -> URL? {
        if let override = ProcessInfo.processInfo.environment[repositoryRootEnvironmentKey],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        var candidate = URL(fileURLWithPath: path).deletingLastPathComponent()
        let fileManager = FileManager.default
        for _ in 0..<12 {
            let hasPackage = fileManager.fileExists(
                atPath: candidate.appendingPathComponent("Package.swift").path
            )
            let hasFixtures = fileManager.fileExists(
                atPath: candidate.appendingPathComponent("Fixtures").path
            )
            if hasPackage, hasFixtures {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
        return nil
    }

    /// True when running under GitHub Actions or another CI provider.
    public static func detectCI() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["GITHUB_ACTIONS"] == "true" {
            return true
        }
        return environment["CI"] == "true" || environment["CI"] == "1"
    }
}
