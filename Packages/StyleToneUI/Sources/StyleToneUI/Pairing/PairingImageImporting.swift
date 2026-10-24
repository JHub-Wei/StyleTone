import Foundation
import ImageIO
import StyleToneCore
import StyleToneImaging

// MARK: - Errors

/// A photo could not be turned into a pairing image.
public enum PairingImportError: Error, Sendable, Equatable {
    /// The picker handed back an empty payload.
    case noImageData
    /// The payload is not a readable image (truncated, corrupt, wrong type).
    case unreadableData
    /// The image is a valid format the app does not accept (GIF, TIFF, ...).
    case unsupportedFormat
    /// The source long edge is below the accepted minimum.
    case imageTooSmall(minimumLongEdge: Int)
    /// ImageIO could not decode the payload.
    case decodingFailed
    /// An unexpected failure.
    case unknown

    public init(styleToneError: StyleToneError) {
        switch styleToneError {
        case .unsupportedFormat:
            self = .unsupportedFormat
        case let .imageTooSmall(minimumLongEdge):
            self = .imageTooSmall(minimumLongEdge: minimumLongEdge)
        case .imageDecodingFailed:
            self = .decodingFailed
        case .invalidImage:
            self = .unreadableData
        default:
            self = .unknown
        }
    }

    /// Selecting a different photo is the only meaningful recovery.
    public var requiresAnotherPhoto: Bool {
        switch self {
        case .noImageData, .unreadableData, .unsupportedFormat, .imageTooSmall, .decodingFailed:
            return true
        case .unknown:
            return false
        }
    }
}

// MARK: - Configuration

/// Bounds for the in-memory pairing proxy.
///
/// Pairing cards never need print resolution, and keeping every pick small is
/// what lets twelve pairs stay inside the 300 MB preview budget. The quality
/// analyzer receives the same proxy, so it measures the pixels the user sees.
public struct PairingImportConfiguration: Sendable, Equatable {
    /// Longest edge of the decoded proxy. Sources below it keep native size.
    public var maximumLongEdge: Int
    /// Smallest accepted long edge of the source photo.
    public var minimumLongEdge: Int
    /// Optional forced target color space; `nil` keeps sRGB/P3 sources.
    public var targetColorSpace: ImageColorSpace?

    public init(
        maximumLongEdge: Int = 1600,
        minimumLongEdge: Int = 512,
        targetColorSpace: ImageColorSpace? = nil
    ) {
        self.maximumLongEdge = max(64, maximumLongEdge)
        self.minimumLongEdge = max(1, minimumLongEdge)
        self.targetColorSpace = targetColorSpace
    }

    /// The configuration used by the pairing screen.
    public static let pairingPreview = PairingImportConfiguration()
}

// MARK: - Protocol

/// Turns picker payloads into pairing photos.
public protocol PairingImageImporting: Sendable {
    func importImage(
        from data: Data,
        sourceIdentifier: String?,
        importedAt: Date
    ) async throws -> PairingPhoto
}

// MARK: - Default importer

/// Decodes a picker payload into a bounded, oriented `ImageAsset`.
///
/// Decoding runs off the main thread through `ImageLoader`; the only extra work
/// here is reading the source pixel size from ImageIO so the card can show
/// "4032 × 3024" even though the memory copy is smaller.
public struct PairingImageImporter: PairingImageImporting {
    public let configuration: PairingImportConfiguration

    private let loader: ImageLoader

    public init(
        configuration: PairingImportConfiguration = .pairingPreview,
        loader: ImageLoader = ImageLoader()
    ) {
        self.configuration = configuration
        self.loader = loader
    }

    public func importImage(
        from data: Data,
        sourceIdentifier: String?,
        importedAt: Date
    ) async throws -> PairingPhoto {
        guard !data.isEmpty else {
            throw PairingImportError.noImageData
        }

        let sourceSize = Self.sourcePixelSize(of: data)
        let options = ImageLoadOptions(
            maximumLongEdge: configuration.maximumLongEdge,
            minimumLongEdge: configuration.minimumLongEdge,
            targetColorSpace: configuration.targetColorSpace
        )

        do {
            let asset = try await loader.load(data: data, options: options)
            return PairingPhoto(
                asset: asset,
                sourcePixelSize: sourceSize ?? asset.pixelSize,
                sourceIdentifier: sourceIdentifier,
                byteCount: data.count,
                importedAt: importedAt
            )
        } catch let error as StyleToneError {
            throw PairingImportError(styleToneError: error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PairingImportError.unknown
        }
    }

    /// Oriented pixel size of the encoded source, read without decoding.
    static func sourcePixelSize(of data: Data) -> PixelSize? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0
        else {
            return nil
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsDimensions = (5...8).contains(orientation)
        return PixelSize(
            width: swapsDimensions ? height : width,
            height: swapsDimensions ? width : height
        )
    }
}
