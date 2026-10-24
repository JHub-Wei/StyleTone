import Foundation

public enum ExportFormat: String, Codable, Sendable, CaseIterable {
    case heic
    case jpeg
}

public struct ExportOptions: Sendable, Equatable {
    public var format: ExportFormat
    public var quality: Double
    public var stripLocation: Bool

    public init(
        format: ExportFormat = .heic,
        quality: Double = 0.92,
        stripLocation: Bool = true
    ) {
        self.format = format
        self.quality = min(max(quality, 0), 1)
        self.stripLocation = stripLocation
    }
}

public struct ExportResult: Sendable, Equatable {
    public let url: URL
    public let pixelSize: PixelSize
    public let format: ExportFormat

    public init(url: URL, pixelSize: PixelSize, format: ExportFormat) {
        self.url = url
        self.pixelSize = pixelSize
        self.format = format
    }
}
