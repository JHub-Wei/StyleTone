import Foundation
import StyleToneCore

/// One hip-knee-ankle chain in top-left normalized image coordinates.
///
/// The centreline is the two-segment polyline hip → knee → ankle. Widths are
/// estimated per leg (from the person mask when available, otherwise from the
/// hip separation) and stored as vertical stations between hip and ankle.
struct LegsPoseLeg {
    let hip: SIMD2<Double>
    let knee: SIMD2<Double>
    let ankle: SIMD2<Double>
    var widthStations: [Double]

    /// Vertical hip-to-ankle distance.
    var length: Double {
        ankle.y - hip.y
    }

    /// Vertical knee-to-ankle distance.
    var shinLength: Double {
        ankle.y - knee.y
    }

    /// Vertical hip-to-knee distance.
    var thighLength: Double {
        knee.y - hip.y
    }

    /// Horizontal centre of the leg at `y`, or `nil` outside the chain.
    func centreX(atY y: Double) -> Double? {
        guard y >= hip.y, y <= ankle.y, length > 1e-9 else {
            return nil
        }
        if y <= knee.y {
            let span = knee.y - hip.y
            guard span > 1e-9 else { return knee.x }
            let t = (y - hip.y) / span
            return LegsMath.lerp(hip.x, knee.x, t)
        }
        let span = ankle.y - knee.y
        guard span > 1e-9 else { return ankle.x }
        let t = (y - knee.y) / span
        return LegsMath.lerp(knee.x, ankle.x, t)
    }

    /// Interpolated half-width at `y`, in normalized image x.
    func halfWidth(atY y: Double) -> Double {
        guard !widthStations.isEmpty else { return 0 }
        if widthStations.count == 1 {
            return widthStations[0]
        }
        let t = LegsMath.clamp((y - hip.y) / max(length, 1e-9), 0, 1)
        let position = t * Double(widthStations.count - 1)
        let index = min(Int(position), widthStations.count - 2)
        let fraction = position - Double(index)
        return LegsMath.lerp(
            widthStations[index],
            widthStations[index + 1],
            fraction
        )
    }

    /// Half-width clamped so a leg close to the left/right frame edge does not
    /// try to sample content beyond the image.
    ///
    /// This is the lateral version of edge extension: instead of asking the
    /// sampler for out-of-frame texels, the profile is compressed into the
    /// visible side of the leg. WP-06's clamp-to-edge sampler still provides
    /// the pixel-level fill for any residual sub-pixel excursion.
    func effectiveHalfWidth(
        atY y: Double,
        configuration: LegsWarpConfiguration
    ) -> Double {
        guard let centre = centreX(atY: y) else { return 0 }
        let width = halfWidth(atY: y)
        guard width > 0 else { return 0 }
        let room = min(centre, 1 - centre) - 0.004
        let lowerBound = configuration.minimumHalfWidth * 0.5
        return min(width, max(room, lowerBound))
    }
}

/// Estimates per-leg widths from the person mask.
///
/// The scan is deliberately conservative: it walks outward from the centreline
/// only until the mask drops below the threshold or the search reaches the
/// midpoint to the other leg. This keeps two touching thighs from being merged
/// into one silhouette.
enum LegsWidthEstimator {
    /// Returns one width station per vertical sample.
    static func stations(
        for leg: LegsPoseLeg,
        otherLeg: LegsPoseLeg,
        mask: MaskBuffer?,
        imageSize: PixelSize,
        fallback: Double,
        configuration: LegsWarpConfiguration
    ) -> [Double] {
        let count = configuration.widthStationCount
        var values = Array(repeating: fallback, count: count)
        guard let mask,
              mask.width == imageSize.width,
              mask.height == imageSize.height,
              imageSize.width > 0,
              imageSize.height > 0
        else {
            return values
        }

        let threshold = configuration.personMaskThreshold
        var samples = 0
        for index in 0 ..< count {
            let fraction = count == 1 ? 0 : Double(index) / Double(count - 1)
            let y = LegsMath.lerp(leg.hip.y, leg.ankle.y, fraction)
            guard let centreX = leg.centreX(atY: y) else { continue }
            let row = min(max(Int(y * Double(imageSize.height)), 0), imageSize.height - 1)
            let centrePixel = min(
                max(Int(centreX * Double(imageSize.width)), 0),
                imageSize.width - 1
            )
            guard let centreValue = mask.normalizedValue(x: centrePixel, y: row),
                  centreValue >= threshold
            else {
                continue
            }

            let separation = otherLeg.centreX(atY: y).map { abs($0 - centreX) } ?? 0
            let halfSeparation = separation > 0
                ? separation * 0.45
                : configuration.maximumHalfWidth
            let searchHalfWidth = min(
                max(fallback * 2.0, configuration.minimumHalfWidth),
                halfSeparation
            )
            let runLimit = max(
                1,
                Int((searchHalfWidth * Double(imageSize.width)).rounded(.down))
            )

            var left = 0
            var leftClippedByFrame = false
            while left < runLimit {
                let pixel = centrePixel - left - 1
                guard pixel >= 0 else {
                    leftClippedByFrame = true
                    break
                }
                guard let value = mask.normalizedValue(x: pixel, y: row),
                      value >= threshold
                else {
                    break
                }
                left += 1
            }

            var right = 0
            var rightClippedByFrame = false
            while right < runLimit {
                let pixel = centrePixel + right + 1
                guard pixel < imageSize.width else {
                    rightClippedByFrame = true
                    break
                }
                guard let value = mask.normalizedValue(x: pixel, y: row),
                      value >= threshold
                else {
                    break
                }
                right += 1
            }

            guard left + right > 0 else { continue }

            // Mirror extension: when the leg (or its mask) is cut by the frame
            // on one side, the visible side is mirrored instead of averaging a
            // truncated run with a full one. This keeps the estimated contour
            // symmetric for legs at the left/right border.
            var measuredLeft = left
            var measuredRight = right
            if leftClippedByFrame, right > 0, right < runLimit {
                measuredLeft = right
            }
            if rightClippedByFrame, left > 0, left < runLimit {
                measuredRight = left
            }
            let halfWidth = Double(measuredLeft + measuredRight)
                / 2 / Double(imageSize.width)
            values[index] = LegsMath.clamp(
                halfWidth,
                configuration.minimumHalfWidth,
                configuration.maximumHalfWidth
            )
            samples += 1
        }

        guard samples > 0 else { return values }

        // Light smoothing removes single-pixel mask noise without blurring the
        // hip-to-ankle taper.
        if count >= 3 {
            let previous = values
            for index in 1 ..< count - 1 {
                values[index] = (
                    previous[index - 1]
                        + previous[index] * 2
                        + previous[index + 1]
                ) / 4
            }
        }
        return values
    }
}
