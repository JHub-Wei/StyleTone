import Foundation
import StyleToneCore

/// Local, patch-based blemish repair.
///
/// The algorithm is deliberately small and deterministic:
///
/// 1. Fit a low-order colour plane to an annulus around the blemish. The plane
///    carries local skin shading, so the repair blends into the surrounding
///    cheek instead of becoming a flat disk.
/// 2. Search a ring of nearby source patches and score them by comparing the
///    target annulus with the shifted source annulus. The best patch supplies
///    pore-scale texture.
/// 3. Transfer only high-frequency detail (source minus a local box blur),
///    clamped to a fraction of the measured ring texture. This keeps pores but
///    stops a second blemish in the source patch from being copied.
/// 4. Composite through a smooth alpha ramp inside the disk. Nothing outside
///    the requested radius is touched.
struct PatchBlemishInpainter: Sendable {
    private struct Plane {
        var constant: Float
        var x: Float
        var y: Float

        @inline(__always)
        func value(u: Float, v: Float) -> Float {
            constant + x * u + y * v
        }
    }

    private struct RingModel {
        var red: Plane
        var green: Plane
        var blue: Plane
        var mean: SIMD3<Float>
        var textureStandardDeviation: Float
    }

    private struct SourceOffset {
        var x: Int
        var y: Int
    }

    private struct DetailPatch {
        var patchMinX: Int
        var patchMinY: Int
        var patchWidth: Int
        var patchHeight: Int
        var offsetX: Int
        var offsetY: Int
        var red: [Float]
        var green: [Float]
        var blue: [Float]
        var limit: Float
    }

