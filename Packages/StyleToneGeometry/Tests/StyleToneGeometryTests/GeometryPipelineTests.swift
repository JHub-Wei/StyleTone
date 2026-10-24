import Foundation
import StyleToneCore
import TestShared
import XCTest
@testable import StyleToneGeometry

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    var recorded: [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private struct ClosurePass: GeometryPass {
    let identifier: String
    let recorder: Recorder?
    let action: @Sendable (inout WarpField) throws -> Void

    init(
        identifier: String,
        recorder: Recorder? = nil,
        action: @escaping @Sendable (inout WarpField) throws -> Void = { _ in }
    ) {
        self.identifier = identifier
        self.recorder = recorder
        self.action = action
    }

    func contribute(
        to field: inout WarpField,
        analysis: PortraitAnalysis,
        parameters: GeometryParameters
    ) throws {
        recorder?.record(identifier)
        try action(&field)
    }
}

private struct ClosureConstraint: GeometryConstraint {
    let identifier: String
    let recorder: Recorder?
    let action: @Sendable (inout WarpField) throws -> Void

    init(
        identifier: String,
        recorder: Recorder? = nil,
        action: @escaping @Sendable (inout WarpField) throws -> Void = { _ in }
    ) {
        self.identifier = identifier
        self.recorder = recorder
        self.action = action
    }

    func constrain(_ field: inout WarpField, analysis: PortraitAnalysis) throws {
        recorder?.record(identifier)
        try action(&field)
    }
}

private final class RecordingBackend: GeometryWarpBackend, @unchecked Sendable {
    let identifier = "test.recording"
    let isGPUAccelerated = false
    private let lock = NSLock()
    private var field: WarpField?
    private var callCount = 0

    var lastField: WarpField? {
        lock.lock()
        defer { lock.unlock() }
        return field
    }

    var warpCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    func warp(
        _ image: ImageAsset,
        field: WarpField,
        configuration: GeometryWarpConfiguration
    ) throws -> ImageAsset {
        lock.lock()
        defer { lock.unlock() }
        self.field = field
        callCount += 1
        return image
    }
}

private enum SpyError: Error {
    case boom
}

final class GeometryPipelineTests: XCTestCase {
    private func analysis() -> PortraitAnalysis {
        MockPortraitAnalysisFactory.empty(size: PixelSize(width: 128, height: 128))
    }

    func testPassPhasesRunFaceBodyLegsRegardlessOfRegistrationOrder() throws {
        let recorder = Recorder()
        let pipeline = GeometryPipeline(
            passes: [
                GeometryPassEntry(phase: .legs, pass: ClosurePass(identifier: "legs", recorder: recorder)),
                GeometryPassEntry(phase: .face, pass: ClosurePass(identifier: "face", recorder: recorder)),
                GeometryPassEntry(phase: .body, pass: ClosurePass(identifier: "body", recorder: recorder))
            ],
            gridDimension: 8
        )

        _ = try pipeline.makeField(
            analysis: analysis(),
            parameters: .neutral
        )

        XCTAssertEqual(recorder.recorded, ["face", "body", "legs"])
    }

    func testSamePhasePassesKeepRegistrationOrder() throws {
        let recorder = Recorder()
        let pipeline = GeometryPipeline(
            passes: [
                GeometryPassEntry(phase: .face, pass: ClosurePass(identifier: "face.a", recorder: recorder)),
                GeometryPassEntry(phase: .face, pass: ClosurePass(identifier: "face.b", recorder: recorder))
            ],
            gridDimension: 8
        )

        _ = try pipeline.makeField(analysis: analysis(), parameters: .neutral)
        XCTAssertEqual(recorder.recorded, ["face.a", "face.b"])
    }

    func testConstraintsRunAfterPassesAndBackgroundRunsLast() throws {
        let recorder = Recorder()
        let pipeline = GeometryPipeline(
            passes: [
                GeometryPassEntry(phase: .face, pass: ClosurePass(identifier: "face", recorder: recorder)),
                GeometryPassEntry(phase: .body, pass: ClosurePass(identifier: "body", recorder: recorder)),
                GeometryPassEntry(phase: .legs, pass: ClosurePass(identifier: "legs", recorder: recorder))
            ],
            constraints: [ClosureConstraint(identifier: "constraint", recorder: recorder)],
            backgroundConstraint: ClosureConstraint(identifier: "background", recorder: recorder),
            gridDimension: 8
        )

        _ = try pipeline.makeField(
            analysis: analysis(),
            parameters: GeometryParameters(backgroundProtection: true)
        )

        XCTAssertEqual(
            recorder.recorded,
            ["face", "body", "legs", "constraint", "background"]
        )
    }

    func testBackgroundConstraintIsSkippedWhenProtectionIsOff() throws {
        let recorder = Recorder()
        let pipeline = GeometryPipeline(
            backgroundConstraint: ClosureConstraint(identifier: "background", recorder: recorder),
            gridDimension: 8
        )

        _ = try pipeline.makeField(
            analysis: analysis(),
            parameters: GeometryParameters(backgroundProtection: false)
        )
        XCTAssertEqual(recorder.recorded, [])
    }

    func testBoundaryPolicyRunsAfterConstraints() throws {
        let pipeline = GeometryPipeline(
            constraints: [
                ClosureConstraint(identifier: "constraint") { field in
                    for index in field.offsets.indices {
                        field.offsets[index] = SIMD2<Float>(0.3, 0)
                    }
                }
            ],
            boundaryPolicy: GeometryBoundaryPolicy(
                pinnedBorderVertices: 1,
                featherCells: 0,
                maximumDisplacement: 1
            ),
            gridDimension: 8
        )

        let field = try pipeline.makeField(analysis: analysis(), parameters: .neutral)
        for y in 0 ..< 8 {
            for x in 0 ..< 8 {
                let edgeDistance = min(min(x, y), min(7 - x, 7 - y))
                if edgeDistance == 0 {
                    XCTAssertEqual(field.offsets[y * 8 + x], .zero)
                }
            }
        }
        XCTAssertEqual(field.offsets[4 * 8 + 4], SIMD2<Float>(0.3, 0))
    }

    func testFieldUsesConfiguredMeshDensity() throws {
        for (quality, expected) in [
            (GeometryQuality.preview, 32),
            (GeometryQuality.export, 64)
        ] {
            let pipeline = GeometryPipeline(
                configuration: GeometryWarpConfiguration(quality: quality)
            )
            let field = try pipeline.makeField(analysis: analysis(), parameters: .neutral)
            XCTAssertEqual(field.width, expected, "quality \(quality)")
            XCTAssertEqual(field.height, expected, "quality \(quality)")
        }
    }

    func testPassErrorPropagates() {
        let pipeline = GeometryPipeline(
            passes: [
                GeometryPassEntry(
                    phase: .face,
                    pass: ClosurePass(identifier: "throwing") { _ in
                        throw SpyError.boom
                    }
                )
            ],
            gridDimension: 8
        )
        XCTAssertThrowsError(try pipeline.makeField(analysis: analysis(), parameters: .neutral)) { error in
            XCTAssertTrue(error is SpyError)
        }
    }

    func testNonFinitePassOutputIsRejected() {
        let pipeline = GeometryPipeline(
            passes: [
                GeometryPassEntry(
                    phase: .face,
                    pass: ClosurePass(identifier: "nan") { field in
                        field.offsets[0] = SIMD2<Float>(.nan, 0)
                    }
                )
            ],
            gridDimension: 8
        )
        XCTAssertThrowsError(try pipeline.makeField(analysis: analysis(), parameters: .neutral)) { error in
            XCTAssertEqual(error as? GeometryError, .nonFiniteOffset(index: 0))
        }
    }

    func testPassCannotResizeTheField() {
        let pipeline = GeometryPipeline(
            passes: [
                GeometryPassEntry(
                    phase: .face,
                    pass: ClosurePass(identifier: "resize") { field in
                        field.width = 4
                    }
                )
            ],
            gridDimension: 8
        )
        XCTAssertThrowsError(try pipeline.makeField(analysis: analysis(), parameters: .neutral)) { error in
            XCTAssertEqual(
                error as? GeometryError,
                .offsetCountMismatch(expected: 32, actual: 64)
            )
        }
    }

    func testCancellationStopsLaterPasses() async throws {
        let recorder = Recorder()
        let pipeline = GeometryPipeline(
            passes: [
                GeometryPassEntry(
                    phase: .face,
                    pass: ClosurePass(identifier: "cancel") { _ in
                        withUnsafeCurrentTask { task in
                            task?.cancel()
                        }
                    }
                ),
                GeometryPassEntry(
                    phase: .body,
                    pass: ClosurePass(identifier: "must-not-run", recorder: recorder)
                )
            ],
            gridDimension: 8
        )
        let analysis = analysis()

        let task = Task { () -> Error? in
            do {
                _ = try pipeline.makeField(analysis: analysis, parameters: .neutral)
                return nil
            } catch {
                return error
            }
        }
        let error = await task.value
        XCTAssertNotNil(error as? CancellationError)
        XCTAssertEqual(recorder.recorded, [])
    }

    func testInvalidGridDimensionIsRejected() {
        let pipeline = GeometryPipeline(gridDimension: 1)
        XCTAssertThrowsError(try pipeline.makeField(analysis: analysis(), parameters: .neutral)) { error in
            XCTAssertEqual(error as? GeometryError, .invalidGrid(width: 1, height: 1))
        }
    }

    func testOrderedPassesPreservesStableOrder() {
        let faceA = ClosurePass(identifier: "face.a")
        let body = ClosurePass(identifier: "body")
        let faceB = ClosurePass(identifier: "face.b")
        let pipeline = GeometryPipeline(
            passes: [
                GeometryPassEntry(phase: .body, pass: body),
                GeometryPassEntry(phase: .face, pass: faceB),
                GeometryPassEntry(phase: .face, pass: faceA)
            ],
            gridDimension: 8
        )
        XCTAssertEqual(
            pipeline.orderedPasses.map { $0.pass.identifier },
            ["face.b", "face.a", "body"]
        )
    }

    func testEngineEmptyPipelineReturnsExactInput() async throws {
        let image = try GeometryTestSupport.gradientWithBorder(width: 32, height: 32)
        let engine = GeometryRenderingEngine(
            configuration: .preview,
            backend: CPUGeometryWarp()
        )
        let output = try await engine.warp(
            image,
            analysis: MockPortraitAnalysisFactory.empty(size: image.pixelSize),
            parameters: .neutral,
            body: .neutral,
            backgroundProtection: false
        )
        XCTAssertTrue(output.cgImage === image.cgImage)
    }

    func testEnginePassesConfiguredQualityFieldToBackend() async throws {
        let backend = RecordingBackend()
        let engine = GeometryRenderingEngine(
            passes: [
                GeometryPassEntry(
                    phase: .face,
                    pass: ClosurePass(identifier: "shift") { field in
                        for index in field.offsets.indices {
                            field.offsets[index] = SIMD2<Float>(0.05, 0)
                        }
                    }
                )
            ],
            configuration: .preview,
            backend: backend
        )
        let image = try GeometryTestSupport.gradientWithBorder(width: 32, height: 32)

        _ = try await engine.warp(
            image,
            analysis: MockPortraitAnalysisFactory.empty(size: image.pixelSize),
            geometry: .neutral,
            quality: .export
        )

        XCTAssertEqual(backend.warpCount, 1)
        XCTAssertEqual(backend.lastField?.width, 64)
        XCTAssertEqual(backend.lastField?.height, 64)
        XCTAssertFalse(backend.lastField?.isZero() ?? true)
    }

    func testEngineForwardsBackgroundProtectionToPipeline() async throws {
        let recorder = Recorder()
        let engine = GeometryRenderingEngine(
            backgroundConstraint: ClosureConstraint(identifier: "background", recorder: recorder),
            configuration: .preview,
            backend: CPUGeometryWarp()
        )
        let image = try GeometryTestSupport.gradientWithBorder(width: 32, height: 32)
        _ = try await engine.warp(
            image,
            analysis: MockPortraitAnalysisFactory.empty(size: image.pixelSize),
            parameters: .neutral,
            body: .neutral,
            backgroundProtection: true
        )
        XCTAssertEqual(recorder.recorded, ["background"])
    }

    func testEngineExposesBackendIdentity() async {
        let engine = GeometryRenderingEngine(backend: CPUGeometryWarp())
        let identifier = await engine.backendIdentifier
        let isGPU = await engine.isGPUAccelerated
        XCTAssertEqual(identifier, "geometry.cpu")
        XCTAssertFalse(isGPU)
    }
}
