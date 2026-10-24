import Foundation
import StyleToneCore

/// A directory-backed store for golden PNG images.
///
/// Recording is explicit: set `recordMode` to `true` (or set
/// `GOLDEN_RECORD=1` in the environment) to overwrite goldens while iterating.
/// A recording run still returns a passing report so it cannot mask a failure,
/// but `recordMode` should never be enabled in CI.
public struct GoldenImageStore: Sendable {
    public let directory: URL
    public let recordMode: Bool

    public init(directory: URL, recordMode: Bool = GoldenImageStore.environmentRecordMode()) {
        self.directory = directory
        self.recordMode = recordMode
    }

    /// Default location for committed goldens: `Fixtures/golden`.
    public static func defaultDirectory(repositoryRoot: URL) -> URL {
        repositoryRoot.appendingPathComponent("Fixtures/golden", isDirectory: true)
    }

    /// Reads `GOLDEN_RECORD` (`1`, `true` or `yes`, case-insensitive).
    public static func environmentRecordMode() -> Bool {
        let value = ProcessInfo.processInfo.environment["GOLDEN_RECORD"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    /// Resolves the PNG URL for a golden name, rejecting path traversal.
    public func url(for name: String) throws -> URL {
        let sanitized = try Self.validatedName(name)
        return directory.appendingPathComponent(sanitized).appendingPathExtension("png")
    }

    /// Loads a golden as straight-alpha sRGB pixels.
    public func loadPixels(named name: String) throws -> PixelBuffer {
        let fileURL = try url(for: name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw GoldenSupportError.goldenImageMissing(name: name)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw GoldenSupportError.fileOperationFailed(reason: "golden image could not be read")
        }
        return try PixelBuffer(imageData: data)
    }

    /// Loads a golden as an `ImageAsset`.
    public func load(named name: String) throws -> ImageAsset {
        try loadPixels(named: name).makeImageAsset()
    }

    /// Writes a golden, creating the store directory when needed.
    public func save(_ pixels: PixelBuffer, named name: String) throws {
        let fileURL = try url(for: name)
        try Self.ensureDirectory(directory)
        do {
            try pixels.pngData().write(to: fileURL, options: .atomic)
        } catch let error as GoldenSupportError {
            throw error
        } catch {
            throw GoldenSupportError.fileOperationFailed(reason: "golden image could not be written")
        }
    }

    /// Writes a golden from an `ImageAsset`.
    public func save(_ image: ImageAsset, named name: String) throws {
        try save(PixelBuffer(image: image), named: name)
    }

    /// Compares against a stored golden. In record mode the golden is replaced
    /// and an identity report is returned.
    public func compare(
        _ actual: PixelBuffer,
        named name: String,
        thresholds: ImageThresholds = .standard
    ) throws -> ImageDifferenceReport {
        if recordMode {
            try save(actual, named: name)
            return try ImageComparator.compare(expected: actual, actual: actual, thresholds: thresholds)
        }
        let expected = try loadPixels(named: name)
        return try ImageComparator.compare(expected: expected, actual: actual, thresholds: thresholds)
    }

    /// Compares an `ImageAsset` against a stored golden.
    public func compare(
        _ actual: ImageAsset,
        named name: String,
        thresholds: ImageThresholds = .standard
    ) throws -> ImageDifferenceReport {
        try compare(PixelBuffer(image: actual), named: name, thresholds: thresholds)
    }

    static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(".."),
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.hasPrefix(".")
        else {
            throw GoldenSupportError.invalidGoldenName(name: name)
        }
        return trimmed
    }

    static func ensureDirectory(_ directory: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw GoldenSupportError.fileOperationFailed(reason: "artifact directory could not be created")
        }
    }
}

/// Files written for one failing comparison.
public struct DiffArtifacts: Sendable, Codable, Equatable {
    public let directory: URL
    public let expectedURL: URL
    public let actualURL: URL
    public let differenceURL: URL
    public let reportURL: URL
    public let markdownURL: URL

    public init(
        directory: URL,
        expectedURL: URL,
        actualURL: URL,
        differenceURL: URL,
        reportURL: URL,
        markdownURL: URL
    ) {
        self.directory = directory
        self.expectedURL = expectedURL
        self.actualURL = actualURL
        self.differenceURL = differenceURL
        self.reportURL = reportURL
        self.markdownURL = markdownURL
    }
}

/// Writes expected/actual/diff PNGs plus JSON and Markdown reports so a CI job
/// can upload the failing case as an artifact.
public enum DiffArtifactWriter {
    public static func write(
        expected: PixelBuffer,
        actual: PixelBuffer,
        report: ImageDifferenceReport,
        name: String,
        to directory: URL,
        amplification: Int = 8
    ) throws -> DiffArtifacts {
        let prefix = try GoldenImageStore.validatedName(name)
        try GoldenImageStore.ensureDirectory(directory)

        let expectedURL = directory.appendingPathComponent("\(prefix)-expected.png")
        let actualURL = directory.appendingPathComponent("\(prefix)-actual.png")
        let differenceURL = directory.appendingPathComponent("\(prefix)-difference.png")
        let reportURL = directory.appendingPathComponent("\(prefix)-report.json")
        let markdownURL = directory.appendingPathComponent("\(prefix)-report.md")

        let difference = try ImageComparator.differenceImage(
            expected: expected,
            actual: actual,
            amplification: amplification
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let reportData: Data
        do {
            reportData = try encoder.encode(report)
        } catch {
            throw GoldenSupportError.fileOperationFailed(reason: "comparison report could not be encoded")
        }

        do {
            try expected.pngData().write(to: expectedURL, options: .atomic)
            try actual.pngData().write(to: actualURL, options: .atomic)
            try difference.pngData().write(to: differenceURL, options: .atomic)
            try reportData.write(to: reportURL, options: .atomic)
            try Data(report.markdown().utf8).write(to: markdownURL, options: .atomic)
        } catch let error as GoldenSupportError {
            throw error
        } catch {
            throw GoldenSupportError.fileOperationFailed(reason: "diff artifact could not be written")
        }

        return DiffArtifacts(
            directory: directory,
            expectedURL: expectedURL,
            actualURL: actualURL,
            differenceURL: differenceURL,
            reportURL: reportURL,
            markdownURL: markdownURL
        )
    }
}
