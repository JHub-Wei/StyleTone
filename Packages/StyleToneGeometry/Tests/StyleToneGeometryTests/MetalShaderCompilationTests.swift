#if canImport(Metal) && os(macOS)
import Foundation
import XCTest
@testable import StyleToneGeometry

/// Compiles the embedded Metal shader with the offline toolchain.
///
/// GitHub-hosted macOS runners often expose no Metal device, so runtime library
/// compilation is skipped there. This test still validates the shader syntax
/// and catches MSL breakage on every CI run that has Xcode installed.
final class MetalShaderCompilationTests: XCTestCase {
    func testEmbeddedShaderCompiles() throws {
        let xcrun = "/usr/bin/xcrun"
        guard FileManager.default.isExecutableFile(atPath: xcrun) else {
            throw XCTSkip("xcrun is unavailable")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("geometry-shader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let sourceURL = directory.appendingPathComponent("GeometryShader.metal")
        let outputURL = directory.appendingPathComponent("GeometryShader.air")
        try MetalGeometryWarp.shaderSource.write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrun)
        process.arguments = [
            "--sdk", "macosx",
            "metal",
            "-c", sourceURL.path,
            "-o", outputURL.path
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0, output.contains("unable to find utility") {
            throw XCTSkip("Metal toolchain is unavailable: \(output)")
        }
        XCTAssertEqual(process.terminationStatus, 0, output)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.path),
            "metal did not emit an AIR file: \(output)"
        )
    }
}
#endif
