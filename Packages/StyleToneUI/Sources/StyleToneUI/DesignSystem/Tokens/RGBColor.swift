import Foundation
import SwiftUI

/// A resolved sRGB colour value used by the design tokens.
///
/// Tokens are stored as plain components so contrast can be verified in unit
/// tests without rendering a view or depending on UIKit.
public struct RGBColor: Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double

    /// Creates a colour from sRGB components. Input is clamped to `0...1`.
    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    /// Creates a neutral grey colour with equal components.
    public init(white: Double) {
        self.init(red: white, green: white, blue: white)
    }

    /// Creates a colour from a `0xRRGGBB` value.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    /// Uppercase `#RRGGBB` representation, useful for design review.
    public var hexString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// WCAG 2.1 relative luminance.
    public var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between two opaque colours, from 1.0 to 21.0.
    public func contrastRatio(with other: RGBColor) -> Double {
        let lhs = relativeLuminance
        let rhs = other.relativeLuminance
        let lighter = max(lhs, rhs)
        let darker = min(lhs, rhs)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Composites this colour over an opaque background.
    public func blended(over background: RGBColor, opacity: Double) -> RGBColor {
        let alpha = Self.clamp(opacity)
        return RGBColor(
            red: red * alpha + background.red * (1 - alpha),
            green: green * alpha + background.green * (1 - alpha),
            blue: blue * alpha + background.blue * (1 - alpha)
        )
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

public extension Color {
    /// Creates a SwiftUI colour from a design token value.
    init(_ rgb: RGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}
