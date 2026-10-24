import Foundation
import StyleToneCore

/// Validated, feature-protected skin coverage for one image.
enum SkinAlphaPlane {
    /// Combines the analysis skin mask with the landmark guard.
    ///
    /// - Returns: `nil` when the mask is empty or below the minimum coverage,
    ///   which lets callers return the original image without doing any pixel
    ///   work.
    static func combined(
        mask: MaskBuffer,
        guardMask: [UInt8]?,
        minimumCoverage: Int
    ) -> [UInt8]? {
        guard mask.width > 0, mask.height > 0 else { return nil }
        var alpha = [UInt8](mask.bytes)
        guard alpha.count == mask.width * mask.height else { return nil }

        if let guardMask, guardMask.count == alpha.count {
            for index in alpha.indices {
                let protection = Int(guardMask[index])
                if protection > 0 {
                    alpha[index] = UInt8(
                        (Int(alpha[index]) * (255 - protection)) / 255
                    )
                }
            }
        }

        let required = max(1, minimumCoverage)
        var coverage = 0
        for value in alpha where value > 8 {
            coverage += 1
            if coverage >= required {
                return alpha
            }
        }
        return nil
    }
}
