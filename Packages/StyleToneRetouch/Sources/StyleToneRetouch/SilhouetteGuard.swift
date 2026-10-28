import Foundation

/// Keeps evenness away from the subject silhouette.
///
/// The skin mask is often binary: full coverage inside the subject and zero
/// outside. Evenness can soften the skin side of that boundary enough to lower
/// the measured edge gradient, so the guard marks a narrow band around every
/// skin/background transition and the retoucher fades evenness out there.
enum SilhouetteGuard {
    static func make(
        alpha: [UInt8],
        width: Int,
        height: Int,
        radius: Int = 2
    ) -> [UInt8] {
        guard width > 0, height > 0, alpha.count == width * height else {
            return []
        }

        let band = max(1, min(radius, 8))
        let far = UInt8(band + 1)
        var distance = [UInt8](repeating: far, count: alpha.count)
        for index in alpha.indices where alpha[index] == 0 {
            distance[index] = 0
        }

        // Two-pass chamfer distance to the nearest non-skin pixel. This is
        // linear in the pixel count and avoids a per-radius dilation scan.
        for y in 0 ..< height {
            let row = y * width
            for x in 0 ..< width {
                let index = row + x
                guard alpha[index] > 0 else { continue }
                var value = distance[index]
                if y > 0 {
                    value = min(value, distance[index - width] &+ 1)
                }
                if x > 0 {
                    value = min(value, distance[index - 1] &+ 1)
                }
                distance[index] = min(value, far)
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            let row = y * width
            for x in stride(from: width - 1, through: 0, by: -1) {
                let index = row + x
                guard alpha[index] > 0 else { continue }
                var value = distance[index]
                if y + 1 < height {
                    value = min(value, distance[index + width] &+ 1)
                }
                if x + 1 < width {
                    value = min(value, distance[index + 1] &+ 1)
                }
                distance[index] = min(value, far)
            }
        }

        var guardMask = [UInt8](repeating: 255, count: alpha.count)
        for index in alpha.indices where alpha[index] == 0 || distance[index] <= band {
            guardMask[index] = 0
        }
        return guardMask
    }
}
