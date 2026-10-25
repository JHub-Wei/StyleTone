import Foundation
import StyleToneCore

// MARK: - Destination / stage

/// Where a finished export goes.
///
/// Saving to the photo library and handing the file to the system share sheet
/// are two separate operations: either one has its own permission and failure
/// semantics, and each successful operation is counted by `ExportQuotaServicing`.
public enum ExportDestination: String, Sendable, CaseIterable, Hashable {
    case photoLibrary
    case share
}

/// Progress stages of one export.
///
/// The renderer and encoder do not expose byte-level progress yet, so the
/// export flow reports the stage it is in plus a monotonic fraction. The UI
/// shows both; it never animates a fake completion.
public enum ExportStage: String, Sendable, CaseIterable, Hashable {
    case idle
    case preparing
    case requestingAccess
    case rendering
    case encoding
    case savingToLibrary
    case awaitingShare
    case finished
    case failed
    case cancelled

    /// Work is in flight and a second export must not start.
    public var isBusy: Bool {
        switch self {
        case .preparing, .requestingAccess, .rendering, .encoding,
             .savingToLibrary, .awaitingShare:
            return true
        case .idle, .finished, .failed, .cancelled:
            return false
        }
    }

    /// The stage reports a final state.
    public var isTerminal: Bool {
        switch self {
        case .finished, .failed, .cancelled:
            return true
        case .idle, .preparing, .requestingAccess, .rendering, .encoding,
             .savingToLibrary, .awaitingShare:
            return false
        }
    }
}

// MARK: - Progress

/// Stage plus a clamped completion fraction in `0...1`.
public struct ExportProgress: Sendable, Equatable {
    public let stage: ExportStage
    public let fraction: Double

    public init(stage: ExportStage, fraction: Double) {
        self.stage = stage
        self.fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0
    }

    public var percent: Int {
        Int((fraction * 100).rounded())
    }
}

// MARK: - Settings

/// One selectable JPEG/HEIC quality preset.
///
/// The presets keep the UI to three choices; `value` is the compression
/// quality written into `ExportOptions`, clamped to `0...1`.
public struct ExportQuality: Sendable, Hashable, Identifiable {
    public let id: String
    public let value: Double

    public init(id: String, value: Double) {
        self.id = id
        self.value = value.isFinite ? min(max(value, 0), 1) : 0.92
    }

    public static let standard = ExportQuality(id: "standard", value: 0.85)
    public static let high = ExportQuality(id: "high", value: 0.92)
    public static let maximum = ExportQuality(id: "maximum", value: 1.0)

    /// The presets offered by the export screen, best default first.
    public static let all: [ExportQuality] = [.high, .standard, .maximum]
}

/// User-visible export choices.
///
/// `stripLocation` defaults to `true` and the MVP screen deliberately does not
/// expose a switch: every export drops location metadata. The property stays
/// visible so a future opt-in can be reviewed without changing the pipeline.
/// WP-02's current writer always encodes a bare `CGImage`, so setting this to
/// `false` does not restore GPS either; the flag is a forward-compatible hint.
public struct ExportSettings: Sendable, Equatable {
    public var format: ExportFormat
    public var quality: ExportQuality
    public var stripLocation: Bool

    public init(
        format: ExportFormat = .heic,
        quality: ExportQuality = .high,
        stripLocation: Bool = true
    ) {
        self.format = format
        self.quality = quality
        self.stripLocation = stripLocation
    }

    /// The frozen core options handed to `ImageExporting`.
    public var options: ExportOptions {
        ExportOptions(
            format: format,
            quality: quality.value,
            stripLocation: stripLocation
        )
    }

    /// File extension without the leading dot.
    public var filenameExtension: String {
        format == .heic ? "heic" : "jpg"
    }
}

// MARK: - Source

/// Everything needed to render the full-resolution result.
///
/// `request.image` must be the full-resolution `ImageAsset` (WP-17 receives it
/// from the editor); `preview` is an optional smaller image used only by the
/// export screen. Mixing them up would silently export a proxy, so the flow
/// compares the rendered pixel size with `expectedPixelSize` and fails instead
/// of writing a low-resolution file.
public struct ExportSource: Sendable {
    public let request: RenderRequest
    public let preview: ImageAsset?
    public let expectedPixelSize: PixelSize

    public init(
        request: RenderRequest,
        preview: ImageAsset? = nil,
        expectedPixelSize: PixelSize? = nil
    ) {
        self.request = request
        self.preview = preview
        self.expectedPixelSize = expectedPixelSize ?? request.image.pixelSize
    }

    /// Number of pixels as a `Double`; avoids integer overflow for absurd sizes.
    public var pixelCount: Double {
        Double(expectedPixelSize.width) * Double(expectedPixelSize.height)
    }

    public var megapixels: Double {
        pixelCount / 1_000_000
    }