    /// Applies one blemish repair in linear extended sRGB.
    ///
    /// - Returns: `true` when at least one pixel was changed.
    static func apply(
        point: BlemishPoint,
        width: Int,
        height: Int,
        pixels: inout [SIMD4<Float>],
        skinMask: [UInt8]?
    ) -> Bool {
        guard width > 0,
              height > 0,
              pixels.count == width * height,
              point.point.x.isFinite,
              point.point.y.isFinite,
              point.radius.isFinite,
              point.point.x >= 0,
              point.point.x <= 1,
              point.point.y >= 0,
              point.point.y <= 1,
              point.radius > 0
        else {
            return false
        }

        let shortEdge = Double(min(width, height))
        let radius = min(
            max(point.radius, 0.005),
            0.12
        ) * shortEdge
        guard radius >= 0.75 else { return false }
        let centerX = point.point.x * Double(width)
        let centerY = point.point.y * Double(height)
        let minX = max(0, Int((centerX - radius).rounded(.down)))
        let maxX = min(width - 1, Int((centerX + radius).rounded(.up)))
        let minY = max(0, Int((centerY - radius).rounded(.down)))
        let maxY = min(height - 1, Int((centerY + radius).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return false }

        guard let model = makeRingModel(
            pixels: pixels,
            width: width,
            height: height,
            centerX: centerX,
            centerY: centerY,
            radius: radius
        ) else {
            return false
        }

        let detailRadius = max(2, min(8, Int((radius * 0.25).rounded())))
        let source = makeDetailPatch(
            pixels: pixels,
            width: width,
            height: height,
            centerX: centerX,
            centerY: centerY,
            radius: radius,
            targetBounds: (
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY
            ),
            detailRadius: detailRadius,
            model: model,
            skinMask: skinMask
        )

        let featherStart = radius * 0.72
        var changed = false
        for y in minY ... maxY {
            let dy = Double(y) + 0.5 - centerY
            for x in minX ... maxX {
                let dx = Double(x) + 0.5 - centerX
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance < radius else { continue }
                let alpha: Float
                if distance <= featherStart {
                    alpha = 1
                } else {
                    alpha = RetouchMath.smoothstep(
                        Float((radius - distance) / max(radius - featherStart, 0.001))
                    )
                }
                guard alpha > 0 else { continue }

                let u = Float(dx / radius)
                let v = Float(dy / radius)
                var red = model.red.value(u: u, v: v)
                var green = model.green.value(u: u, v: v)
                var blue = model.blue.value(u: u, v: v)
                if red.isFinite, green.isFinite, blue.isFinite {
                    if let source {
                        let localX = x + source.offsetX - source.patchMinX
                        let localY = y + source.offsetY - source.patchMinY
                        if localX >= 0,
                           localX < source.patchWidth,
                           localY >= 0,
                           localY < source.patchHeight
                        {
                            let localIndex = localY * source.patchWidth + localX
                            red += min(
                                max(source.red[localIndex], -source.limit),
                                source.limit
                            )
                            green += min(
                                max(source.green[localIndex], -source.limit),
                                source.limit
                            )
                            blue += min(
                                max(source.blue[localIndex], -source.limit),
                                source.limit
                            )
                        }
                    }
                } else {
                    red = model.mean.x
                    green = model.mean.y
                    blue = model.mean.z
                }

                let pixelIndex = y * width + x
                let original = pixels[pixelIndex]
                let repaired = SIMD3<Float>(
                    min(max(red, -0.25), 2),
                    min(max(green, -0.25), 2),
                    min(max(blue, -0.25), 2)
                )
                pixels[pixelIndex] = SIMD4<Float>(
                    original.x + (repaired.x - original.x) * alpha,
                    original.y + (repaired.y - original.y) * alpha,
                    original.z + (repaired.z - original.z) * alpha,
                    original.w
                )
                changed = true
            }
        }
        return changed
    }

    // MARK: - Ring model

    private static func makeRingModel(
        pixels: [SIMD4<Float>],
        width: Int,
        height: Int,
        centerX: Double,
        centerY: Double,
        radius: Double
    ) -> RingModel? {
        let inner = radius * 1.02
        let outer = radius * 1.50
        let searchRadius = outer + 1
        let minX = max(0, Int((centerX - searchRadius).rounded(.down)))
        let maxX = min(width - 1, Int((centerX + searchRadius).rounded(.up)))
        let minY = max(0, Int((centerY - searchRadius).rounded(.down)))
        let maxY = min(height - 1, Int((centerY + searchRadius).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return nil }

        var count = 0
        var meanRed = 0.0
        var meanGreen = 0.0
        var meanBlue = 0.0
        var meanLuma = 0.0
        for y in minY ... maxY {
            let dy = Double(y) + 0.5 - centerY
            for x in minX ... maxX {
                let dx = Double(x) + 0.5 - centerX
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance >= inner, distance <= outer else { continue }
                let pixel = pixels[y * width + x]
                meanRed += Double(pixel.x)
                meanGreen += Double(pixel.y)
                meanBlue += Double(pixel.z)
                meanLuma += Double(RetouchMath.luma(pixel))
                count += 1
            }
        }
        guard count >= 8 else { return nil }
        meanRed /= Double(count)
        meanGreen /= Double(count)
        meanBlue /= Double(count)
        meanLuma /= Double(count)

        var variance = 0.0
        for y in minY ... maxY {
            let dy = Double(y) + 0.5 - centerY
            for x in minX ... maxX {
                let dx = Double(x) + 0.5 - centerX
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance >= inner, distance <= outer else { continue }
                let luma = Double(RetouchMath.luma(pixels[y * width + x]))
                variance += (luma - meanLuma) * (luma - meanLuma)
            }
        }
        let lumaStandardDeviation = (variance / Double(count)).squareRoot()
        let clipLimit = max(lumaStandardDeviation * 2.5, 0.002)

        var s0 = 0.0
        var sx = 0.0
        var sy = 0.0
        var sxx = 0.0
        var sxy = 0.0
        var syy = 0.0
        var sr = 0.0
        var sg = 0.0
        var sb = 0.0
        var srx = 0.0
        var sry = 0.0
        var sgx = 0.0
        var sgy = 0.0
        var sbx = 0.0
        var sby = 0.0
        for y in minY ... maxY {
            let dy = Double(y) + 0.5 - centerY
            for x in minX ... maxX {
                let dx = Double(x) + 0.5 - centerX
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance >= inner, distance <= outer else { continue }
                let pixel = pixels[y * width + x]
                let luma = Double(RetouchMath.luma(pixel))
                guard abs(luma - meanLuma) <= clipLimit else { continue }
                let u = dx / radius
                let v = dy / radius
                s0 += 1
                sx += u
                sy += v
                sxx += u * u
                sxy += u * v
                syy += v * v
                let red = Double(pixel.x)
                let green = Double(pixel.y)
                let blue = Double(pixel.z)
                sr += red
                sg += green
                sb += blue
                srx += red * u
                sry += red * v
                sgx += green * u
                sgy += green * v
                sbx += blue * u
                sby += blue * v
            }
        }
        guard s0 >= 8 else { return nil }

        let redPlane = solvePlane(
            s0: s0, sx: sx, sy: sy, sxx: sxx, sxy: sxy, syy: syy,
            sc: sr, scx: srx, scy: sry
        ) ?? Plane(constant: Float(meanRed), x: 0, y: 0)
        let greenPlane = solvePlane(
            s0: s0, sx: sx, sy: sy, sxx: sxx, sxy: sxy, syy: syy,
            sc: sg, scx: sgx, scy: sgy
        ) ?? Plane(constant: Float(meanGreen), x: 0, y: 0)
        let bluePlane = solvePlane(
            s0: s0, sx: sx, sy: sy, sxx: sxx, sxy: sxy, syy: syy,
            sc: sb, scx: sbx, scy: sby
        ) ?? Plane(constant: Float(meanBlue), x: 0, y: 0)

        var residual = 0.0
        for y in minY ... maxY {
            let dy = Double(y) + 0.5 - centerY
            for x in minX ... maxX {
                let dx = Double(x) + 0.5 - centerX
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance >= inner, distance <= outer else { continue }
                let pixel = pixels[y * width + x]
                let u = Float(dx / radius)
                let v = Float(dy / radius)
                let dr = pixel.x - redPlane.value(u: u, v: v)
                let dg = pixel.y - greenPlane.value(u: u, v: v)
                let db = pixel.z - bluePlane.value(u: u, v: v)
                residual += Double(dr * dr + dg * dg + db * db)
            }
        }
        let textureDeviation = Float(
            (residual / Double(max(count, 1) * 3)).squareRoot()
        )

        return RingModel(
            red: redPlane,
            green: greenPlane,
            blue: bluePlane,
            mean: SIMD3<Float>(Float(meanRed), Float(meanGreen), Float(meanBlue)),
            textureStandardDeviation: textureDeviation
        )
    }

    private static func solvePlane(
        s0: Double,
        sx: Double,
        sy: Double,
        sxx: Double,
        sxy: Double,
        syy: Double,
        sc: Double,
        scx: Double,
        scy: Double
    ) -> Plane? {
        let determinant = s0 * (sxx * syy - sxy * sxy) -
            sx * (sx * syy - sxy * sy) +
            sy * (sx * sxy - sxx * sy)
        guard abs(determinant) > 1e-9 else { return nil }

        let constant = (
            sc * (sxx * syy - sxy * sxy) -
                sx * (scx * syy - sxy * scy) +
                sy * (scx * sxy - sxx * scy)
        ) / determinant
        let gradientX = (
            s0 * (scx * syy - sxy * scy) -
                sc * (sx * syy - sxy * sy) +
                sy * (sx * scy - scx * sy)
        ) / determinant
        let gradientY = (
            s0 * (sxx * scy - scx * sxy) -
                sx * (sx * scy - scx * sy) +
                sc * (sx * sxy - sxx * sy)
        ) / determinant
        guard constant.isFinite, gradientX.isFinite, gradientY.isFinite else {
            return nil
        }
        return Plane(
            constant: Float(constant),
            x: Float(min(max(gradientX, -0.5), 0.5)),
            y: Float(min(max(gradientY, -0.5), 0.5))
        )
    }

    // MARK: - Source patch

    private static func makeDetailPatch(
        pixels: [SIMD4<Float>],
        width: Int,
        height: Int,
        centerX: Double,
        centerY: Double,
        radius: Double,
        targetBounds: (minX: Int, maxX: Int, minY: Int, maxY: Int),
        detailRadius: Int,
        model: RingModel,
        skinMask: [UInt8]?
    ) -> DetailPatch? {
        guard let offset = bestOffset(
            pixels: pixels,
            width: width,
            height: height,
            centerX: centerX,
            centerY: centerY,
            radius: radius,
            model: model,
            skinMask: skinMask
        ) else {
            return nil
        }

        let margin = detailRadius + 2
        let patchMinX = targetBounds.minX + offset.x - margin
        let patchMinY = targetBounds.minY + offset.y - margin
        let patchMaxX = targetBounds.maxX + offset.x + margin + 1
        let patchMaxY = targetBounds.maxY + offset.y + margin + 1
        guard patchMinX >= 0,
              patchMinY >= 0,
              patchMaxX <= width,
              patchMaxY <= height
        else {
            return nil
        }
        let patchWidth = patchMaxX - patchMinX
        let patchHeight = patchMaxY - patchMinY
        let patchCount = patchWidth * patchHeight
        var red = [Float](repeating: 0, count: patchCount)
        var green = [Float](repeating: 0, count: patchCount)
        var blue = [Float](repeating: 0, count: patchCount)
        for y in 0 ..< patchHeight {
            let sourceY = patchMinY + y
            for x in 0 ..< patchWidth {
                let sourceX = patchMinX + x
                let pixel = pixels[sourceY * width + sourceX]
                let index = y * patchWidth + x
                red[index] = pixel.x
                green[index] = pixel.y
                blue[index] = pixel.z
            }
        }

        let blurredRed = BoxBlur.apply(
            red,
            width: patchWidth,
            height: patchHeight,
            radius: detailRadius
        )
        let blurredGreen = BoxBlur.apply(
            green,
            width: patchWidth,
            height: patchHeight,
            radius: detailRadius
        )
        let blurredBlue = BoxBlur.apply(
            blue,
            width: patchWidth,
            height: patchHeight,
            radius: detailRadius
        )
        for index in 0 ..< patchCount {
            red[index] -= blurredRed[index]
            green[index] -= blurredGreen[index]
            blue[index] -= blurredBlue[index]
        }

        let limit = min(
            max(model.textureStandardDeviation * 3, 0.012),
            0.06
        )
        return DetailPatch(
            patchMinX: patchMinX,
            patchMinY: patchMinY,
            patchWidth: patchWidth,
            patchHeight: patchHeight,
            offsetX: offset.x,
            offsetY: offset.y,
            red: red,
            green: green,
            blue: blue,
            limit: limit
        )
    }

    private static func bestOffset(
        pixels: [SIMD4<Float>],
        width: Int,
        height: Int,
        centerX: Double,
        centerY: Double,
        radius: Double,
        model: RingModel,
        skinMask: [UInt8]?
    ) -> SourceOffset? {
        let angularSteps = 16
        let distances = [1.6, 2.2, 2.9]
        let ringSamples = 96
        var targetSamples: [(x: Double, y: Double, color: SIMD3<Float>)] = []
        targetSamples.reserveCapacity(ringSamples)
        for index in 0 ..< ringSamples {
            let angle = Double(index) / Double(ringSamples) * 2 * Double.pi
            let ringRadius = radius * (index.isMultiple(of: 2) ? 1.10 : 1.38)
            let x = centerX + cos(angle) * ringRadius
            let y = centerY + sin(angle) * ringRadius
            guard let color = sample(
                pixels,
                width: width,
                height: height,
                x: x,
                y: y
            ) else {
                continue
            }
            targetSamples.append((x, y, color))
        }
        guard !targetSamples.isEmpty else { return nil }

        let targetCoverage = maskCoverage(
            skinMask,
            width: width,
            height: height,
            centerX: centerX,
            centerY: centerY,
            radius: radius
        )
        let targetIsSkin = targetCoverage > 0.35

        let margin = max(4, Int((radius * 0.25).rounded()) + 2)
        var best: (offset: SourceOffset, score: Double)?
        for distance in distances {
            let offsetDistance = radius * distance
            for angleIndex in 0 ..< angularSteps {
                let angle = Double(angleIndex) / Double(angularSteps) * 2 * Double.pi
                let offsetX = Int((cos(angle) * offsetDistance).rounded())
                let offsetY = Int((sin(angle) * offsetDistance).rounded())
                if offsetX == 0, offsetY == 0 { continue }
                let minSourceX = Int((centerX - radius).rounded(.down)) +
                    offsetX - margin
                let maxSourceX = Int((centerX + radius).rounded(.up)) +
                    offsetX + margin
                let minSourceY = Int((centerY - radius).rounded(.down)) +
                    offsetY - margin
                let maxSourceY = Int((centerY + radius).rounded(.up)) +
                    offsetY + margin
                guard minSourceX >= 0,
                      minSourceY >= 0,
                      maxSourceX < width,
                      maxSourceY < height
                else {
                    continue
                }

                var difference = 0.0
                var sampleCount = 0
                for targetSample in targetSamples {
                    guard let sourceColor = sample(
                        pixels,
                        width: width,
                        height: height,
                        x: targetSample.x + Double(offsetX),
                        y: targetSample.y + Double(offsetY)
                    ) else {
                        continue
                    }
                    difference += Double(
                        abs(sourceColor.x - targetSample.color.x) +
                            abs(sourceColor.y - targetSample.color.y) +
                            abs(sourceColor.z - targetSample.color.z)
                    )
                    sampleCount += 1
                }
                guard sampleCount >= targetSamples.count / 2 else { continue }
                var score = difference / Double(sampleCount) / 3
                if let sourceMean = meanColor(
                    pixels,
                    width: width,
                    height: height,
                    centerX: centerX + Double(offsetX),
                    centerY: centerY + Double(offsetY),
                    radius: radius * 0.35
                ) {
                    score += Double(
                        abs(sourceMean.x - model.mean.x) +
                            abs(sourceMean.y - model.mean.y) +
                            abs(sourceMean.z - model.mean.z)
                    ) / 3 * 0.6
                }
                if targetIsSkin, skinMask != nil {
                    let sourceCoverage = maskCoverage(
                        skinMask,
                        width: width,
                        height: height,
                        centerX: centerX + Double(offsetX),
                        centerY: centerY + Double(offsetY),
                        radius: radius * 0.7
                    )
                    score += (1 - sourceCoverage) * 0.08
                }
                if score < best?.score ?? Double.greatestFiniteMagnitude {
                    best = (
                        offset: SourceOffset(x: offsetX, y: offsetY),
                        score: score
                    )
                }
            }
        }
        return best?.offset
    }

    private static func sample(
        _ pixels: [SIMD4<Float>],
        width: Int,
        height: Int,
        x: Double,
        y: Double
    ) -> SIMD3<Float>? {
        guard x >= 0, y >= 0,
              x <= Double(width),
              y <= Double(height)
        else {
            return nil
        }
        let shiftedX = min(max(x - 0.5, 0), Double(width - 1))
        let shiftedY = min(max(y - 0.5, 0), Double(height - 1))
        let x0 = Int(shiftedX.rounded(.down))
        let y0 = Int(shiftedY.rounded(.down))
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = Float(shiftedX - Double(x0))
        let ty = Float(shiftedY - Double(y0))
        let top = pixels[y0 * width + x0] * (1 - tx) +
            pixels[y0 * width + x1] * tx
        let bottom = pixels[y1 * width + x0] * (1 - tx) +
            pixels[y1 * width + x1] * tx
        return SIMD3<Float>(top.x, top.y, top.z) * (1 - ty) +
            SIMD3<Float>(bottom.x, bottom.y, bottom.z) * ty
    }

    private static func meanColor(
        _ pixels: [SIMD4<Float>],
        width: Int,
        height: Int,
        centerX: Double,
        centerY: Double,
        radius: Double
    ) -> SIMD3<Float>? {
        let steps = 12
        var total = SIMD3<Float>(0, 0, 0)
        var count = 0
        for index in 0 ..< steps {
            let angle = Double(index) / Double(steps) * 2 * Double.pi
            let ringRadius = radius * (index.isMultiple(of: 2) ? 0.35 : 0.8)
            let x = centerX + cos(angle) * ringRadius
            let y = centerY + sin(angle) * ringRadius
            if let color = sample(pixels, width: width, height: height, x: x, y: y) {
                total += color
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return total / Float(count)
    }

    private static func maskCoverage(
        _ mask: [UInt8]?,
        width: Int,
        height: Int,
        centerX: Double,
        centerY: Double,
        radius: Double
    ) -> Double {
        guard let mask, mask.count == width * height else { return 1 }
        let steps = 16
        var covered = 0
        var total = 0
        for index in 0 ..< steps {
            let angle = Double(index) / Double(steps) * 2 * Double.pi
            let ringRadius = radius * (index.isMultiple(of: 2) ? 0.35 : 0.8)
            let x = Int((centerX + cos(angle) * ringRadius).rounded(.down))
            let y = Int((centerY + sin(angle) * ringRadius).rounded(.down))
            guard x >= 0, x < width, y >= 0, y < height else { continue }
            total += 1
            if mask[y * width + x] > 16 {
                covered += 1
            }
        }
        guard total > 0 else { return 1 }
        return Double(covered) / Double(total)
    }
}
