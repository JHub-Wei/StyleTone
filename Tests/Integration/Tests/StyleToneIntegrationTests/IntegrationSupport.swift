import CryptoKit
import Foundation
import GoldenSupport
import StyleToneCore
import StyleToneGeometry
import StyleToneImaging
import StyleToneRetouch
import TestShared
import XCTest

// MARK: - Environment

/// Repository paths and the artifact directory for the integration suite.
struct IntegrationEnvironment: Sendable {
    let repositoryRoot: URL
    let corpusURL: URL
    let baselineURL: URL
    let goldensDirectory: URL
    let artifactsDirectory: URL
    let isCI: Bool

    init() throws {
        let environment = TestEnvironment()
        repositoryRoot = try environment.requireRepositoryRoot()
        let integration = repositoryRoot.appendingPathComponent(
            "Tests/Integration",
            isDirectory: true
        )
        corpusURL = integration.appendingPathComponent("Corpus/portrait-corpus.json")
        baselineURL = integration.appendingPathComponent("Baselines/portrait-baseline.json")
        goldensDirectory = integration.appendingPathComponent("Goldens", isDirectory: true)
        if let override = ProcessInfo.processInfo.environment["ST_GOLDEN_ARTIFACTS_DIR"],
           !override.isEmpty
        {
            artifactsDirectory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            artifactsDirectory = repositoryRoot
                .appendingPathComponent(".build", isDirectory: true)
                .appendingPathComponent("golden-artifacts", isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: artifactsDirectory,
            withIntermediateDirectories: true
        )
        isCI = environment.isCI
    }

    var baselineExists: Bool {
        FileManager.default.fileExists(atPath: baselineURL.path)
    }

    var goldensExist: Bool {
        FileManager.default.fileExists(atPath: goldensDirectory.path)
    }

    /// Loads and validates the corpus.
    func loadCorpus() throws -> (corpus: PortraitCorpus, data: Data) {
        let data = try Data(contentsOf: corpusURL)
        let corpus = try PortraitCorpus.decode(data)
        try corpus.validate()
        try corpus.validateCoverage()
        return (corpus, data)
    }

    /// Loads and validates the committed baseline against the corpus.
    func loadBaseline(corpus: PortraitCorpus) throws -> PortraitBaseline? {
        guard baselineExists else { return nil }
        let data = try Data(contentsOf: baselineURL)
        let baseline = try PortraitBaseline.decode(data)
        try baseline.validate(corpus: corpus)
        return baseline
    }

    /// Writes an artifact into the run directory and returns its URL.
    @discardableResult
    func write(_ data: Data, name: String) throws -> URL {
        let url = artifactsDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func write(_ text: String, name: String) throws -> URL {
        try write(Data(text.utf8), name: name)
    }

    /// Adds a keep-always XCTest attachment. SwiftPM CI exports these from the
    /// xcresult bundle; the same files are also copied to the artifact directory.
    func attach(
        _ data: Data,
        name: String,
        uniformTypeIdentifier: String,
        to testCase: XCTestCase
    ) {
        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: uniformTypeIdentifier
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Pipeline

/// Parameters used for every corpus sample. They are fixed so a metric change
/// can only come from the algorithms, not from a different slider position.
struct PortraitPipelineParameters: Sendable {
    let geometry: GeometryParameters
    let skin: SkinParameters

    static func make(for framing: PortraitFraming) -> PortraitPipelineParameters {
        // Evenness is deliberately disabled for the golden corpus.
        //
        // WP-25 found that `LowFrequencyField.make` downsamples through a
        // Core Graphics bitmap context without flipping its CTM, so the reduced
        // field is vertically mirrored relative to the full-resolution image.
        // Uniform WP-07 fixtures do not notice; a real portrait is pulled
        // towards whatever is mirrored below it (dark skin gets a pale,
        // desaturated cast). The defect is filed against WP-07; until it is
        // fixed the golden suite exercises smoothing only. Re-enable
        // `evenness: 0.35` here once WP-07 flips the reduced image.
        let skin = SkinParameters(smoothing: 0.55, evenness: 0)
        switch framing {
        case .headshot:
            return PortraitPipelineParameters(
                geometry: GeometryParameters(
                    face: FaceParameters(slim: 0.40, jaw: 0.25),
                    body: .neutral,
                    backgroundProtection: true
                ),
                skin: skin
            )
        case .halfBody:
            return PortraitPipelineParameters(
                geometry: GeometryParameters(
                    face: FaceParameters(slim: 0.35, jaw: 0.20),
                    body: BodyParameters(arm: 0.30, waist: 0.35, leg: 0, legLength: 1.0),
                    backgroundProtection: true
                ),
                skin: skin
            )
        case .fullBody:
            return PortraitPipelineParameters(
                geometry: GeometryParameters(
                    face: FaceParameters(slim: 0.35, jaw: 0.20),
                    body: BodyParameters(arm: 0.30, waist: 0.35, leg: 0.25, legLength: 1.08),
                    backgroundProtection: true
                ),
                skin: skin
            )
        }
    }
}

struct PortraitPipelineOutput: Sendable {
    let source: PixelBuffer
    let retouched: PixelBuffer
    let output: PixelBuffer
    let durationSeconds: Double
}

/// Composes the real retouch and geometry engines exactly in contract order:
/// source → Retouch → Geometry (with WP-15 background protection).
struct PortraitPipelineRunner: Sendable {
    private let engine: GeometryRenderingEngine
    private let retoucher: SkinRetoucher

    init() {
        engine = GeometryRenderingEngine(
            passes: [
                GeometryPassEntry(phase: .face, pass: FaceWarpContributor()),
                GeometryPassEntry(phase: .body, pass: BodyWarpContributor()),
                GeometryPassEntry(phase: .legs, pass: LegsWarpContributor())
            ],
            backgroundConstraint: BackgroundWarpConstraint(),
            configuration: .preview,
            backend: CPUGeometryWarp()
        )
        retoucher = SkinRetoucher()
    }

    func run(scene: PortraitScene) async throws -> PortraitPipelineOutput {
        let parameters = PortraitPipelineParameters.make(for: scene.spec.framing)
        let sourceAsset = try scene.pixels.makeImageAsset()
        let start = Date()
        let retouchedAsset = try await retoucher.retouch(
            sourceAsset,
            analysis: scene.analysis,
            parameters: parameters.skin
        )
        let outputAsset = try await engine.warp(
            retouchedAsset,
            analysis: scene.analysis,
            geometry: parameters.geometry,
            quality: .preview
        )
        let duration = Date().timeIntervalSince(start)
        return PortraitPipelineOutput(
            source: scene.pixels,
            retouched: try PixelBuffer(image: retouchedAsset),
            output: try PixelBuffer(image: outputAsset),
            durationSeconds: duration
        )
    }
}

// MARK: - Golden images

enum PortraitGoldenComparison {
    /// Deterministic pipeline output is compared tightly; a recompiled pipeline
    /// should decode to the same bytes apart from PNG round-trip rounding.
    static let thresholds = ImageThresholds(
        channelTolerance: 1,
        allowedDifferingPixelRatio: 0.01,
        maxMeanDeltaE00: 1.0,
        maxP95DeltaE00: 2.0,
        maxDeltaE00: 6.0,
        minSSIM: 0.99
    )

    static func filename(for sampleID: String) -> String {
        "\(sampleID).png"
    }

    static func load(
        _ sampleID: String,
        from directory: URL
    ) throws -> PixelBuffer? {
        let url = directory.appendingPathComponent(filename(for: sampleID))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try PixelBuffer(imageData: Data(contentsOf: url))
    }
}

// MARK: - Defect injection (failure-localisation tests)

enum PortraitDefectInjection {
    /// Moves one background line along a sine curve and fills the vacated
    /// pixels with nearby background. Used to prove the line metric reports a
    /// real bend instead of always passing.
    static func bendBackgroundLine(
        scene: PortraitScene,
        pixels: PixelBuffer
    ) throws -> PixelBuffer {
        let person = MaskOperations.bytes(scene.groundTruth.personMask)
        var output = pixels
        let vertical = scene.groundTruth.lines.first {
            $0.orientation == .vertical && $0.span > 0.2
        }
        if let line = vertical {
            let width = pixels.width
            let height = pixels.height
            let center = Int(line.position * Double(width))
            let startY = max(8, Int(line.start * Double(height)))
            let endY = min(height - 9, Int(line.end * Double(height)))
            guard startY < endY else { return output }
            for y in startY ... endY {
                var blocked = false
                for x in (center - 6) ... (center + 6) where x >= 0 && x < width {
                    if person[y * width + x] > 0 {
                        blocked = true
                        break
                    }
                }
                if blocked { continue }
                let phase = Double(y - startY) / Double(max(1, endY - startY))
                let offset = Int((4.0 * sin(2 * Double.pi * phase)).rounded())
                guard offset != 0 else { continue }
                for x in (center - 2) ... (center + 2) where x >= 0 && x < width {
                    let target = x + offset
                    guard target >= 0, target < width else { continue }
                    output[target, y] = pixels[x, y]
                    let replacement = pixels[min(width - 1, x + 10), y]
                    output[x, y] = replacement
                }
            }
            return output
        }

        if let line = scene.groundTruth.lines.first {
            let width = pixels.width
            let height = pixels.height
            let center = Int(line.position * Double(height))
            let startX = max(8, Int(line.start * Double(width)))
            let endX = min(width - 9, Int(line.end * Double(width)))
            guard startX < endX else { return output }
            for x in startX ... endX {
                let phase = Double(x - startX) / Double(max(1, endX - startX))
                let offset = Int((4.0 * sin(2 * Double.pi * phase)).rounded())
                guard offset != 0 else { continue }
                for y in (center - 2) ... (center + 2) where y >= 0 && y < height {
                    let target = y + offset
                    guard target >= 0, target < height else { continue }
                    output[x, target] = pixels[x, y]
                    output[x, y] = pixels[x, min(height - 1, y + 10)]
                }
            }
        }
        return output
    }

    /// Adds a strong red cast to every skin pixel inside the skin mask.
    static func tintSkin(scene: PortraitScene, pixels: PixelBuffer) -> PixelBuffer {
        var output = pixels
        let skin = MaskOperations.bytes(scene.groundTruth.skinMask)
        for y in 0 ..< pixels.height {
            for x in 0 ..< pixels.width where skin[y * pixels.width + x] > 0 {
                let pixel = pixels[x, y]
                output[x, y] = RGBA8(
                    red: UInt8(min(255, Int(Double(pixel.red) * 1.15 + 4))),
                    green: UInt8(min(255, Int(Double(pixel.green) * 0.94))),
                    blue: UInt8(min(255, Int(Double(pixel.blue) * 0.88)))
                )
            }
        }
        return output
    }

    /// Box-blurs a band around the subject silhouette, simulating a halo or a
    /// torn edge after warping.
    static func blurSilhouette(scene: PortraitScene, pixels: PixelBuffer, radius: Int = 3) throws -> PixelBuffer {
        let personMask = scene.groundTruth.personMask
        let dilated = try MaskOperations.dilated(personMask, radius: radius)
        let eroded = try MaskOperations.eroded(personMask, radius: radius)
        let dilatedBytes = MaskOperations.bytes(dilated)
        let erodedBytes = MaskOperations.bytes(eroded)
        var band: [Bool] = Array(repeating: false, count: pixels.width * pixels.height)
        for index in 0 ..< band.count {
            band[index] = dilatedBytes[index] > 0 && erodedBytes[index] == 0
        }
        let width = pixels.width
        let height = pixels.height
        var output = pixels
        let box = 3
        for y in 0 ..< height {
            for x in 0 ..< width where band[y * width + x] {
                var red = 0
                var green = 0
                var blue = 0
                var count = 0
                for sampleY in max(0, y - box) ... min(height - 1, y + box) {
                    for sampleX in max(0, x - box) ... min(width - 1, x + box) {
                        let pixel = pixels[sampleX, sampleY]
                        red += Int(pixel.red)
                        green += Int(pixel.green)
                        blue += Int(pixel.blue)
                        count += 1
                    }
                }
                guard count > 0 else { continue }
                output[x, y] = RGBA8(
                    red: UInt8(red / count),
                    green: UInt8(green / count),
                    blue: UInt8(blue / count)
                )
            }
        }
        return output
    }
}
