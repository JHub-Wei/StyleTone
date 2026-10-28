import Foundation
import StyleToneCore
import StyleToneImaging

/// CPU implementation of the skin smoothing and evenness pass.
///
/// The image is processed in overlapping horizontal bands. Only one band is
/// linearised at a time, so a 12 MP render never holds two full linear RGBA
/// buffers plus the full set of filter scratch arrays. The overlap is twice the
/// guided-filter radius, which makes the result independent of band height.
struct SkinRetouchPipeline: Sendable {
    let configuration: SkinRetouchConfiguration

    func render(
        _ image: ImageAsset,
        analysis: PortraitAnalysis,
        parameters: SkinParameters
    ) throws -> ImageAsset {
        guard image.width > 0, image.height > 0 else {
            throw StyleToneError.invalidImage
        }

        let smoothing = RetouchMath.unit(parameters.smoothing) *
            RetouchMath.unit(configuration.maximumSmoothing)
        let requestedEvenness = RetouchMath.unit(parameters.evenness) *
            RetouchMath.unit(configuration.maximumEvenness)
        guard smoothing > 0.0005 || requestedEvenness > 0.0005 else {
            return image
        }

        // A coarse or stale mask must never lead to smoothing hair, clothes or
        // the background. Returning the original is the documented fallback.
        guard let skinMask = analysis.skinMask,
              skinMask.width == image.width,
              skinMask.height == image.height
        else {
            return image
        }

        let guardMask = FeatureGuardMask.make(
            analysis: analysis,
            imageSize: image.pixelSize
        )
        guard let alpha = SkinAlphaPlane.combined(
            mask: skinMask,
            guardMask: guardMask,
            minimumCoverage: configuration.minimumMaskCoverage
        ) else {
            return image
        }

        let shortEdge = max(1, min(image.width, image.height))
        let fineRadius = max(
            1,
            min(
                64,
                Int((configuration.fineRadiusFraction * Double(shortEdge)).rounded())
            )
        )
        let regionalRadius = max(
            fineRadius + 2,
            min(
                256,
                Int((configuration.regionalRadiusFraction * Double(shortEdge)).rounded())
            )
        )

        var effectiveEvenness = requestedEvenness
        var lowFrequency: LowFrequencyField?
        if effectiveEvenness > 0.0005 {
            do {
                lowFrequency = try LowFrequencyField.make(
                    image: image,
                    colorSpace: image.colorSpace,
                    regionalRadius: regionalRadius,
                    skinAlpha: alpha
                )
            } catch {
                lowFrequency = nil
            }
            if lowFrequency == nil {
                effectiveEvenness = 0
            }
        }
        guard smoothing > 0.0005 || effectiveEvenness > 0.0005 else {
            return image
        }

        let fineFloor = Float(RetouchMath.unit(configuration.fineTextureRetain))
        let evennessFloor = Float(RetouchMath.unit(configuration.evennessRetain))
        let fineRetain = 1 - (1 - fineFloor) * Float(smoothing)
        let evennessRetain = 1 - (1 - evennessFloor) * Float(effectiveEvenness)
        let guidedEpsilon = Float(max(configuration.guidedEpsilon, 1e-6))
        let edgeThreshold = Float(max(configuration.edgeProtectionThreshold, 1e-4))
        let evennessLimit = Float(max(configuration.evennessChangeLimit, 0))
        let chromaStrength = Float(RetouchMath.unit(configuration.chromaEvenness))
        let evennessStrength = Float(effectiveEvenness)

        let width = image.width
        let height = image.height
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixelCount > 0 else {
            throw StyleToneError.invalidImage
        }
        var output = [SIMD4<Float>](
            repeating: SIMD4<Float>(0, 0, 0, 0),
            count: pixelCount
        )

        let tileHeight = max(64, min(1024, configuration.tileHeight))
        let halo = fineRadius * 2 + 2
        let pipeline = ColorPipeline()
        var tileStart = 0

        while tileStart < height {
            try Task.checkCancellation()
            let tileEnd = min(tileStart + tileHeight, height)
            let bandStart = max(0, tileStart - halo)
            let bandEnd = min(height, tileEnd + halo)
            let band = try pipeline.linearize(
                image,
                region: PixelRegion(
                    x: 0,
                    y: bandStart,
                    width: width,
                    height: bandEnd - bandStart
                )
            )
            guard band.width == width, band.height == bandEnd - bandStart else {
                throw StyleToneError.invalidImage
            }

            var luma = [Float](repeating: 0, count: band.pixelCount)
            band.pixels.withUnsafeBufferPointer { input in
                luma.withUnsafeMutableBufferPointer { destination in
                    for index in 0 ..< band.pixelCount {
                        destination[index] = RetouchMath.luma(input[index])
                    }
                }
            }
            let base = GuidedFilter.selfGuided(
                luma,
                width: width,
                height: band.height,
                radius: fineRadius,
                epsilon: guidedEpsilon
            )

            for globalY in tileStart ..< tileEnd {
                if (globalY & 0x3F) == 0 {
                    try Task.checkCancellation()
                }
                let localRow = (globalY - bandStart) * width
                let globalRow = globalY * width
                for x in 0 ..< width {
                    let localIndex = localRow + x
                    let globalIndex = globalRow + x
                    let original = band.pixels[localIndex]
                    let alphaByte = alpha[globalIndex]
                    guard alphaByte > 0 else {
                        output[globalIndex] = original
                        continue
                    }

                    let alphaUnit = Float(alphaByte) * (1.0 / 255.0)
                    let y = luma[localIndex]
                    let baseY = base[localIndex]
                    let detail = y - baseY
                    let originalChroma = RetouchMath.chroma(
                        red: original.x,
                        green: original.y,
                        blue: original.z,
                        luma: y
                    )

                    var targetLuma: Float
                    var targetChroma = originalChroma

                    if let lowFrequency, evennessStrength > 0.0005 {
                        let low = lowFrequency.sample(x: x, y: globalY)
                        let edge = RetouchMath.edgeWeight(
                            detail: detail,
                            threshold: edgeThreshold
                        )
                        let midFrequency = baseY - low.x
                        let rawChange = midFrequency * (evennessRetain - 1) * edge
                        let change = min(
                            max(rawChange, -evennessLimit),
                            evennessLimit
                        )
                        targetLuma = low.x + change + detail * fineRetain

                        let chromaBlend = alphaUnit * evennessStrength *
                            chromaStrength * edge
                        targetChroma = SIMD2<Float>(
                            originalChroma.x +
                                (low.y - originalChroma.x) * chromaBlend,
                            originalChroma.y +
                                (low.z - originalChroma.y) * chromaBlend
                        )
                    } else {
                        targetLuma = baseY + detail * fineRetain
                    }

                    let outputLuma = y + (targetLuma - y) * alphaUnit
                    let reconstructed = RetouchMath.reconstruct(
                        luma: outputLuma,
                        chroma: targetChroma
                    )
                    guard reconstructed.x.isFinite,
                          reconstructed.y.isFinite,
                          reconstructed.z.isFinite
                    else {
                        output[globalIndex] = original
                        continue
                    }
                    output[globalIndex] = SIMD4<Float>(
                        min(max(reconstructed.x, -0.5), 2),
                        min(max(reconstructed.y, -0.5), 2),
                        min(max(reconstructed.z, -0.5), 2),
                        original.w
                    )
                }
            }
            tileStart = tileEnd
        }

        let linearOutput = try LinearImage(
            width: width,
            height: height,
            pixels: output
        )
        let targetColorSpace = ImageColorSpace.detect(image.colorSpace)
        do {
            return try pipeline.makeImage(
                from: linearOutput,
                colorSpace: targetColorSpace
            )
        } catch let error as StyleToneError {
            throw error
        } catch {
            throw StyleToneError.retouchingFailed
        }
    }
}
