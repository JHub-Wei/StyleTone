import Foundation
import PerformanceKit
import StyleToneCore
import StyleToneGeometry
import StyleToneImaging
import StyleToneUI
import TestShared
import XCTest

/// Full 12 MP export slice: real Metal geometry engine + `EditorRenderer`
/// composition + platform ImageIO encode and temp-file write.
///
/// The retouch and tone stages are passthrough doubles so this test measures the
/// export integration and codec, not the WP-07 algorithm (which has its own
/// 12 MP envelope). The geometry engine is real and runs at export density.
final class ExportPerformanceTests: XCTestCase {
    func testTwelveMegapixelRenderAndEncode() async throws {
        let engine = makeSyntheticGeometryEngine(quality: .export)
        guard await engine.isGPUAccelerated else {
            throw XCTSkip("Metal device unavailable; the CPU export path is not a budget target")
        }

        let scenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "export.twelveMegapixel")
        )
        let memoryScenario = try XCTUnwrap(
            PerformanceScenario.scenario(id: "export.memoryPeak")
        )
        let session = try PerformanceSession(source: "ExportPerformanceTests")
        defer { session.finish() }

        let temp = try TemporaryDirectory(prefix: "StyleTonePerfExport")
        defer { temp.remove() }

        let size = PixelSize(width: 4_032, height: 3_024)
        let image = try PerformanceFixtures.gradientImage(size: size)
        let analysis = try PerformanceFixtures.analysis(
            size: size,
            includesMasks: false
        )
        let renderer = EditorRenderer(
            retoucher: MockRetoucher.passthrough(),
            blemishRemover: MockBlemishRemover.passthrough(),
            geometryRenderer: engine
        )
        let exporter = FileImageExporter(directory: temp.url)
        let request = RenderRequest(
            image: image,
            analysis: analysis,
            style: PerformanceFixtures.style(),
            strength: 1,
            adjustments: ManualAdjustments(faceSlim: 0.35, jaw: 0.25),
            backgroundProtection: true
        )
        let options = ExportOptions(format: .jpeg, quality: 0.9)

        // Warm the Metal pipeline and the platform codec; not recorded.
        let warmOutput = try await renderer.render(request)
        let warmResult = try await exporter.export(warmOutput.image, options: options)
        try exporter.removeExportedFile(at: warmResult.url)

        let probe = LockedMemoryProbe(reader: DarwinMemoryFootprintReader())
        try probe.start()

        let measurement = try await PerformanceClock.measureAsync(
            scenario: scenario,
            iterations: 3,
            warmUpIterations: 0
        ) {
            try probe.sample()
            let output = try await renderer.render(request)
            try probe.sample()
            let result = try await exporter.export(output.image, options: options)
            try probe.sample()
            try exporter.removeExportedFile(at: result.url)
            XCTAssertEqual(result.pixelSize, size)
        }

        let memoryMeasurement = try probe.measurement(
            scenarioID: memoryScenario.id,
            absolute: PerformanceTestEnvironment.isReferenceDevice
        )
        session.recordAndAssertContract(
            memoryMeasurement,
            scenario: memoryScenario,
            contract: 500,
            notes: PerformanceTestEnvironment.isReferenceDevice
                ? "absolute phys_footprint peak"
                : "peak delta from process baseline"
        )
        session.recordAndAssertContract(
            measurement,
            scenario: scenario,
            contract: 6,
            notes: "12 MP Metal export grid + JPEG encode; peak delta "
                + String(format: "%.1f MB", probe.peakDeltaMegabytes)
        )
    }
}
