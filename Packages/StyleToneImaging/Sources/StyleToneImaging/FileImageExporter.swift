import Foundation
import StyleToneCore

/// File-based ``ImageExporting`` implementation.
///
/// Files are encoded into a dedicated temporary directory (never into the
/// photo library) and returned by URL. The caller is responsible for handing
/// the file to PhotoKit/share and for deleting it afterwards; use
/// ``removeExportedFile(at:)`` for that cleanup.
public struct FileImageExporter: ImageExporting, Sendable {
    /// Directory name used below the system temporary directory.
    public static let defaultDirectoryName = "StyleToneExports"

    /// Directory that receives exported files.
    public let directory: URL

    private let colorSpace: ImageColorSpace
    private let writer: ImageWriter

    /// Creates an exporter.
    ///
    /// - Parameters:
    ///   - directory: Destination directory. Defaults to
    ///     `<tmp>/StyleToneExports`, created on first export.
    ///   - colorSpace: Working space for the encoded file. Defaults to sRGB.
    ///   - writer: Low-level encoder.
    public init(
        directory: URL? = nil,
        colorSpace: ImageColorSpace = .sRGB,
        writer: ImageWriter = ImageWriter()
    ) {
        self.directory = directory
            ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.defaultDirectoryName, isDirectory: true)
        self.colorSpace = colorSpace
        self.writer = writer
    }

    /// Encodes `output` to a new unique file and returns its URL.
    ///
    /// - Throws: `StyleToneError.exportFailed` on encoding or file-system
    ///   failure, `CancellationError` when the task is cancelled.
    public func export(
        _ output: ImageAsset,
        options: ExportOptions
    ) async throws -> ExportResult {
        try Task.checkCancellation()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw StyleToneError.exportFailed
        }

        let url = directory.appendingPathComponent(Self.fileName(for: options.format))
        let result = try writer.write(
            output,
            to: url,
            options: ImageWriteOptions(
                format: options.format,
                quality: options.quality,
                colorSpace: colorSpace
            )
        )

        if Task.isCancelled {
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        return result
    }

    /// Deletes a file previously produced by this exporter.
    ///
    /// Missing files are ignored so cleanup can be retried safely.
    public func removeExportedFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw StyleToneError.exportFailed
        }
    }

    private static func fileName(for format: ExportFormat) -> String {
        "styletone-\(UUID().uuidString).\(format.filenameExtension)"
    }
}
