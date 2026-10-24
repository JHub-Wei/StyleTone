import Foundation
import StyleToneCore

/// Image formats recognized by ``ImageLoader``.
public enum ImageFileFormat: String, Sendable, CaseIterable {
    case heic
    case jpeg
    case png

    /// Uniform Type Identifier understood by ImageIO.
    public var typeIdentifier: String {
        switch self {
        case .heic:
            return "public.heic"
        case .jpeg:
            return "public.jpeg"
        case .png:
            return "public.png"
        }
    }

    /// Conventional file extension without a leading dot.
    public var filenameExtension: String {
        switch self {
        case .heic:
            return "heic"
        case .jpeg:
            return "jpg"
        case .png:
            return "png"
        }
    }

    /// Maps an ImageIO type identifier to a supported import format.
    ///
    /// HEIF container variants are accepted as HEIC. Everything else returns
    /// `nil` so the loader can report `StyleToneError.unsupportedFormat`.
    public static func detect(_ typeIdentifier: String) -> ImageFileFormat? {
        switch typeIdentifier {
        case "public.heic", "public.heif", "public.heif-standard":
            return .heic
        case "public.jpeg":
            return .jpeg
        case "public.png":
            return .png
        default:
            return nil
        }
    }
}

public extension ExportFormat {
    /// Uniform Type Identifier used when writing this format.
    var typeIdentifier: String {
        switch self {
        case .heic:
            return "public.heic"
        case .jpeg:
            return "public.jpeg"
        }
    }

    /// Conventional file extension without a leading dot.
    var filenameExtension: String {
        switch self {
        case .heic:
            return "heic"
        case .jpeg:
            return "jpg"
        }
    }
}
