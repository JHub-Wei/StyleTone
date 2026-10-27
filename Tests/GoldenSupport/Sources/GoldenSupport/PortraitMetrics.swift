import Foundation
import StyleToneCore

private func portraitTrace(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - Thresholds

/// Thresholds for the absolute quality gates.
///
/// Values are chosen from perceptual standards, not from the current output:
/// - `1.5 px` line deviation is roughly one visible pixel at a 360 px-wide
///   preview and matches the WP-15 acceptance proxy (`0.005` normalized at
///   360 px is 1.8 px).
/// - CIEDE2000 `2.5...3` is the commonly used "visible difference" band.
/// - A single pixel of channel clipping is not an incident, but more than 0.5 %
///   of the skin region is.
///
/// Do not relax these to make a failing sample pass. A real regression is a bug
/// in the algorithm and must be filed against its owner.
public struct PortraitMetricThresholds: Sendable, Equatable, Codable {
    public var backgroundMaxDeviationPx: Double
    public var backgroundMaxAngleDegrees: Double

    public var skinMaxMeanDeltaE00: Double
    public var skinMaxP95DeltaE00: Double
    public var skinMaxDeltaL: Double
    public var skinMaxDeltaA: Double
    public var skinMaxDeltaB: Double
    public var skinMinSaturationRatio: Double
    public var skinMaxSaturationRatio: Double
    public var skinMaxHueShiftDegrees: Double
    public var skinMaxClipIncrease: Double
    public var skinMaxNonSkinP95DeltaE00: Double
    public var skinMaxFinalDeltaL: Double
    public var skinMaxFinalDarkDeltaL: Double
    public var skinMaxFinalDeltaE00: Double

    public var edgeMinMedianContrastRetention: Double
    public var edgeMinMeanContrastRetention: Double
    public var edgeMaxDegradedFraction: Double
    public var edgeMaxSignFlipFraction: Double
    public var edgeMaxOvershootFraction: Double
    public var edgeMinGradientEnergyRatio: Double

    public init(
        backgroundMaxDeviationPx: Double = 1.5,
        backgroundMaxAngleDegrees: Double = 1.0,
        skinMaxMeanDeltaE00: Double = 3.0,
        skinMaxP95DeltaE00: Double = 6.0,
        skinMaxDeltaL: Double = 1.5,
        skinMaxDeltaA: Double = 1.2,
        skinMaxDeltaB: Double = 1.5,
        skinMinSaturationRatio: Double = 0.965,
        skinMaxSaturationRatio: Double = 1.035,
        skinMaxHueShiftDegrees: Double = 3.0,
        skinMaxClipIncrease: Double = 0.005,
        skinMaxNonSkinP95DeltaE00: Double = 1.5,
        skinMaxFinalDeltaL: Double = 1.2,
        skinMaxFinalDarkDeltaL: Double = 1.0,
        skinMaxFinalDeltaE00: Double = 6.0,
        edgeMinMedianContrastRetention: Double = 0.80,
        edgeMinMeanContrastRetention: Double = 0.82,
        edgeMaxDegradedFraction: Double = 0.05,
        edgeMaxSignFlipFraction: Double = 0.01,
        edgeMaxOvershootFraction: Double = 0.03,
        edgeMinGradientEnergyRatio: Double = 0.75
    ) {
        self.backgroundMaxDeviationPx = backgroundMaxDeviationPx
        self.backgroundMaxAngleDegrees = backgroundMaxAngleDegrees
        self.skinMaxMeanDeltaE00 = skinMaxMeanDeltaE00
        self.skinMaxP95DeltaE00 = skinMaxP95DeltaE00
        self.skinMaxDeltaL = skinMaxDeltaL
        self.skinMaxDeltaA = skinMaxDeltaA
        self.skinMaxDeltaB = skinMaxDeltaB
        self.skinMinSaturationRatio = skinMinSaturationRatio
        self.skinMaxSaturationRatio = skinMaxSaturationRatio
        self.skinMaxHueShiftDegrees = skinMaxHueShiftDegrees
        self.skinMaxClipIncrease = skinMaxClipIncrease
        self.skinMaxNonSkinP95DeltaE00 = skinMaxNonSkinP95DeltaE00
        self.skinMaxFinalDeltaL = skinMaxFinalDeltaL
        self.skinMaxFinalDarkDeltaL = skinMaxFinalDarkDeltaL
        self.skinMaxFinalDeltaE00 = skinMaxFinalDeltaE00
        self.edgeMinMedianContrastRetention = edgeMinMedianContrastRetention
        self.edgeMinMeanContrastRetention = edgeMinMeanContrastRetention
        self.edgeMaxDegradedFraction = edgeMaxDegradedFraction
        self.edgeMaxSignFlipFraction = edgeMaxSignFlipFraction
        self.edgeMaxOvershootFraction = edgeMaxOvershootFraction
        self.edgeMinGradientEnergyRatio = edgeMinGradientEnergyRatio
    }

    /// CI defaults.
    public static let standard = PortraitMetricThresholds()
}

// MARK: - Reports

/// One measured background line.
public struct BackgroundLineMeasurement: Codable, Sendable, Equatable {
    public var label: String
    public var orientation: String
    public var sampleCount: Int
    public var maxDeviationPx: Double
    public var angleDegrees: Double
    public var meanDisplacementPx: Double
    public var isDistorted: Bool

    public init(
        label: String,
        orientation: String,
        sampleCount: Int,
        maxDeviationPx: Double,
        angleDegrees: Double,
        meanDisplacementPx: Double,
        isDistorted: Bool
    ) {
        self.label = label
        self.orientation = orientation
        self.sampleCount = sampleCount
        self.maxDeviationPx = maxDeviationPx
        self.angleDegrees = angleDegrees
        self.meanDisplacementPx = meanDisplacementPx
        self.isDistorted = isDistorted
    }
}

/// Straight-line preservation measured on the rendered pixels.
public struct BackgroundLineReport: Codable, Sendable, Equatable {
    public var lines: [BackgroundLineMeasurement]
    public var measuredLineCount: Int
    public var distortedLineCount: Int
    public var maxDeviationPx: Double
    public var maxAngleDegrees: Double
    public var failures: [String]

    public init(
        lines: [BackgroundLineMeasurement],
        measuredLineCount: Int,
        distortedLineCount: Int,
        maxDeviationPx: Double,
        maxAngleDegrees: Double,
        failures: [String]
    ) {
        self.lines = lines
        self.measuredLineCount = measuredLineCount
        self.distortedLineCount = distortedLineCount
        self.maxDeviationPx = maxDeviationPx
        self.maxAngleDegrees = maxAngleDegrees
        self.failures = failures
    }

    public var isDistorted: Bool {
        distortedLineCount > 0
    }
}

/// Skin-colour integrity measured on the retouch and final outputs.
public struct SkinToneReport: Codable, Sendable, Equatable {
    public var skinPixelCount: Int
    public var meanDeltaE00: Double
    public var p95DeltaE00: Double
    public var maxDeltaE00: Double
    public var meanDeltaL: Double
    public var meanDeltaA: Double
    public var meanDeltaB: Double
    public var saturationRatio: Double
    public var hueShiftDegrees: Double
    public var clipIncrease: Double
    public var nonSkinP95DeltaE00: Double
    public var finalMeanDeltaL: Double
    public var finalMeanDeltaE00: Double
    public var incidents: [String]

    public init(
        skinPixelCount: Int,
        meanDeltaE00: Double,
        p95DeltaE00: Double,
        maxDeltaE00: Double,
        meanDeltaL: Double,
        meanDeltaA: Double,
        meanDeltaB: Double,
        saturationRatio: Double,
        hueShiftDegrees: Double,
        clipIncrease: Double,
        nonSkinP95DeltaE00: Double,
        finalMeanDeltaL: Double,
        finalMeanDeltaE00: Double,
        incidents: [String]
    ) {
        self.skinPixelCount = skinPixelCount
        self.meanDeltaE00 = meanDeltaE00
        self.p95DeltaE00 = p95DeltaE00
        self.maxDeltaE00 = maxDeltaE00
        self.meanDeltaL = meanDeltaL
        self.meanDeltaA = meanDeltaA
        self.meanDeltaB = meanDeltaB
        self.saturationRatio = saturationRatio
        self.hueShiftDegrees = hueShiftDegrees
        self.clipIncrease = clipIncrease
        self.nonSkinP95DeltaE00 = nonSkinP95DeltaE00
        self.finalMeanDeltaL = finalMeanDeltaL
        self.finalMeanDeltaE00 = finalMeanDeltaE00
        self.incidents = incidents
    }
}

/// Silhouette and detail preservation.
public struct EdgePreservationReport: Codable, Sendable, Equatable {
    public var boundarySamples: Int
    public var meanContrastRetention: Double
    public var medianContrastRetention: Double
    public var degradedFraction: Double
    public var signFlipFraction: Double
    public var overshootFraction: Double
    public var gradientEnergyRatio: Double
    public var failures: [String]

    public init(
        boundarySamples: Int,
        meanContrastRetention: Double,
        medianContrastRetention: Double,
        degradedFraction: Double,
        signFlipFraction: Double,
        overshootFraction: Double,
        gradientEnergyRatio: Double,
        failures: [String]
    ) {
        self.boundarySamples = boundarySamples
        self.meanContrastRetention = meanContrastRetention
        self.medianContrastRetention = medianContrastRetention
        self.degradedFraction = degradedFraction
        self.signFlipFraction = signFlipFraction
        self.overshootFraction = overshootFraction
        self.gradientEnergyRatio = gradientEnergyRatio
        self.failures = failures
    }
}

/// Compact perceptual fingerprint of a rendered image.
///
/// Luma uses a 16x16 block grid, chroma an 8x8 grid. The signature is small
/// enough to commit for 100 samples while still detecting spatial drift that a
/// scalar metric would miss. It is not reversible to the source pixels.
public struct PortraitImageSignature: Codable, Sendable, Equatable {
    public var lumaGrid: Int
    public var chromaGrid: Int
    public var lumaHex: String
    public var chromaAHex: String
    public var chromaBHex: String

    public init(
        lumaGrid: Int,
        chromaGrid: Int,
        lumaHex: String,
        chromaAHex: String,
        chromaBHex: String
    ) {
        self.lumaGrid = lumaGrid
        self.chromaGrid = chromaGrid
        self.lumaHex = lumaHex
        self.chromaAHex = chromaAHex
        self.chromaBHex = chromaBHex
    }

    /// Compares two signatures. Differences are reported in 8-bit levels.
    public func compare(to other: PortraitImageSignature) -> PortraitSignatureComparison {
        let luma = Self.decode(lumaHex)
        let otherLuma = Self.decode(other.lumaHex)
        let chromaA = Self.decode(chromaAHex)
        let otherChromaA = Self.decode(other.chromaAHex)
        let chromaB = Self.decode(chromaBHex)
        let otherChromaB = Self.decode(other.chromaBHex)
        let lumaDifferences = Self.differences(luma, otherLuma)
        let chromaDifferences = Self.differences(chromaA, otherChromaA)
            + Self.differences(chromaB, otherChromaB)
        return PortraitSignatureComparison(
            meanLumaDelta: Self.mean(lumaDifferences),
            maxLumaDelta: Int(lumaDifferences.max() ?? 255),
            meanChromaDelta: Self.mean(chromaDifferences)
        )
    }

    private static func decode(_ hex: String) -> [Int] {
        var values: [Int] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let pair = hex[index..<next]
            values.append(Int(pair, radix: 16) ?? 0)
            index = next
        }
        return values
    }

    private static func differences(_ first: [Int], _ second: [Int]) -> [Int] {
        guard first.count == second.count, !first.isEmpty else { return [255] }
        return zip(first, second).map { abs($0 - $1) }
    }

    private static func mean(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}

/// Comparison result for two signatures.
public struct PortraitSignatureComparison: Sendable, Equatable, Codable {
    public var meanLumaDelta: Double
    public var maxLumaDelta: Int
    public var meanChromaDelta: Double

    public init(meanLumaDelta: Double, maxLumaDelta: Int, meanChromaDelta: Double) {
        self.meanLumaDelta = meanLumaDelta
        self.maxLumaDelta = maxLumaDelta
        self.meanChromaDelta = meanChromaDelta
    }
}

/// Flattened metrics stored in the committed baseline.
public struct PortraitSampleMetrics: Codable, Sendable, Equatable {
    public var backgroundMeasuredLines: Int
    public var backgroundDistortedLines: Int
    public var backgroundMaxDeviationPx: Double
    public var backgroundMaxAngleDegrees: Double

    public var skinPixelCount: Int
    public var skinMeanDeltaE00: Double
    public var skinP95DeltaE00: Double
    public var skinMaxDeltaE00: Double
    public var skinMeanDeltaL: Double
    public var skinMeanDeltaA: Double
    public var skinMeanDeltaB: Double
    public var skinSaturationRatio: Double
    public var skinHueShiftDegrees: Double
    public var skinClipIncrease: Double
    public var skinNonSkinP95DeltaE00: Double
    public var skinFinalMeanDeltaL: Double
    public var skinFinalMeanDeltaE00: Double

    public var edgeBoundarySamples: Int
    public var edgeMeanContrastRetention: Double
    public var edgeMedianContrastRetention: Double
    public var edgeDegradedFraction: Double
    public var edgeSignFlipFraction: Double
    public var edgeOvershootFraction: Double
    public var edgeGradientEnergyRatio: Double

    public var coverageMeanDeltaE00: Double
    public var coverageP95DeltaE00: Double
    public var finalSSIM: Double
    public var signature: PortraitImageSignature

    public init(
        backgroundMeasuredLines: Int,
        backgroundDistortedLines: Int,
        backgroundMaxDeviationPx: Double,
        backgroundMaxAngleDegrees: Double,
        skinPixelCount: Int,
        skinMeanDeltaE00: Double,
        skinP95DeltaE00: Double,
        skinMaxDeltaE00: Double,
        skinMeanDeltaL: Double,
        skinMeanDeltaA: Double,
        skinMeanDeltaB: Double,
        skinSaturationRatio: Double,
        skinHueShiftDegrees: Double,
        skinClipIncrease: Double,
        skinNonSkinP95DeltaE00: Double,
        skinFinalMeanDeltaL: Double,
        skinFinalMeanDeltaE00: Double,
        edgeBoundarySamples: Int,
        edgeMeanContrastRetention: Double,
        edgeMedianContrastRetention: Double,
        edgeDegradedFraction: Double,
        edgeSignFlipFraction: Double,
        edgeOvershootFraction: Double,
        edgeGradientEnergyRatio: Double,
        coverageMeanDeltaE00: Double,
        coverageP95DeltaE00: Double,
        finalSSIM: Double,
        signature: PortraitImageSignature
    ) {
        self.backgroundMeasuredLines = backgroundMeasuredLines
        self.backgroundDistortedLines = backgroundDistortedLines
        self.backgroundMaxDeviationPx = backgroundMaxDeviationPx
        self.backgroundMaxAngleDegrees = backgroundMaxAngleDegrees
        self.skinPixelCount = skinPixelCount
        self.skinMeanDeltaE00 = skinMeanDeltaE00
        self.skinP95DeltaE00 = skinP95DeltaE00
        self.skinMaxDeltaE00 = skinMaxDeltaE00
        self.skinMeanDeltaL = skinMeanDeltaL
        self.skinMeanDeltaA = skinMeanDeltaA
        self.skinMeanDeltaB = skinMeanDeltaB
        self.skinSaturationRatio = skinSaturationRatio
        self.skinHueShiftDegrees = skinHueShiftDegrees
        self.skinClipIncrease = skinClipIncrease
        self.skinNonSkinP95DeltaE00 = skinNonSkinP95DeltaE00
        self.skinFinalMeanDeltaL = skinFinalMeanDeltaL
        self.skinFinalMeanDeltaE00 = skinFinalMeanDeltaE00
        self.edgeBoundarySamples = edgeBoundarySamples
        self.edgeMeanContrastRetention = edgeMeanContrastRetention
        self.edgeMedianContrastRetention = edgeMedianContrastRetention
        self.edgeDegradedFraction = edgeDegradedFraction
        self.edgeSignFlipFraction = edgeSignFlipFraction
        self.edgeOvershootFraction = edgeOvershootFraction
        self.edgeGradientEnergyRatio = edgeGradientEnergyRatio
        self.coverageMeanDeltaE00 = coverageMeanDeltaE00
        self.coverageP95DeltaE00 = coverageP95DeltaE00
        self.finalSSIM = finalSSIM
        self.signature = signature
    }
}

/// Complete evaluation of one rendered sample.
public struct PortraitEvaluation: Sendable {
    public var background: BackgroundLineReport
    public var skin: SkinToneReport
    public var edge: EdgePreservationReport
    public var metrics: PortraitSampleMetrics
    public var failures: [String]

    public init(
        background: BackgroundLineReport,
        skin: SkinToneReport,
        edge: EdgePreservationReport,
        metrics: PortraitSampleMetrics,
        failures: [String]
    ) {
        self.background = background
        self.skin = skin
        self.edge = edge
        self.metrics = metrics
        self.failures = failures
    }

    public var isPassing: Bool {
        failures.isEmpty
    }
}

// MARK: - Evaluator

/// Computes the WP-25 quality metrics for one sample.
public enum PortraitMetricEvaluator {
    /// Evaluates source, retouched and final images against the scene ground
    /// truth. All three images must share the scene pixel size.
    public static func evaluate(
        scene: PortraitScene,
        source: PixelBuffer,
        retouched: PixelBuffer,
        output: PixelBuffer,
        thresholds: PortraitMetricThresholds = .standard
    ) throws -> PortraitEvaluation {
        guard source.pixelSize == scene.spec.pixelSize,
              retouched.pixelSize == scene.spec.pixelSize,
              output.pixelSize == scene.spec.pixelSize
        else {
            throw GoldenSupportError.imageSizeMismatch(
                expected: scene.spec.pixelSize,
                actual: output.pixelSize
            )
        }

        let background = try measureBackground(scene: scene, output: output, thresholds: thresholds)
        portraitTrace("PORTRAIT_TRACE background done")
        let skin = try measureSkin(
            scene: scene,
            source: source,
            retouched: retouched,
            output: output,
            thresholds: thresholds
        )
        portraitTrace("PORTRAIT_TRACE skin done")
        let edge = try measureEdges(
            scene: scene,
            source: source,
            output: output,
            thresholds: thresholds
        )
        portraitTrace("PORTRAIT_TRACE edges done")
        let coverage = try coverageDeltaE(source: source, output: output)
        portraitTrace("PORTRAIT_TRACE coverage done")
        let ssim = ImageComparator.structuralSimilarity(source, output)
        portraitTrace("PORTRAIT_TRACE ssim done")
        let signature = try signature(of: output)
        portraitTrace("PORTRAIT_TRACE signature done")

        let metrics = PortraitSampleMetrics(
            backgroundMeasuredLines: background.measuredLineCount,
            backgroundDistortedLines: background.distortedLineCount,
            backgroundMaxDeviationPx: background.maxDeviationPx,
            backgroundMaxAngleDegrees: background.maxAngleDegrees,
            skinPixelCount: skin.skinPixelCount,
            skinMeanDeltaE00: skin.meanDeltaE00,
            skinP95DeltaE00: skin.p95DeltaE00,
            skinMaxDeltaE00: skin.maxDeltaE00,
            skinMeanDeltaL: skin.meanDeltaL,
            skinMeanDeltaA: skin.meanDeltaA,
            skinMeanDeltaB: skin.meanDeltaB,
            skinSaturationRatio: skin.saturationRatio,
            skinHueShiftDegrees: skin.hueShiftDegrees,
            skinClipIncrease: skin.clipIncrease,
            skinNonSkinP95DeltaE00: skin.nonSkinP95DeltaE00,
            skinFinalMeanDeltaL: skin.finalMeanDeltaL,
            skinFinalMeanDeltaE00: skin.finalMeanDeltaE00,
            edgeBoundarySamples: edge.boundarySamples,
            edgeMeanContrastRetention: edge.meanContrastRetention,
            edgeMedianContrastRetention: edge.medianContrastRetention,
            edgeDegradedFraction: edge.degradedFraction,
            edgeSignFlipFraction: edge.signFlipFraction,
            edgeOvershootFraction: edge.overshootFraction,
            edgeGradientEnergyRatio: edge.gradientEnergyRatio,
            coverageMeanDeltaE00: coverage.mean,
            coverageP95DeltaE00: coverage.p95,
            finalSSIM: ssim,
            signature: signature
        )

        var failures: [String] = []
        failures.append(contentsOf: background.failures)
        failures.append(contentsOf: skin.incidents)
        failures.append(contentsOf: edge.failures)
        return PortraitEvaluation(
            background: background,
            skin: skin,
            edge: edge,
            metrics: metrics,
            failures: failures
        )
    }

    /// Computes the perceptual signature of one image.
    public static func signature(of pixels: PixelBuffer) throws -> PortraitImageSignature {
        let lumaGrid = 16
        let chromaGrid = 8
        var lumaValues: [Int] = []
        lumaValues.reserveCapacity(lumaGrid * lumaGrid)
        for gridY in 0 ..< lumaGrid {
            for gridX in 0 ..< lumaGrid {
                let block = blockRect(
                    gridX: gridX,
                    gridY: gridY,
                    columns: lumaGrid,
                    rows: lumaGrid,
                    width: pixels.width,
                    height: pixels.height
                )
                lumaValues.append(Int(blockAverageLuma(pixels, block).rounded()))
            }
        }

        var chromaA: [Int] = []
        var chromaB: [Int] = []
        chromaA.reserveCapacity(chromaGrid * chromaGrid)
        chromaB.reserveCapacity(chromaGrid * chromaGrid)
        for gridY in 0 ..< chromaGrid {
            for gridX in 0 ..< chromaGrid {
                let block = blockRect(
                    gridX: gridX,
                    gridY: gridY,
                    columns: chromaGrid,
                    rows: chromaGrid,
                    width: pixels.width,
                    height: pixels.height
                )
                let average = blockAverageColor(pixels, block)
                let lab = ColorScience.lab(average)
                chromaA.append(quantizedSigned(lab.a))
                chromaB.append(quantizedSigned(lab.b))
            }
        }

        return PortraitImageSignature(
            lumaGrid: lumaGrid,
            chromaGrid: chromaGrid,
            lumaHex: hex(lumaValues),
            chromaAHex: hex(chromaA),
            chromaBHex: hex(chromaB)
        )
    }

    // MARK: Background lines

    private static func measureBackground(
        scene: PortraitScene,
        output: PixelBuffer,
        thresholds: PortraitMetricThresholds
    ) throws -> BackgroundLineReport {
        let width = output.width
        let height = output.height
        let person = MaskOperations.bytes(scene.groundTruth.personMask)
        let radius = max(4, Int(0.02 * Double(min(width, height)).rounded()))
        var measurements: [BackgroundLineMeasurement] = []
        for line in scene.groundTruth.lines {
            portraitTrace("line \(line.label)")
            let measurement: BackgroundLineMeasurement?
            switch line.orientation {
            case .vertical:
                measurement = measureVerticalLine(
                    line,
                    buffer: output,
                    person: person,
                    radius: radius,
                    thresholds: thresholds
                )
            case .horizontal:
                measurement = measureHorizontalLine(
                    line,
                    buffer: output,
                    person: person,
                    radius: radius,
                    thresholds: thresholds
                )
            }
            if let measurement {
                measurements.append(measurement)
            }
        }
        let measuredLines = measurements
        let distorted = measuredLines.filter(\.isDistorted)
        var failures: [String] = []
        for line in distorted {
            failures.append(
                "background.\(line.label) deviation "
                    + String(
                        format: "%.2f px > %.2f px (angle %.2f deg)",
                        line.maxDeviationPx,
                        thresholds.backgroundMaxDeviationPx,
                        line.angleDegrees
                    )
            )
        }
        let maxDeviation = measuredLines.map(\.maxDeviationPx).max() ?? 0
        let maxAngle = measuredLines.map { abs($0.angleDegrees) }.max() ?? 0
        return BackgroundLineReport(
            lines: measurements,
            measuredLineCount: measuredLines.count,
            distortedLineCount: distorted.count,
            maxDeviationPx: maxDeviation,
            maxAngleDegrees: maxAngle,
            failures: failures
        )
    }

    private static func measureVerticalLine(
        _ line: PortraitGroundTruthLine,
        buffer: PixelBuffer,
        person: [UInt8],
        radius: Int,
        thresholds: PortraitMetricThresholds
    ) -> BackgroundLineMeasurement? {
        let width = buffer.width
        let height = buffer.height
        let center = line.position * Double(width)
        let startY = max(1, Int(line.start * Double(height)))
        let endY = min(height - 2, Int(line.end * Double(height)))
        guard startY < endY else { return nil }
        let centerX = Int(center.rounded())
        let lower = max(1, centerX - radius)
        let upper = min(width - 2, centerX + radius)
        guard lower + 2 < upper else { return nil }

        var samples: [(t: Double, position: Double)] = []
        for y in startY ... endY {
            if line.label == "door.right" {
                portraitTrace("dr y \(y)")
            }
            if hasPerson(person: person, width: width, xRange: (lower - 2)...(upper + 2), yRange: y...y) {
                continue
            }
            if line.label == "door.right", y < 30 {
                portraitTrace("dr person \(y)")
            }
            var profile: [Double] = []
            profile.reserveCapacity(upper - lower + 1)
            for x in lower ... upper {
                profile.append(luma(buffer[x, y].color))
            }
            if line.label == "door.right", y < 30 {
                portraitTrace("dr profile \(y) \(profile.count)")
            }
            guard let position = extremumPosition(
                profile: profile,
                startIndex: lower,
                minimumContrast: 8,
                expected: center
            ) else {
                continue
            }
            if line.label == "door.right", y < 30 {
                portraitTrace("dr ext \(y) \(position)")
            }
            samples.append((Double(y), position))
        }
        if line.label == "door.right" {
            portraitTrace("vline \(line.label) samples \(samples.count)")
        }
        return makeMeasurement(
            line: line,
            samples: samples,
            expected: center,
            axisSpan: Double(endY - startY),
            thresholds: thresholds
        )
    }

    private static func measureHorizontalLine(
        _ line: PortraitGroundTruthLine,
        buffer: PixelBuffer,
        person: [UInt8],
        radius: Int,
        thresholds: PortraitMetricThresholds
    ) -> BackgroundLineMeasurement? {
        let width = buffer.width
        let height = buffer.height
        let center = line.position * Double(height)
        let startX = max(1, Int(line.start * Double(width)))
        let endX = min(width - 2, Int(line.end * Double(width)))
        guard startX < endX else { return nil }
        let centerY = Int(center.rounded())
        let lower = max(1, centerY - radius)
        let upper = min(height - 2, centerY + radius)
        guard lower + 2 < upper else { return nil }

        var samples: [(t: Double, position: Double)] = []
        for x in startX ... endX {
            if hasPerson(
                person: person,
                width: width,
                xRange: x...x,
                yRange: (lower - 2)...(upper + 2)
            ) {
                continue
            }
            var profile: [Double] = []
            profile.reserveCapacity(upper - lower + 1)
            for y in lower ... upper {
                profile.append(luma(buffer[x, y].color))
            }
            guard let position = extremumPosition(
                profile: profile,
                startIndex: lower,
                minimumContrast: 8,
                expected: center
            ) else {
                continue
            }
            samples.append((Double(x), position))
        }
        return makeMeasurement(
            line: line,
            samples: samples,
            expected: center,
            axisSpan: Double(endX - startX),
            thresholds: thresholds
        )
    }

    private static func makeMeasurement(
        line: PortraitGroundTruthLine,
        samples: [(t: Double, position: Double)],
        expected: Double,
        axisSpan: Double,
        thresholds: PortraitMetricThresholds
    ) -> BackgroundLineMeasurement? {
        guard samples.count >= 8, axisSpan > 0 else { return nil }
        let first = samples.first?.t ?? 0
        let last = samples.last?.t ?? 0
        guard last - first >= axisSpan * 0.12 else { return nil }

        var sumT = 0.0
        var sumV = 0.0
        for sample in samples {
            sumT += sample.t
            sumV += sample.position
        }
        let count = Double(samples.count)
        let meanT = sumT / count
        let meanV = sumV / count
        var covariance = 0.0
        var variance = 0.0
        for sample in samples {
            let dt = sample.t - meanT
            covariance += dt * (sample.position - meanV)
            variance += dt * dt
        }
        guard variance > 1e-9 else { return nil }
        let slope = covariance / variance
        let intercept = meanV - slope * meanT
        var deviations: [Double] = []
        deviations.reserveCapacity(samples.count)
        var displacement = 0.0
        for sample in samples {
            let fitted = slope * sample.t + intercept
            deviations.append(abs(sample.position - fitted))
            displacement += sample.position - expected
        }
        deviations.sort()
        // Crossings with a perpendicular structure make the local extremum
        // ambiguous for one or two samples. The robust maximum is the 95th
        // percentile: a genuinely bowed line deviates on most samples, while an
        // isolated crossing must not fail a sample.
        let robustMaxDeviation = percentile(deviations, fraction: 0.95)
        displacement /= count
        let angle = atan(slope) * 180 / Double.pi
        let distorted = robustMaxDeviation > thresholds.backgroundMaxDeviationPx
            || abs(angle) > thresholds.backgroundMaxAngleDegrees
        return BackgroundLineMeasurement(
            label: line.label,
            orientation: line.orientation.rawValue,
            sampleCount: samples.count,
            maxDeviationPx: robustMaxDeviation,
            angleDegrees: angle,
            meanDisplacementPx: displacement,
            isDistorted: distorted
        )
    }

    /// Finds the darkest or brightest pixel of a 1-D profile and interpolates
    /// the extremum with a parabola. Returns the position in buffer coordinates.
    private static func extremumPosition(
        profile: [Double],
        startIndex: Int,
        minimumContrast: Double,
        expected: Double
    ) -> Double? {
        guard profile.count >= 3 else { return nil }
        var mean = 0.0
        for value in profile { mean += value }
        mean /= Double(profile.count)
        var minIndex = 0
        var maxIndex = 0
        for index in 1 ..< profile.count {
            if profile[index] < profile[minIndex] { minIndex = index }
            if profile[index] > profile[maxIndex] { maxIndex = index }
        }
        let candidates: [(index: Int, contrast: Double)] = [
            (minIndex, abs(profile[minIndex] - mean)),
            (maxIndex, abs(profile[maxIndex] - mean))
        ].filter { $0.contrast >= minimumContrast }
        guard let peak = candidates.min(by: { lhs, rhs in
            let leftDistance = abs(Double(startIndex + lhs.index) + 0.5 - expected)
            let rightDistance = abs(Double(startIndex + rhs.index) + 0.5 - expected)
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            return lhs.contrast > rhs.contrast
        }) else {
            return nil
        }
        let peakIndex = peak.index
        let left = profile[peakIndex - 1]
        let centerValue = profile[peakIndex]
        let right = profile[peakIndex + 1]
        let denominator = left - 2 * centerValue + right
        var offset = 0.0
        if abs(denominator) > 1e-9 {
            offset = 0.5 * (left - right) / denominator
        }
        offset = min(max(offset, -1), 1)
        return Double(startIndex + peakIndex) + 0.5 + offset
    }

    private static func hasPerson(
        person: [UInt8],
        width: Int,
        xRange: ClosedRange<Int>,
        yRange: ClosedRange<Int>
    ) -> Bool {
        let lowerX = max(0, xRange.lowerBound)
        let upperX = min(width - 1, xRange.upperBound)
        guard lowerX <= upperX else { return false }
        for y in yRange where y >= 0 && y < person.count / width {
            let row = y * width
            for x in lowerX ... upperX where person[row + x] > 0 {
                return true
            }
        }
        return false
    }

    // MARK: Skin

    private static func measureSkin(
        scene: PortraitScene,
        source: PixelBuffer,
        retouched: PixelBuffer,
        output: PixelBuffer,
        thresholds: PortraitMetricThresholds
    ) throws -> SkinToneReport {
        portraitTrace("skin start")
        let eroded = try MaskOperations.eroded(scene.groundTruth.skinMask, radius: 2)
        let skinBytes = MaskOperations.bytes(eroded)
        let skinMaskBytes = MaskOperations.bytes(scene.groundTruth.skinMask)
        let personBytes = MaskOperations.bytes(scene.groundTruth.personMask)
        let width = source.width
        let height = source.height
        var finalRegion = [Bool](repeating: false, count: width * height)
        if let face = scene.groundTruth.primaryFaceBox {
            let insetX = face.width * 0.12
            let insetY = face.height * 0.12
            let minX = max(0, Int((face.x + insetX) * Double(width)))
            let maxX = min(width - 1, Int((face.maxX - insetX) * Double(width)))
            let minY = max(0, Int((face.y + insetY) * Double(height)))
            let maxY = min(height - 1, Int((face.maxY - insetY) * Double(height)))
            if minX < maxX, minY < maxY {
                for y in minY ... maxY {
                    for x in minX ... maxX {
                        finalRegion[y * width + x] = true
                    }
                }
            }
        }

        var skinPixelCount = 0
        var deltaValues: [Double] = []
        var sumSourceL = 0.0
        var sumSourceA = 0.0
        var sumSourceB = 0.0
        var sumRetouchedL = 0.0
        var sumRetouchedA = 0.0
        var sumRetouchedB = 0.0
        var sumSaturationSource = 0.0
        var sumSaturationRetouched = 0.0
        var hueVectorSource = SIMD2<Double>(0, 0)
        var hueVectorRetouched = SIMD2<Double>(0, 0)
        var sourceClip = 0
        var retouchedClip = 0
        var finalDeltaValues: [Double] = []
        var finalDeltaLTotal = 0.0
        var finalCount = 0

        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = y * width + x
                guard skinBytes[index] > 0 else { continue }
                let sourcePixel = source[x, y]
                let retouchedPixel = retouched[x, y]
                let sourceLab = ColorScience.lab(sourcePixel.color)
                let retouchedLab = ColorScience.lab(retouchedPixel.color)
                let delta = ColorScience.deltaE00(sourceLab, retouchedLab)
                deltaValues.append(delta)
                skinPixelCount += 1

                sumSourceL += sourceLab.l
                sumSourceA += sourceLab.a
                sumSourceB += sourceLab.b
                sumRetouchedL += retouchedLab.l
                sumRetouchedA += retouchedLab.a
                sumRetouchedB += retouchedLab.b

                let sourceSaturation = (sourceLab.a * sourceLab.a + sourceLab.b * sourceLab.b).squareRoot()
                let retouchedSaturation = (retouchedLab.a * retouchedLab.a + retouchedLab.b * retouchedLab.b).squareRoot()
                sumSaturationSource += sourceSaturation
                sumSaturationRetouched += retouchedSaturation
                let sourceAngle = atan2(sourceLab.b, sourceLab.a)
                let retouchedAngle = atan2(retouchedLab.b, retouchedLab.a)
                hueVectorSource.x += cos(sourceAngle) * sourceSaturation
                hueVectorSource.y += sin(sourceAngle) * sourceSaturation
                hueVectorRetouched.x += cos(retouchedAngle) * retouchedSaturation
                hueVectorRetouched.y += sin(retouchedAngle) * retouchedSaturation

                if isClipped(sourcePixel.color) { sourceClip += 1 }
                if isClipped(retouchedPixel.color) { retouchedClip += 1 }

                if finalRegion[index], skinMaskBytes[index] > 0 {
                    let finalLab = ColorScience.lab(output[x, y].color)
                    finalDeltaValues.append(ColorScience.deltaE00(sourceLab, finalLab))
                    finalDeltaLTotal += finalLab.l - sourceLab.l
                    finalCount += 1
                }
            }
        }

        guard skinPixelCount > 0 else {
            return SkinToneReport(
                skinPixelCount: 0,
                meanDeltaE00: 0,
                p95DeltaE00: 0,
                maxDeltaE00: 0,
                meanDeltaL: 0,
                meanDeltaA: 0,
                meanDeltaB: 0,
                saturationRatio: 1,
                hueShiftDegrees: 0,
                clipIncrease: 0,
                nonSkinP95DeltaE00: 0,
                finalMeanDeltaL: 0,
                finalMeanDeltaE00: 0,
                incidents: ["skin.mask empty"]
            )
        }

        let count = Double(skinPixelCount)
        let meanSourceL = sumSourceL / count
        let meanSourceA = sumSourceA / count
        let meanSourceB = sumSourceB / count
        let meanRetouchedL = sumRetouchedL / count
        let meanRetouchedA = sumRetouchedA / count
        let meanRetouchedB = sumRetouchedB / count
        let deltaSorted = deltaValues.sorted()
        let meanDelta = deltaValues.isEmpty ? 0 : deltaValues.reduce(0, +) / Double(deltaValues.count)
        let p95Delta = percentile(deltaSorted, fraction: 0.95)
        let maxDelta = deltaSorted.last ?? 0
        let saturationSource = sumSaturationSource / count
        let saturationRetouched = sumSaturationRetouched / count
        let saturationRatio = saturationSource > 1e-6 ? saturationRetouched / saturationSource : 1
        let sourceHue = atan2(hueVectorSource.y, hueVectorSource.x) * 180 / Double.pi
        let retouchedHue = atan2(hueVectorRetouched.y, hueVectorRetouched.x) * 180 / Double.pi
        var hueShift = retouchedHue - sourceHue
        while hueShift > 180 { hueShift -= 360 }
        while hueShift < -180 { hueShift += 360 }
        let clipIncrease = Double(retouchedClip - sourceClip) / count

        var nonSkinDeltaValues: [Double] = []
        var sampleIndex = 0
        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = y * width + x
                sampleIndex += 1
                guard personBytes[index] > 0, skinMaskBytes[index] == 0 else { continue }
                if sampleIndex % 3 != 0 { continue }
                let delta = ColorScience.deltaE00(
                    source[x, y].color,
                    retouched[x, y].color
                )
                nonSkinDeltaValues.append(delta)
            }
        }
        let nonSkinP95 = percentile(nonSkinDeltaValues.sorted(), fraction: 0.95)

        let finalMeanDeltaL = finalCount > 0 ? finalDeltaLTotal / Double(finalCount) : 0
        let finalMeanDeltaE = finalDeltaValues.isEmpty
            ? 0
            : finalDeltaValues.reduce(0, +) / Double(finalDeltaValues.count)

        var incidents: [String] = []
        if meanDelta > thresholds.skinMaxMeanDeltaE00 {
            incidents.append(String(format: "skin.meanDeltaE00 %.3f > %.3f", meanDelta, thresholds.skinMaxMeanDeltaE00))
        }
        if p95Delta > thresholds.skinMaxP95DeltaE00 {
            incidents.append(String(format: "skin.p95DeltaE00 %.3f > %.3f", p95Delta, thresholds.skinMaxP95DeltaE00))
        }
        if abs(meanRetouchedL - meanSourceL) > thresholds.skinMaxDeltaL {
            incidents.append(
                String(
                    format: "skin.meanDeltaL %.3f > %.3f",
                    meanRetouchedL - meanSourceL,
                    thresholds.skinMaxDeltaL
                )
            )
        }
        if abs(meanRetouchedA - meanSourceA) > thresholds.skinMaxDeltaA {
            incidents.append(
                String(
                    format: "skin.meanDeltaA %.3f > %.3f",
                    meanRetouchedA - meanSourceA,
                    thresholds.skinMaxDeltaA
                )
            )
        }
        if abs(meanRetouchedB - meanSourceB) > thresholds.skinMaxDeltaB {
            incidents.append(
                String(
                    format: "skin.meanDeltaB %.3f > %.3f",
                    meanRetouchedB - meanSourceB,
                    thresholds.skinMaxDeltaB
                )
            )
        }
        if saturationRatio < thresholds.skinMinSaturationRatio {
            incidents.append(String(format: "skin.saturationRatio %.4f < %.4f", saturationRatio, thresholds.skinMinSaturationRatio))
        }
        if saturationRatio > thresholds.skinMaxSaturationRatio {
            incidents.append(String(format: "skin.saturationRatio %.4f > %.4f", saturationRatio, thresholds.skinMaxSaturationRatio))
        }
        if abs(hueShift) > thresholds.skinMaxHueShiftDegrees {
            incidents.append(String(format: "skin.hueShift %.2f deg > %.2f deg", hueShift, thresholds.skinMaxHueShiftDegrees))
        }
        if clipIncrease > thresholds.skinMaxClipIncrease {
            incidents.append(String(format: "skin.clipIncrease %.4f > %.4f", clipIncrease, thresholds.skinMaxClipIncrease))
        }
        if nonSkinP95 > thresholds.skinMaxNonSkinP95DeltaE00 {
            incidents.append(String(format: "skin.nonSkinP95DeltaE00 %.3f > %.3f", nonSkinP95, thresholds.skinMaxNonSkinP95DeltaE00))
        }
        if abs(finalMeanDeltaL) > thresholds.skinMaxFinalDeltaL {
            incidents.append(
                String(
                    format: "skin.finalMeanDeltaL %.3f > %.3f",
                    finalMeanDeltaL,
                    thresholds.skinMaxFinalDeltaL
                )
            )
        }
        if scene.spec.primarySubject.skinTone.rawValue >= SkinToneBand.v.rawValue,
           finalMeanDeltaL > thresholds.skinMaxFinalDarkDeltaL
        {
            incidents.append(
                String(
                    format: "skin.darkFinalDeltaL %.3f > %.3f",
                    finalMeanDeltaL,
                    thresholds.skinMaxFinalDarkDeltaL
                )
            )
        }
        if finalMeanDeltaE > thresholds.skinMaxFinalDeltaE00 {
            incidents.append(
                String(
                    format: "skin.finalMeanDeltaE00 %.3f > %.3f",
                    finalMeanDeltaE,
                    thresholds.skinMaxFinalDeltaE00
                )
            )
        }

        return SkinToneReport(
            skinPixelCount: skinPixelCount,
            meanDeltaE00: meanDelta,
            p95DeltaE00: p95Delta,
            maxDeltaE00: maxDelta,
            meanDeltaL: meanRetouchedL - meanSourceL,
            meanDeltaA: meanRetouchedA - meanSourceA,
            meanDeltaB: meanRetouchedB - meanSourceB,
            saturationRatio: saturationRatio,
            hueShiftDegrees: hueShift,
            clipIncrease: clipIncrease,
            nonSkinP95DeltaE00: nonSkinP95,
            finalMeanDeltaL: finalMeanDeltaL,
            finalMeanDeltaE00: finalMeanDeltaE,
            incidents: incidents
        )
    }

    private static func isClipped(_ color: RGB8) -> Bool {
        color.red >= 250 || color.green >= 250 || color.blue >= 250
            || color.red <= 5 || color.green <= 5 || color.blue <= 5
    }

    // MARK: Edges

    private static func measureEdges(
        scene: PortraitScene,
        source: PixelBuffer,
        output: PixelBuffer,
        thresholds: PortraitMetricThresholds
    ) throws -> EdgePreservationReport {
        portraitTrace("edges start")
        let mask = scene.groundTruth.personMask
        let boundary = MaskOperations.boundaryPoints(mask)
        if source.isIdentical(to: output) {
            return EdgePreservationReport(
                boundarySamples: boundary.count,
                meanContrastRetention: 1,
                medianContrastRetention: 1,
                degradedFraction: 0,
                signFlipFraction: 0,
                overshootFraction: 0,
                gradientEnergyRatio: 1,
                failures: []
            )
        }
        let maskBytes = MaskOperations.bytes(mask)
        let stride = max(1, boundary.count / 320)
        var ratios: [Double] = []
        var gradientSource = 0.0
        var gradientFinal = 0.0
        var degraded = 0
        var signFlips = 0
        var overshoot = 0
        var used = 0

        for (index, point) in boundary.enumerated() where index % stride == 0 {
            guard let normal = outwardNormal(maskBytes, mask.width, mask.height, point.x, point.y) else {
                continue
            }
            let sourceContrast = contrast(
                source,
                x: Double(point.x) + 0.5,
                y: Double(point.y) + 0.5,
                normal: normal
            )
            guard abs(sourceContrast) > 6 else { continue }
            let extendedRadius = max(10, min(output.width, output.height) / 20)
            let local = bestEdgeCandidate(
                output: output,
                pointX: Double(point.x) + 0.5,
                pointY: Double(point.y) + 0.5,
                normal: normal,
                sourceContrast: sourceContrast,
                shifts: -6 ... 6
            )
            used += 1
            let chosen: (shift: Int, contrast: Double)?
            if let local, abs(local.contrast) / abs(sourceContrast) >= 0.5 {
                chosen = local
            } else {
                chosen = bestEdgeCandidate(
                    output: output,
                    pointX: Double(point.x) + 0.5,
                    pointY: Double(point.y) + 0.5,
                    normal: normal,
                    sourceContrast: sourceContrast,
                    shifts: -extendedRadius ... extendedRadius
                ) ?? local
            }
            guard let chosen else {
                ratios.append(0)
                degraded += 1
                signFlips += 1
                continue
            }
            let ratio = abs(chosen.contrast) / abs(sourceContrast)
            ratios.append(ratio)
            if ratio < 0.5 { degraded += 1 }
            if ratio > 2.5 { overshoot += 1 }
            gradientSource += gradientMagnitude(
                source,
                x: Double(point.x) + 0.5,
                y: Double(point.y) + 0.5
            )
            gradientFinal += gradientMagnitude(
                output,
                x: Double(point.x) + 0.5 + normal.x * Double(chosen.shift),
                y: Double(point.y) + 0.5 + normal.y * Double(chosen.shift)
            )
        }

        let sortedRatios = ratios.sorted()
        let meanRatio = ratios.isEmpty ? 0 : ratios.reduce(0, +) / Double(ratios.count)
        let medianRatio = percentile(sortedRatios, fraction: 0.5)
        let degradedFraction = used > 0 ? Double(degraded) / Double(used) : 0
        let signFlipFraction = used > 0 ? Double(signFlips) / Double(used) : 0
        let overshootFraction = used > 0 ? Double(overshoot) / Double(used) : 0
        let gradientRatio = gradientSource > 1e-6 ? gradientFinal / gradientSource : 1

        var failures: [String] = []
        if used < 20 {
            failures.append("edge.boundary samples \(used) < 20")
        }
        if medianRatio < thresholds.edgeMinMedianContrastRetention {
            failures.append(String(format: "edge.medianContrastRetention %.3f < %.3f", medianRatio, thresholds.edgeMinMedianContrastRetention))
        }
        if meanRatio < thresholds.edgeMinMeanContrastRetention {
            failures.append(String(format: "edge.meanContrastRetention %.3f < %.3f", meanRatio, thresholds.edgeMinMeanContrastRetention))
        }
        if degradedFraction > thresholds.edgeMaxDegradedFraction {
            failures.append(String(format: "edge.degradedFraction %.3f > %.3f", degradedFraction, thresholds.edgeMaxDegradedFraction))
        }
        if signFlipFraction > thresholds.edgeMaxSignFlipFraction {
            failures.append(String(format: "edge.signFlipFraction %.3f > %.3f", signFlipFraction, thresholds.edgeMaxSignFlipFraction))
        }
        if overshootFraction > thresholds.edgeMaxOvershootFraction {
            failures.append(String(format: "edge.overshootFraction %.3f > %.3f", overshootFraction, thresholds.edgeMaxOvershootFraction))
        }
        if gradientRatio < thresholds.edgeMinGradientEnergyRatio {
            failures.append(String(format: "edge.gradientEnergyRatio %.3f < %.3f", gradientRatio, thresholds.edgeMinGradientEnergyRatio))
        }

        return EdgePreservationReport(
            boundarySamples: used,
            meanContrastRetention: meanRatio,
            medianContrastRetention: medianRatio,
            degradedFraction: degradedFraction,
            signFlipFraction: signFlipFraction,
            overshootFraction: overshootFraction,
            gradientEnergyRatio: gradientRatio,
            failures: failures
        )
    }

    /// Picks a same-sign edge candidate near the expected silhouette point.
    ///
    /// The strongest candidate is reduced to the closest shift that still has at
    /// least 90 % of its contrast, so a nearby stronger fold cannot win just by
    /// being stronger. Large intentional moves (leg lengthening) are found by
    /// the caller's second, wider search.
    private static func bestEdgeCandidate(
        output: PixelBuffer,
        pointX: Double,
        pointY: Double,
        normal: SIMD2<Double>,
        sourceContrast: Double,
        shifts: ClosedRange<Int>
    ) -> (shift: Int, contrast: Double)? {
        var candidates: [(shift: Int, contrast: Double)] = []
        candidates.reserveCapacity(shifts.count)
        for shift in shifts {
            let value = contrast(
                output,
                x: pointX + normal.x * Double(shift),
                y: pointY + normal.y * Double(shift),
                normal: normal
            )
            if value * sourceContrast > 0 {
                candidates.append((shift: shift, contrast: value))
            }
        }
        guard let strongest = candidates.max(by: { abs($0.contrast) < abs($1.contrast) }) else {
            return nil
        }
        let threshold = abs(strongest.contrast) * 0.90
        return candidates
            .filter { abs($0.contrast) >= threshold }
            .min { abs($0.shift) < abs($1.shift) } ?? strongest
    }

    private static func outwardNormal(
        _ mask: [UInt8],
        _ width: Int,
        _ height: Int,
        _ x: Int,
        _ y: Int
    ) -> SIMD2<Double>? {
        var gx = 0.0
        var gy = 0.0
        for offsetY in -3 ... 3 {
            for offsetX in -3 ... 3 {
                let sampleX = x + offsetX
                let sampleY = y + offsetY
                guard sampleX >= 0, sampleX < width, sampleY >= 0, sampleY < height else { continue }
                guard mask[sampleY * width + sampleX] > 0 else { continue }
                gx += Double(offsetX)
                gy += Double(offsetY)
            }
        }
        let length = (gx * gx + gy * gy).squareRoot()
        guard length > 1e-6 else { return nil }
        return SIMD2<Double>(-gx / length, -gy / length)
    }

    private static func contrast(
        _ buffer: PixelBuffer,
        x: Double,
        y: Double,
        normal: SIMD2<Double>
    ) -> Double {
        let inside = bilinearLuma(buffer, x: x - normal.x * 3, y: y - normal.y * 3)
        let outside = bilinearLuma(buffer, x: x + normal.x * 3, y: y + normal.y * 3)
        return inside - outside
    }

    private static func gradientMagnitude(_ buffer: PixelBuffer, x: Double, y: Double) -> Double {
        let dx = bilinearLuma(buffer, x: x + 1, y: y) - bilinearLuma(buffer, x: x - 1, y: y)
        let dy = bilinearLuma(buffer, x: x, y: y + 1) - bilinearLuma(buffer, x: x, y: y - 1)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func bilinearLuma(_ buffer: PixelBuffer, x: Double, y: Double) -> Double {
        let clampedX = min(max(x, 0), Double(buffer.width - 1))
        let clampedY = min(max(y, 0), Double(buffer.height - 1))
        let x0 = Int(floor(clampedX))
        let y0 = Int(floor(clampedY))
        let x1 = min(buffer.width - 1, x0 + 1)
        let y1 = min(buffer.height - 1, y0 + 1)
        let fx = clampedX - Double(x0)
        let fy = clampedY - Double(y0)
        let top = luma(buffer[x0, y0].color) * (1 - fx) + luma(buffer[x1, y0].color) * fx
        let bottom = luma(buffer[x0, y1].color) * (1 - fx) + luma(buffer[x1, y1].color) * fx
        return top * (1 - fy) + bottom * fy
    }

    // MARK: Coverage ΔE / SSIM helpers

    private static func coverageDeltaE(
        source: PixelBuffer,
        output: PixelBuffer
    ) throws -> (mean: Double, p95: Double) {
        guard source.width == output.width, source.height == output.height else {
            throw GoldenSupportError.imageSizeMismatch(
                expected: source.pixelSize,
                actual: output.pixelSize
            )
        }
        let stride = max(2, min(source.width, source.height) / 90)
        var values: [Double] = []
        values.reserveCapacity((source.width / stride + 1) * (source.height / stride + 1))
        var y = 0
        while y < source.height {
            var x = 0
            while x < source.width {
                values.append(
                    ColorScience.deltaE00(source[x, y].color, output[x, y].color)
                )
                x += stride
            }
            y += stride
        }
        guard !values.isEmpty else { return (0, 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        values.sort()
        return (mean, percentile(values, fraction: 0.95))
    }

    // MARK: Signature helpers

    private static func blockRect(
        gridX: Int,
        gridY: Int,
        columns: Int,
        rows: Int,
        width: Int,
        height: Int
    ) -> PixelRect {
        let minX = gridX * width / columns
        let maxX = (gridX + 1) * width / columns
        let minY = gridY * height / rows
        let maxY = (gridY + 1) * height / rows
        return PixelRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        ).clamped(width: width, height: height)
    }

    private static func blockAverageLuma(_ buffer: PixelBuffer, _ rect: PixelRect) -> Double {
        guard rect.area > 0 else { return 0 }
        var total = 0.0
        for y in rect.y ..< rect.maxY {
            for x in rect.x ..< rect.maxX {
                total += luma(buffer[x, y].color)
            }
        }
        return total / Double(rect.area)
    }

    private static func blockAverageColor(_ buffer: PixelBuffer, _ rect: PixelRect) -> RGB8 {
        guard rect.area > 0 else { return .black }
        var red = 0
        var green = 0
        var blue = 0
        for y in rect.y ..< rect.maxY {
            for x in rect.x ..< rect.maxX {
                let pixel = buffer[x, y]
                red += Int(pixel.red)
                green += Int(pixel.green)
                blue += Int(pixel.blue)
            }
        }
        let count = max(1, rect.area)
        return RGB8(
            red: UInt8(min(255, red / count)),
            green: UInt8(min(255, green / count)),
            blue: UInt8(min(255, blue / count))
        )
    }

    private static func quantizedSigned(_ value: Double) -> Int {
        Int(min(max((value + 128).rounded(), 0), 255))
    }

    private static func hex(_ values: [Int]) -> String {
        var text = ""
        text.reserveCapacity(values.count * 2)
        for value in values {
            text += String(format: "%02X", min(max(value, 0), 255))
        }
        return text
    }

    // MARK: Colour helpers

    private static func luma(_ color: RGB8) -> Double {
        color.luma
    }

    private static func percentile(_ sortedValues: [Double], fraction: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        let rank = Int((clamped * Double(sortedValues.count)).rounded(.up))
        let index = min(max(rank - 1, 0), sortedValues.count - 1)
        return sortedValues[index]
    }
}
