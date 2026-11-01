import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import StyleToneCore

/// Core Image implementation of the editor's tone/colour/finish stage.
///
/// The frozen Core contract has no tone engine, so WP-17 owns this protocol.
/// Values are already blended with manual offsets and the global strength by
/// `EditorRenderPlan`; this renderer only maps them to visible filters.
public struct CoreImageToneRenderer: EditorToneRendering {
    public init() {}

    public func applyTone(
        _ image: ImageAsset,
        settings: EditorToneSettings,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        guard !settings.isNeutral else { return image }

        guard let output = Self.render(
            image: image,
            tone: settings.tone,
            finish: settings.finish
        ) else {
            throw StyleToneError.renderingFailed
        }
        return output
    }

    private static func render(
        image: ImageAsset,
        tone: ToneParameters,
        finish: FinishParameters
    ) -> ImageAsset? {
        let source = CIImage(
            cgImage: image.cgImage,
            options: [.colorSpace: image.colorSpace]
        )
        var output = source

        if abs(tone.exposure) > 0.0005 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = output
            filter.ev = Float(tone.exposure * 2.0)
            output = filter.outputImage ?? output
        }

        if abs(tone.contrast) > 0.0005 || abs(tone.saturation) > 0.0005 {
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.contrast = Float(1 + tone.contrast * 0.35)
            filter.saturation = Float(1 + tone.saturation * 0.7)
            filter.brightness = 0
            output = filter.outputImage ?? output
        }

        if abs(tone.highlights) > 0.0005 || abs(tone.shadows) > 0.0005 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            // Positive highlights are left alone; negative values recover them.
            filter.highlightAmount = Float(1 + min(tone.highlights, 0) * 0.7)
            filter.shadowAmount = Float(tone.shadows * 0.6)
            filter.radius = 0
            output = filter.outputImage ?? output
        }

        if abs(tone.temperature) > 0.0005 || abs(tone.tint) > 0.0005 {
            let red = 1 + tone.temperature * 0.12 + tone.tint * 0.03
            let green = 1 - tone.tint * 0.08
            let blue = 1 - tone.temperature * 0.12 + tone.tint * 0.03
            let filter = CIFilter.colorMatrix()
            filter.inputImage = output
            filter.rVector = CIVector(x: red, y: 0, z: 0, w: 0)
            filter.gVector = CIVector(x: 0, y: green, z: 0, w: 0)
            filter.bVector = CIVector(x: 0, y: 0, z: blue, w: 0)
            filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            output = filter.outputImage ?? output
        }

        if finish.grain > 0.0005 {
            output = applyGrain(to: output, amount: finish.grain)
        }

        if finish.vignette < -0.0005 {
            let filter = CIFilter.vignette()
            filter.inputImage = output
            filter.intensity = Float(abs(finish.vignette) * 1.4)
            filter.radius = Float(max(1, min(image.width, image.height)) * 0.55)
            output = filter.outputImage ?? output
        }

        let context = CIContext(options: [
            .workingColorSpace: image.colorSpace,
            .outputColorSpace: image.colorSpace,
            .cacheIntermediates: false
        ])
        let extent = output.extent.integral
        guard !extent.isEmpty,
              let cgImage = context.createCGImage(output, from: extent)
        else {
            return nil
        }
        return ImageAsset(cgImage: cgImage, colorSpace: image.colorSpace)
    }

    private static func applyGrain(to image: CIImage, amount: Double) -> CIImage {
        guard let random = CIFilter.randomGenerator().outputImage else {
            return image
        }
        let monochrome = random.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: 1,
            kCIInputBrightnessKey: 0
        ])
        let alpha = monochrome.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: amount * 0.12)
        ])
        let grain = alpha.cropped(to: image.extent)
        return grain.applyingFilter("CISoftLightBlendMode", parameters: [
            kCIInputBackgroundImageKey: image
        ])
    }
}
