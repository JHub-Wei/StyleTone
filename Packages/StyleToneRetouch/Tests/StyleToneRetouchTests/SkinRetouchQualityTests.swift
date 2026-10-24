import GoldenSupport
import StyleToneCore
import XCTest
@testable import StyleToneRetouch

final class SkinRetouchQualityTests: XCTestCase {
    private let retoucher = SkinRetoucher()

    func testZeroStrengthReturnsOriginalAsset() async throws {
        let size = PixelSize(width: 64, height: 64)
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[2].color
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size)
        )
        let output = try await retoucher.retouch(
            input,
            analysis: analysis,
            parameters: SkinParameters(smoothing: 0, evenness: 0, blemish: 1)
        )
        XCTAssertTrue(output.cgImage === input.cgImage)
    }

    func testMissingEmptyAndWrongSizeMasksReturnOriginalAsset() async throws {
        let size = PixelSize(width: 64, height: 64)
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[2].color
        )
        let parameters = SkinParameters(smoothing: 0.8, evenness: 0.6)

        let missingMask = try await retoucher.retouch(
            input,
            analysis: SyntheticSkin.analysis(size: size, mask: nil),
            parameters: parameters
        )
        XCTAssertTrue(missingMask.cgImage === input.cgImage)

        let emptyMask = try await retoucher.retouch(
            input,
            analysis: SyntheticSkin.analysis(
                size: size,
                mask: try SyntheticSkin.emptyMask(size: size)
            ),
            parameters: parameters
        )
        XCTAssertTrue(emptyMask.cgImage === input.cgImage)

        let wrongSizeMask = try MockMaskFactory.solid(
            value: 255,
            size: PixelSize(width: 32, height: 32)
        )
        let mismatched = try await retoucher.retouch(
            input,
            analysis: SyntheticSkin.analysis(size: size, mask: wrongSizeMask),
            parameters: parameters
        )
        XCTAssertTrue(mismatched.cgImage === input.cgImage)
    }

    func testMaximumSmoothingRetainsTextureAndBrightness() async throws {
        let size = PixelSize(width: 192, height: 192)
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[2].color
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size)
        )
        let output = try await retoucher.retouch(
            input,
            analysis: analysis,
            parameters: SkinParameters(smoothing: 1, evenness: 0)
        )
        let before = try PixelBuffer(image: input)
        let after = try PixelBuffer(image: output)

        let textureBefore = SyntheticSkin.highFrequencyStd(before)
        let textureAfter = SyntheticSkin.highFrequencyStd(after)
        let textureRatio = textureAfter / max(textureBefore, 1e-6)
        XCTAssertGreaterThan(textureRatio, 0.2, "pores were erased")
        XCTAssertLessThan(textureRatio, 0.95, "smoothing had no effect")

        XCTAssertEqual(after.meanLuma, before.meanLuma, accuracy: 1.5)
        XCTAssertEqual(output.pixelSize, input.pixelSize)
    }

    func testMultiSkinToneEvennessDoesNotWhitenOrDesaturate() async throws {
        let size = PixelSize(width: 96, height: 96)
        let parameters = SkinParameters(smoothing: 0.8, evenness: 0.6)
        let mask = try SyntheticSkin.fullMask(size: size)

        for tone in SyntheticSkin.tones {
            let input = try SyntheticSkin.image(size: size, tone: tone.color)
            let analysis = SyntheticSkin.analysis(size: size, mask: mask)
            let output = try await retoucher.retouch(
                input,
                analysis: analysis,
                parameters: parameters
            )
            let before = try PixelBuffer(image: input)
            let after = try PixelBuffer(image: output)

            let lumaDelta = after.meanLuma - before.meanLuma
            XCTAssertLessThan(
                abs(lumaDelta),
                1.0,
                "\(tone.name): brightness shifted by \(lumaDelta)"
            )

            let saturationBefore = SyntheticSkin.meanSaturation(before)
            let saturationAfter = SyntheticSkin.meanSaturation(after)
            XCTAssertGreaterThan(
                saturationAfter / max(saturationBefore, 1e-6),
                0.985,
                "\(tone.name): skin was desaturated"
            )

            var hueDelta = SyntheticSkin.meanHueDegrees(after) -
                SyntheticSkin.meanHueDegrees(before)
            while hueDelta > 180 { hueDelta -= 360 }
            while hueDelta < -180 { hueDelta += 360 }
            XCTAssertLessThan(
                abs(hueDelta),
                1.5,
                "\(tone.name): hue shifted by \(hueDelta) degrees"
            )

            let textureRatio = SyntheticSkin.highFrequencyStd(after)
                / max(SyntheticSkin.highFrequencyStd(before), 1e-6)
            XCTAssertGreaterThan(
                textureRatio,
                0.15,
                "\(tone.name): texture was flattened"
            )
        }
    }

    func testEvennessReducesRegionalBlotches() async throws {
        let size = PixelSize(width: 192, height: 192)
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[2].color,
            seed: 7
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size)
        )
        let output = try await retoucher.retouch(
            input,
            analysis: analysis,
            parameters: SkinParameters(smoothing: 0, evenness: 1)
        )
        let before = try PixelBuffer(image: input)
        let after = try PixelBuffer(image: output)

        let blotchBefore = SyntheticSkin.lowFrequencyStd(before)
        let blotchAfter = SyntheticSkin.lowFrequencyStd(after)
        XCTAssertLessThan(
            blotchAfter,
            blotchBefore * 0.92,
            "evenness did not reduce regional variation"
        )
        XCTAssertEqual(after.meanLuma, before.meanLuma, accuracy: 1.5)
        XCTAssertGreaterThan(
            SyntheticSkin.highFrequencyStd(after)
                / max(SyntheticSkin.highFrequencyStd(before), 1e-6),
            0.35,
            "evenness removed fine texture"
        )
    }

    func testStrongEdgeContrastIsPreserved() async throws {
        let size = PixelSize(width: 160, height: 160)
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[2].color,
            stepEdge: true
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size)
        )
        let output = try await retoucher.retouch(
            input,
            analysis: analysis,
            parameters: SkinParameters(smoothing: 1, evenness: 1)
        )
        let before = try PixelBuffer(image: input)
        let after = try PixelBuffer(image: output)

        let contrastBefore = SyntheticSkin.edgeContrast(before)
        let contrastAfter = SyntheticSkin.edgeContrast(after)
        XCTAssertGreaterThan(contrastBefore, 10)
        XCTAssertGreaterThan(
            contrastAfter / max(contrastBefore, 1e-6),
            0.85,
            "a strong structure was flattened"
        )
    }

    func testFeatureGuardKeepsEyePixelsUntouched() async throws {
        let size = PixelSize(width: 128, height: 128)
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[2].color
        )
        let eye = [
            NormalizedPoint(x: 0.42, y: 0.42),
            NormalizedPoint(x: 0.58, y: 0.42),
            NormalizedPoint(x: 0.58, y: 0.58),
            NormalizedPoint(x: 0.42, y: 0.58)
        ]
        let face = FaceObservation(
            boundingBox: NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            landmarks: [.leftEye: eye],
            confidence: 0.95
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size),
            faces: [face]
        )
        let output = try await retoucher.retouch(
            input,
            analysis: analysis,
            parameters: SkinParameters(smoothing: 1, evenness: 0)
        )
        let before = try PixelBuffer(image: input)
        let after = try PixelBuffer(image: output)

        for y in 62 ... 66 {
            for x in 62 ... 66 {
                XCTAssertEqual(
                    after[x, y],
                    before[x, y],
                    "guarded eye pixel (\(x), \(y)) changed"
                )
            }
        }
    }

    func testNaNAndOutOfRangeParametersAreSafe() async throws {
        let size = PixelSize(width: 64, height: 64)
        let input = try SyntheticSkin.image(
            size: size,
            tone: SyntheticSkin.tones[2].color
        )
        let analysis = SyntheticSkin.analysis(
            size: size,
            mask: try SyntheticSkin.fullMask(size: size)
        )

        let clamped = try await retoucher.retouch(
            input,
            analysis: analysis,
            parameters: SkinParameters(smoothing: 2, evenness: -3)
        )
        XCTAssertEqual(clamped.pixelSize, input.pixelSize)

        let notANumber = try await retoucher.retouch(
            input,
            analysis: analysis,
            parameters: SkinParameters(
                smoothing: .nan,
                evenness: .nan,
                blemish: .nan
            )
        )
        XCTAssertTrue(notANumber.cgImage === input.cgImage)
    }
}
