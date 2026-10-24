import Foundation

/// An opaque 8-bit sRGB colour used by the synthetic fixtures and the image
/// comparison tools.
///
/// The type deliberately carries no alpha channel: fixtures are opaque, and
/// alpha handling belongs to `PixelBuffer` / `RGBA8`.
public struct RGB8: Sendable, Hashable, Codable, CustomStringConvertible {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// A neutral grey with the same value in every channel.
    public init(gray: UInt8) {
        self.init(red: gray, green: gray, blue: gray)
    }

    /// Parses `#RRGGBB` or `RRGGBB` (case-insensitive).
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            return nil
        }
        self.init(
            red: UInt8((value >> 16) & 0xFF),
            green: UInt8((value >> 8) & 0xFF),
            blue: UInt8(value & 0xFF)
        )
    }

    /// Uppercase `#RRGGBB`, the canonical manifest representation.
    public var hex: String {
        String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue))
    }

    public var description: String { hex }

    /// Rec. 709 luma on 8-bit sRGB values, in `0...255`.
    ///
    /// SSIM is computed on this value; it is *not* linear light.
    public var luma: Double {
        0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
    }

    /// WCAG relative luminance (linear light), in `0...1`.
    public var relativeLuminance: Double {
        0.2126 * ColorScience.srgbToLinear(Double(red) / 255.0)
            + 0.7152 * ColorScience.srgbToLinear(Double(green) / 255.0)
            + 0.0722 * ColorScience.srgbToLinear(Double(blue) / 255.0)
    }

    /// WCAG contrast ratio against another colour, in `1...21`.
    public func contrastRatio(with other: RGB8) -> Double {
        let first = relativeLuminance
        let second = other.relativeLuminance
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Per-channel linear interpolation, rounded half away from zero.
    public func blended(with other: RGB8, amount: Double) -> RGB8 {
        let t = min(max(amount, 0), 1)
        return RGB8(
            red: Self.interpolate(red, other.red, t),
            green: Self.interpolate(green, other.green, t),
            blue: Self.interpolate(blue, other.blue, t)
        )
    }

    private static func interpolate(_ start: UInt8, _ end: UInt8, _ amount: Double) -> UInt8 {
        let value = Double(start) + (Double(end) - Double(start)) * amount
        return UInt8(min(max(value.rounded(), 0), 255))
    }

    public static let black = RGB8(red: 0, green: 0, blue: 0)
    public static let white = RGB8(red: 255, green: 255, blue: 255)
    public static let midGray = RGB8(gray: 128)
}

extension RGB8 {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let color = RGB8(hex: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a #RRGGBB colour, got '\(value)'"
            )
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
