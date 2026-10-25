import Foundation
import ImageIO
import StyleToneCore
import StyleToneImaging

/// Metadata read from an encoded export file.
struct ExportEncodedImageInfo: Sendable, Equatable {
    let pixelSize: PixelSize
    let format: ExportFormat
}

/// Owns the temporary directory that holds encoded export files.
///
/// `FileImageExporter` (WP-02) writes into `<tmp>/StyleToneExports` by default;
/// this store uses the same public constant and refuses to delete anything
/// outside its directory. Normal paths remove the file immediately after the
/// save/share completes; `removeStaleFiles` only handles files left behind by a
/// crash or a kill while suspended.
public struct ExportTemporaryFileStore: Sendable {
    /// Directory name shared with `FileImageExporter.defaultDirectoryName`.
    public static let directoryName = FileImageExporter.defaultDirectoryName

    public let directory: URL
    public let staleAfter: TimeInterval

    public init(
        directory: URL = ExportTemporaryFileStore.defaultDirectory,
        staleAfter: TimeInterval = ExportAcceptance.staleTemporaryFileAge
    ) {
        self.directory = directory.standardizedFileURL
        self.staleAfter = staleAfter.isFinite ? max(0, staleAfter) : 0
    }

    /// `<tmp>/StyleToneExports`.
    public static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Creates the export directory and, on iOS, marks it complete-protected so
    /// files written by WP-02 inherit the protection class.
    public func prepareDirectoryForExport() {
        #if os(iOS)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directory.path
        )
        #else
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        #endif
    }

    /// Whether `url` is a direct child of the store's directory.
    public func contains(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == directory
    }

    public func fileExists(at url: URL) -> Bool {
        contains(url) && FileManager.default.fileExists(atPath: url.path)
    }

    /// Deletes one export file. Missing files count as success so cleanup can
    /// be retried; URLs outside the directory are never touched.
    @discardableResult
    public func remove(_ url: URL) -> Bool {
        guard contains(url) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    /// Size in bytes, or `0` when the file is missing/outside the directory.
    public func byteCount(of url: URL) -> Int {
        guard fileExists(at: url),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.intValue
    }

    /// Reads the actual pixel size and container format from the encoded file.
    ///
    /// `ExportResult.pixelSize`/`format` come from the exporter; a buggy
    /// exporter could report a full-resolution file while writing a proxy. The
    /// export flow compares these ImageIO-derived values (metadata only, no
    /// pixel decode) with the requested output before counting or saving.
    func encodedImageInfo(of url: URL) -> ExportEncodedImageInfo? {
        guard fileExists(at: url) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            options as CFDictionary
        ),
            let type = CGImageSourceGetType(source),
            let format = Self.exportFormat(forTypeIdentifier: type as String),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0,
            height > 0
        else {
            return nil
        }
        return ExportEncodedImageInfo(
            pixelSize: PixelSize(width: width, height: height),
            format: format
        )
    }

    /// Best-effort `NSFileProtectionComplete` for a staged export on iOS.
    ///
    /// The directory is protected before encoding; this second pass protects a
    /// file if it was created by an exporter that ignored the directory class.
    /// The file is short-lived and deleted after the save/share, so a failure to
    /// set the attribute does not block the export.
    #if os(iOS)
    public func applyFileProtection(to url: URL) {
        guard contains(url) else { return }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }
    #else
    public func applyFileProtection(to url: URL) {}
    #endif

    /// Deletes regular files older than `staleAfter`.
    ///
    /// - Returns: Number of files removed.
    /// - Note: A missing directory is not an error; exports may not have run yet.
    @discardableResult
    public func removeStaleFiles(now: Date = Date()) -> Int {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return 0
        }

        var removed = 0
        for url in urls where contains(url) {
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ) else {
                continue
            }
            guard values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else {
                continue
            }
            let age = now.timeIntervalSince(modified)
            guard age >= staleAfter else { continue }
            if remove(url) {
                removed += 1
            }
        }
        return removed
    }

    // MARK: - Private

    private static func exportFormat(forTypeIdentifier typeIdentifier: String) -> ExportFormat? {
        switch typeIdentifier {
        case "public.heic", "public.heif", "public.heif-standard":
            return .heic
        case "public.jpeg":
            return .jpeg
        default:
            return nil
        }
    }
}
