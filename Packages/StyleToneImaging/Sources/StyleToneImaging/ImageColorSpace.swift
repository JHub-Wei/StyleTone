import CoreGraphics
import Foundation

/// Working color spaces supported by the imaging module.
///
/// `StyleToneCore` defines 8-bit sRGB with premultiplied alpha as the exchange
/// baseline. Display P3 sources are preserved by ``ImageLoader`` by default so
/// that wide-gamut data is not clipped at import; the actual pixels are always
/// described by `ImageAsset.colorSpace` and consumers must not assume sRGB.
public enum ImageColorSpace: String, Sendable, CaseIterable {
    /// IEC 61966-2-1 sRGB.
    case sRGB
    /// Display P3 (D65), the wide-gamut space used by modern iPhone captures.
    case displayP3

    /// Human-readable ICC profile name. Intended for diagnostics and tests.
    public var displayName: String {
        switch self {
        case .sRGB:
            return "sRGB IEC61966-2.1"
        case .displayP3:
            return "Display P3"
        }
    }

    /// Canonical Core Graphics color space used for decoding and encoding.
    public var cgColorSpace: CGColorSpace {
        let name = self == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3
        return CGColorSpace(name: name) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// Classifies a Core Graphics color space.
    ///
    /// Only sRGB and Display P3 are first-class working spaces. Any other RGB
    /// space (for example Adobe RGB) is treated as sRGB, which is safe because
    /// Core Graphics converts those pixels into sRGB when they are drawn into
    /// an sRGB context.
    public static func detect(_ colorSpace: CGColorSpace) -> ImageColorSpace {
        if let p3 = CGColorSpace(name: CGColorSpace.displayP3), CFEqual(colorSpace, p3) {
            return .displayP3
        }
        if let copiedName = CGColorSpaceCopyName(colorSpace) {
            let name = copiedName as String
            if name.localizedCaseInsensitiveContains("P3") {
                return .displayP3
            }
            if name.localizedCaseInsensitiveContains("sRGB") {
                return .sRGB
            }
        }
        return .sRGB
    }
}
