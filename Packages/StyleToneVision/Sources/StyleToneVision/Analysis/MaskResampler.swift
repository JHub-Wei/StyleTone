import Foundation
import StyleToneCore

/// Resamples masks between the analysis proxy and the original image size.
///
/// Bilinear resampling keeps soft mask edges usable after downscaling. The
/// resampler is deterministic and row-major; it never changes the mask's
/// meaning or color space.
enum MaskResampler {
    static func resample(_ mask: MaskBuffer, to target: PixelSize) throws -> MaskBuffer {
        guard target.isPositive else {
            throw StyleToneError.invalidMask
        }
        if mask.width == target.width, mask.height == target.height {
            return mask
        }

        var bytes = [UInt8](repeating: 0, count: target.width * target.height)
        let scaleX = Double(mask.width) / Double(target.width)
        let scaleY = Double(mask.height) / Double(target.height)

        for y in 0 ..< target.height {
            if y.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            let sourceY = (Double(y) + 0.5) * scaleY - 0.5
            let y0 = Int(sourceY.rounded(.down))
            let y1 = y0 + 1
            let fy = sourceY - Double(y0)
            let row0 = min(max(y0, 0), mask.height - 1) * mask.width
            let row1 = min(max(y1, 0), mask.height - 1) * mask.width
            let destinationRow = y * target.width

            for x in 0 ..< target.width {
                let sourceX = (Double(x) + 0.5) * scaleX - 0.5
                let x0 = Int(sourceX.rounded(.down))
                let x1 = x0 + 1
                let fx = sourceX - Double(x0)
                let column0 = min(max(x0, 0), mask.width - 1)
                let column1 = min(max(x1, 0), mask.width - 1)

                let topLeft = Double(mask.bytes[row0 + column0])
                let topRight = Double(mask.bytes[row0 + column1])
                let bottomLeft = Double(mask.bytes[row1 + column0])
                let bottomRight = Double(mask.bytes[row1 + column1])

                let top = topLeft + (topRight - topLeft) * fx
                let bottom = bottomLeft + (bottomRight - bottomLeft) * fx
                let value = top + (bottom - top) * fy
                bytes[destinationRow + x] = UInt8(min(max(Int(value.rounded()), 0), 255))
            }
        }

        return try MaskBuffer(width: target.width, height: target.height, bytes: Data(bytes))
    }
}
