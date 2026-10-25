import CoreGraphics
import Foundation
import ImageIO
import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

/// 12MP budget check for the export pipeline.
///
/// `StyleToneUITests` does not link `StyleToneImaging`, so the exporter below
/// uses the same ImageIO calls as WP-02's `ImageWriter` for the purpose of
/// timing the platform HEVC/JPEG encoder. The renderer is the echo mock: this
/// isolates the export slice's own overhead plus system encoding. WP-24 owns the
/// final device measurement of the complete WP-17 render + export pipeline.
@MainActor
final class ExportPerformanceTests: XCTestCase {
    func testTwelveMegapixelExportStaysWithinBudget() async throws {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        let format: ExportFormat = identifiers.contains("public.heic") ? .heic : .jpeg
        let size = PixelSize(width: 4_032, height: 3_024)
        let image = try makeImageAsset(size: size)
        let analysis = try MockPortraitAnalysisFactory.portrait(
            size: size,
            includesMasks: false
        )
        let request = RenderRequest(
            image: image,
            analysis: analysis,
            style: MockStyleProfileFactory.standard(
                updatedAt: ExportTestFactory.referenceDate
            )
        )
        let source = ExportSource(request: request)

        let temp = try TemporaryDirectory(prefix: "StyleToneExportPerformance")
        defer { temp.remove() }

        let exporter = PlatformImageExporter(directory: temp.url)
        let quota = FakeExportQuota(.unlimited)
        let dependencies = ExportTestFactory.dependencies(
            directory: temp.url,
            exporter: exporter,
            quota: quota,
            supportsShare: false
        )
        let model = ExportViewModel(
            source: source,
            dependencies: dependencies,
            settings: ExportSettings(format: format, quality: .high)
        )

        await model.start()
        XCTAssertTrue(model.canSaveToLibrary)

        // Warm up the platform codec (cold HEIC/JPEG setup) without measuring it.
        model.saveToLibrary()
        await model.waitForCompletion()
        XCTAssertEqual(model.stage, .finished, "warm-up failed")
        let warmUpFiles = try ExportTestFactory.directoryContents(temp.url)
        XCTAssertTrue(warmUpFiles.isEmpty)

        let iterations = 10
        var durations: [TimeInterval] = []
        for iteration in 0..<iterations {
            let started = Date()
            model.saveToLibrary()
            await model.waitForCompletion()
            let elapsed = Date().timeIntervalSince(started)
            durations.append(elapsed)

            XCTAssertEqual(model.stage, .finished, "iteration \(iteration) failed")
            XCTAssertEqual(model.outcome?.pixelSize, size)
            XCTAssertEqual(model.outcome?.format, format)
            XCTAssertEqual(model.outcome?.counted, true)

            let files = try ExportTestFactory.directoryContents(temp.url)
            XCTAssertTrue(files.isEmpty, "iteration \(iteration) left a temp file")
        }

        let sorted = durations.sorted()
        let p95 = percentile(sorted, 0.95)

        let summary = durations
            .map { String(format: "%.3f", $0) }
            .joined(separator: ", ")
        let attachment = XCTAttachment(
            string: "12MP \(format.rawValue) durations (s): [\(summary)], p95=\(String(format: "%.3f", p95))"
        )
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertLessThanOrEqual(
            p95,
            ExportAcceptance.twelveMegapixelBudget,
            "12MP export p95 \(p95)s exceeds \(ExportAcceptance.twelveMegapixelBudget)s"
        )

        let count = await quota.recordCount
        XCTAssertEqual(count, iterations + 1, "warm-up plus measured runs must be counted")
    }

    /// Linear-interpolated percentile over an already sorted sample.
    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(max(p, 0), 1)
        let position = clamped * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper {
            return sorted[lower]
        }
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    // MARK: - Test-local encoder

    /// Minimal ImageIO exporter timing the platform codec.
    private actor PlatformImageExporter: ImageExporting {
        private let directory: URL

        init(directory: URL) {
            self.directory = directory
        }

        func export(_ output: ImageAsset, options: ExportOptions) async throws -> ExportResult {
            let typeIdentifier = options.format == .heic ? "public.heic" : "public.jpeg"
            let fileExtension = options.format == .heic ? "heic" : "jpg"
            let url = directory
                .appendingPathComponent("perf-\(UUID().uuidString)")
                .appendingPathExtension(fileExtension)

            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                typeIdentifier as CFString,
                1,
                nil
            ) else {
                throw StyleToneError.exportFailed
            }

            let properties: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: min(max(options.quality, 0), 1)
            ]
            CGImageDestinationAddImage(destination, output.cgImage, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw StyleToneError.exportFailed
            }

            return ExportResult(
                url: url,
                pixelSize: output.pixelSize,
                format: options.format
            )
        }
    }

    // MARK: - Fixture

    private func makeImageAsset(size: PixelSize) throws -> ImageAsset {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: size.width,
                height: size.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        )

        let startColor = try XCTUnwrap(
            CGColor(colorSpace: colorSpace, components: [0.12, 0.08, 0.20, 1])
        )
        let endColor = try XCTUnwrap(
            CGColor(colorSpace: colorSpace, components: [0.95, 0.65, 0.35, 1])
        )
        let stripeColor = try XCTUnwrap(
            CGColor(colorSpace: colorSpace, components: [0.80, 0.40, 0.20, 1])
        )
        let colors = [startColor, endColor] as CFArray
        let gradient = try XCTUnwrap(
            CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])
        )
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size.width, y: size.height),
            options: []
        )

        for x in stride(from: 0, to: size.width, by: 24) {
            context.setFillColor(stripeColor)
            context.fill(CGRect(x: x, y: 0, width: 8, height: size.height))
        }

        let cgImage = try XCTUnwrap(context.makeImage())
        return ImageAsset(cgImage: cgImage, colorSpace: colorSpace)
    }
}