    /// Images at or above this size get a "may take longer" note.
    ///
    /// 24MP is a deliberately conservative threshold: it warns before the
    /// 48MP class NFR-04 calls out, and never blocks the export.
    public var isLargeImage: Bool {
        pixelCount >= Double(ExportAcceptance.largeImagePixelCount)
    }

    public var previewImage: ImageAsset {
        preview ?? request.image
    }

    /// Width / height, or `0` when the height is unusable.
    public var aspectRatio: Double {
        expectedPixelSize.aspectRatio
    }
}

// MARK: - Staged file

/// A file produced by `ImageExporting` and not yet handed off.
///
/// The URL stays inside the export temporary directory. It is deleted after a
/// successful save/share, after a failed or cancelled attempt that does not
/// keep it for "share instead", and by the stale-file sweeper after a crash.
public struct ExportStagedFile: Sendable, Equatable {
    public let url: URL
    public let format: ExportFormat
    public let pixelSize: PixelSize
    public let byteCount: Int
    public let createdAt: Date

    public init(
        url: URL,
        format: ExportFormat,
        pixelSize: PixelSize,
        byteCount: Int,
        createdAt: Date
    ) {
        self.url = url
        self.format = format
        self.pixelSize = pixelSize
        self.byteCount = max(0, byteCount)
        self.createdAt = createdAt
    }

    public var filenameExtension: String {
        format == .heic ? "heic" : "jpg"
    }
}

/// Identifiable payload for the system share sheet.
public struct ExportShareRequest: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let file: ExportStagedFile

    public init(id: UUID = UUID(), file: ExportStagedFile) {
        self.id = id
        self.file = file
    }

    public var url: URL {
        file.url
    }
}

// MARK: - Results

/// What the user got, without retaining pixels or file paths.
public struct ExportOutcome: Sendable, Equatable {
    public let destination: ExportDestination
    public let format: ExportFormat
    public let pixelSize: PixelSize
    public let byteCount: Int
    public let duration: TimeInterval
    /// False only when the photo was delivered but the quota write failed.
    public let counted: Bool
    public let completedAt: Date

    public init(
        destination: ExportDestination,
        format: ExportFormat,
        pixelSize: PixelSize,
        byteCount: Int,
        duration: TimeInterval,
        counted: Bool,
        completedAt: Date
    ) {
        self.destination = destination
        self.format = format
        self.pixelSize = pixelSize
        self.byteCount = max(0, byteCount)
        self.duration = max(0, duration)
        self.counted = counted
        self.completedAt = completedAt
    }
}

/// Stage durations of the last attempt. Used by diagnostics and CI checks.
public struct ExportTimings: Sendable, Equatable {
    public let render: TimeInterval
    public let encode: TimeInterval
    public let save: TimeInterval
    public let total: TimeInterval

    public init(
        render: TimeInterval,
        encode: TimeInterval,
        save: TimeInterval,
        total: TimeInterval
    ) {
        self.render = max(0, render)
        self.encode = max(0, encode)
        self.save = max(0, save)
        self.total = max(0, total)
    }

    public static let zero = ExportTimings(render: 0, encode: 0, save: 0, total: 0)
}

// MARK: - Acceptance constants

/// Numbers from contracts §10 and the WP-19 card, kept next to the code so the
/// UI and tests cannot drift silently.
public enum ExportAcceptance {
    /// 12MP export p95 budget (contracts §10).
    public static let twelveMegapixelBudget: TimeInterval = 6

    /// 48MP class exports are allowed but warned about; NFR-04 allows 20s.
    public static let largeImageBudget: TimeInterval = 20
    public static let largeImagePixelCount = 24_000_000

    /// A temporary export file older than this is considered abandoned.
    ///
    /// Normal success/failure/cancel/close paths delete immediately; this only
    /// covers a crash or a kill while the app is suspended.
    public static let staleTemporaryFileAge: TimeInterval = 10 * 60
}

// MARK: - Pipeline errors

/// Internal export failures that must not leak file paths into user copy.
public enum ExportPipelineError: Error, Sendable, Equatable {
    /// The exporter reported success but no file exists at the URL.
    case missingOutput
    /// The renderer returned a proxy-sized image instead of the full image.
    case resolutionMismatch(expected: PixelSize, actual: PixelSize)
    /// The encoded file's reported size differs from the rendered size.
    case exportSizeMismatch(expected: PixelSize, actual: PixelSize)
    /// The exporter ignored the requested format.
    case formatMismatch(expected: ExportFormat, actual: ExportFormat)

    public var code: String {
        switch self {
        case .missingOutput: return "E_EXPORT_OUTPUT"
        case .resolutionMismatch: return "E_EXPORT_RESOLUTION"
        case .exportSizeMismatch: return "E_EXPORT_SIZE"
        case .formatMismatch: return "E_EXPORT_FORMAT"
        }
    }
}
