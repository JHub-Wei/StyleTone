import Foundation
import XCTest
@testable import TestShared
import GoldenSupport
import StyleToneCore

final class MockDoublesTests: XCTestCase {
    // MARK: - Analysis

    func testMockPortraitAnalyzerReturnsFixedAndGeneratedAnalyses() async throws {
        let image = try MockImageAssetFactory.solid(
            color: RGB8(gray: 90),
            size: PixelSize(width: 40, height: 60)
        )

        let fixed = MockPortraitAnalysisFactory.empty(size: image.pixelSize)
        let fixedAnalyzer = MockPortraitAnalyzer(analysis: fixed)
        let fixedResult = try await fixedAnalyzer.analyze(image)
        XCTAssertEqual(fixedResult.imageSize, image.pixelSize)
        XCTAssertTrue(fixedResult.faces.isEmpty)

        let generatedAnalyzer = MockPortraitAnalyzer.generated(faceCount: 2, includesBody: true)
        let generated = try await generatedAnalyzer.analyze(image)
        XCTAssertEqual(generated.faces.count, 2)
        XCTAssertTrue(generated.warnings.contains(.multipleFaces))
        XCTAssertEqual(generated.imageSize, image.pixelSize)
        XCTAssertNotNil(generated.personMask)
        XCTAssertEqual(generated.personMask?.width ?? 0, image.pixelSize.width)
    }

    func testMockPortraitAnalyzerFailure() async throws {
        let image = try MockImageAssetFactory.solid()
        let analyzer = MockPortraitAnalyzer(failure: .noFaceDetected)
        do {
            _ = try await analyzer.analyze(image)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? StyleToneError, .noFaceDetected)
        }
    }

    func testPortraitFactoryLandmarksAreCompleteAndNormalized() throws {
        let analysis = try MockPortraitAnalysisFactory.portrait(
            size: PixelSize(width: 100, height: 120),
            faceCount: 1
        )
        let face = try XCTUnwrap(analysis.faces.first)
        XCTAssertEqual(face.landmarks.count, FaceLandmarkKind.allCases.count)
        for kind in FaceLandmarkKind.allCases {
            let points = face.points(for: kind)
            XCTAssertFalse(points.isEmpty, "\(kind) has no points")
            for point in points {
                XCTAssertTrue(point.isNormalized, "\(kind) point outside 0...1: \(point)")
            }
        }
        XCTAssertEqual(face.boundingBox.x, 0.30, accuracy: 1e-9)
        XCTAssertEqual(face.boundingBox.width, 0.40, accuracy: 1e-9)
        XCTAssertEqual(face.boundingBox.y, 0.16, accuracy: 1e-9)
        XCTAssertEqual(face.boundingBox.height, 0.30, accuracy: 1e-9)
        XCTAssertEqual(analysis.body?.joints.count ?? 0, BodyJointKind.allCases.count)
        XCTAssertNotNil(analysis.skinMask)
        XCTAssertNotNil(analysis.backgroundEdgeMask)
    }

    func testPortraitFactoryEmptyAndNoFace() throws {
        let empty = MockPortraitAnalysisFactory.empty(size: PixelSize(width: 10, height: 10))
        XCTAssertTrue(empty.faces.isEmpty)
        XCTAssertTrue(empty.warnings.contains(.noFace))

        let noBody = try MockPortraitAnalysisFactory.portrait(includesBody: false)
        XCTAssertNil(noBody.body)
        XCTAssertTrue(noBody.warnings.contains(.noBody))

        let noFace = try MockPortraitAnalysisFactory.portrait(faceCount: 0)
        XCTAssertTrue(noFace.faces.isEmpty)
        XCTAssertTrue(noFace.warnings.contains(.noFace))
    }

    func testMaskFactories() throws {
        let size = PixelSize(width: 64, height: 48)
        let solid = try MockMaskFactory.solid(value: 200, size: size)
        XCTAssertEqual(solid.width, 64)
        XCTAssertEqual(solid.height, 48)
        XCTAssertEqual(Int(solid.value(x: 10, y: 10) ?? 0), 200)

        let ellipse = try MockMaskFactory.ellipse(size: size)
        XCTAssertEqual(Int(ellipse.value(x: 32, y: 24) ?? 0), 255)
        XCTAssertEqual(Int(ellipse.value(x: 0, y: 0) ?? 0), 0)

        let border = try MockMaskFactory.border(size: size, thickness: 3)
        XCTAssertEqual(Int(border.value(x: 0, y: 0) ?? 0), 255)
        XCTAssertEqual(Int(border.value(x: 32, y: 24) ?? 0), 0)

        let rectangle = try MockMaskFactory.rectangle(
            size: size,
            rect: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        )
        XCTAssertEqual(Int(rectangle.value(x: 32, y: 24) ?? 0), 255)
        XCTAssertEqual(Int(rectangle.value(x: 1, y: 1) ?? 0), 0)
    }

    // MARK: - Pair quality and learning

    func testPairQualityMock() async throws {
        let image = try MockImageAssetFactory.solid()
        let analyzer = MockPairQualityAnalyzer.graded(.warning, reasons: ["pair.reason.blur"], confidence: 0.4)
        let quality = try await analyzer.assess(original: image, edited: image)
        XCTAssertEqual(quality.grade, .warning)
        XCTAssertEqual(quality.reasons, ["pair.reason.blur"])
        XCTAssertEqual(quality.confidence, 0.4, accuracy: 1e-6)
    }

    func testStyleProfilePresets() {
        XCTAssertTrue(MockStyleProfileFactory.natural().isNeutral)
        XCTAssertEqual(MockStyleProfileFactory.trial().pairCount, 3)
        XCTAssertEqual(MockStyleProfileFactory.standard().confidence, .standard)
        XCTAssertEqual(MockStyleProfileFactory.stable().pairCount, 8)
        let extreme = MockStyleProfileFactory.extreme()
        XCTAssertEqual(extreme.skin.smoothing, 1)
        XCTAssertEqual(extreme.body.legLength, 1.15)
        XCTAssertEqual(extreme.finish.vignette, -1)
    }

    func testStyleLearnerMockAndRecorder() async throws {
        let profile = MockStyleProfileFactory.stable()
        let learner = MockStyleLearner(profile: profile)
        let learned = try await learner.learn(samples: [], answers: [])
        XCTAssertEqual(learned, profile)

        let failing = MockStyleLearner(error: .invalidState)
        do {
            _ = try await failing.learn(samples: [], answers: [])
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? StyleToneError, .invalidState)
        }

        let recorder = RecordingStyleLearner(profile: profile)
        _ = try await recorder.learn(
            samples: [],
            answers: [CalibrationAnswer(dimension: .tone, choseA: true)]
        )
        let sampleCounts = await recorder.sampleCounts
        let answerCounts = await recorder.answerCounts
        XCTAssertEqual(sampleCounts, [0])
        XCTAssertEqual(answerCounts, [1])
    }

    // MARK: - Purchase and persistence

    func testPurchaserStateMachine() async throws {
        let purchaser = MockPurchaser(state: .unknown)
        let initial = await purchaser.state
        XCTAssertEqual(initial, .unknown)

        let product = try await purchaser.product()
        XCTAssertEqual(product.id, PurchaseProduct.mockMonthly.id)

        let purchased = try await purchaser.purchase()
        XCTAssertEqual(purchased, .active)
        let restored = try await purchaser.restore()
        XCTAssertEqual(restored, .active)

        let purchaseCalls = await purchaser.purchaseCallCount
        let restoreCalls = await purchaser.restoreCallCount
        XCTAssertEqual(purchaseCalls, 1)
        XCTAssertEqual(restoreCalls, 1)
    }

    func testPurchaserFailures() async throws {
        let failingPurchase = MockPurchaser(failurePoint: .purchase)
        do {
            _ = try await failingPurchase.purchase()
            XCTFail("expected purchase failure")
        } catch {
            XCTAssertEqual(error as? StyleToneError, .purchaseFailed)
        }

        let failingRestore = MockPurchaser(failurePoint: .restore)
        do {
            _ = try await failingRestore.restore()
            XCTFail("expected restore failure")
        } catch {
            XCTAssertEqual(error as? StyleToneError, .purchaseFailed)
        }
    }

    func testStyleProfileStoreMock() async throws {
        let profile = MockStyleProfileFactory.standard()
        let store = MockStyleProfileStore()
        let empty = try await store.loadActive()
        XCTAssertNil(empty)

        try await store.save(profile)
        let loaded = try await store.loadActive()
        XCTAssertEqual(loaded, profile)

        try await store.deleteAll()
        let deleted = try await store.loadActive()
        XCTAssertNil(deleted)

        let deleteCalls = await store.deleteCount
        XCTAssertEqual(deleteCalls, 1)
    }

    // MARK: - Images and rendering

    func testImageFactoryPatterns() throws {
        let size = PixelSize(width: 20, height: 10)
        let solid = try MockImageAssetFactory.solid(color: RGB8(red: 1, green: 2, blue: 3), size: size)
        XCTAssertEqual(solid.pixelSize, size)
        XCTAssertEqual(try PixelBuffer(image: solid)[5, 5].color, RGB8(red: 1, green: 2, blue: 3))

        let gradient = try MockImageAssetFactory.gradient(size: size)
        XCTAssertEqual(try PixelBuffer(image: gradient)[0, 0].color, .black)
        XCTAssertEqual(try PixelBuffer(image: gradient)[size.width - 1, 0].color, .white)

        let checker = try MockImageAssetFactory.checkerboard(cellSize: 2, size: size)
        XCTAssertEqual(checker.pixelSize, size)

        let fixture = try MockImageAssetFactory.fixture(named: "solid.cream")
        XCTAssertEqual(fixture.pixelSize, PixelSize(width: 64, height: 64))
        XCTAssertThrowsError(try MockImageAssetFactory.fixture(named: "missing"))
    }

    func testRendererAndExporterMocks() async throws {
        let image = try MockImageAssetFactory.solid()
        let request = RenderRequest(
            image: image,
            analysis: MockPortraitAnalysisFactory.empty(size: image.pixelSize),
            style: MockStyleProfileFactory.natural()
        )
        let warning = RenderWarning(kind: .noFace, messageKey: "render.noFace")
        let output = try await MockImageRenderer.echo(warnings: [warning]).render(request)
        XCTAssertEqual(output.image.pixelSize, image.pixelSize)
        XCTAssertEqual(output.warnings, [warning])

        let failing = MockImageRenderer.failing()
        do {
            _ = try await failing.render(request)
            XCTFail("expected renderer failure")
        } catch {
            XCTAssertEqual(error as? StyleToneError, .renderingFailed)
        }

        let export = try await MockImageExporter.succeeding().export(
            image,
            options: ExportOptions(format: .jpeg)
        )
        XCTAssertEqual(export.format, .jpeg)
        XCTAssertEqual(export.pixelSize, image.pixelSize)
        XCTAssertEqual(export.url.pathExtension, "jpg")

        let retouched = try await MockRetoucher.passthrough().retouch(
            image,
            analysis: request.analysis,
            parameters: SkinParameters()
        )
        XCTAssertEqual(retouched.pixelSize, image.pixelSize)

        let warped = try await MockGeometryRenderer.passthrough().warp(
            image,
            analysis: request.analysis,
            parameters: FaceParameters(),
            body: BodyParameters(),
            backgroundProtection: true
        )
        XCTAssertEqual(warped.pixelSize, image.pixelSize)
    }

    // MARK: - Environment helpers

    func testTestEnvironmentFindsRepositoryFixtures() throws {
        let environment = TestEnvironment()
        guard let repositoryRoot = environment.repositoryRoot else {
            throw XCTSkip("repository root not found; set ST_REPO_ROOT")
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent("Package.swift").path
            )
        )
        let manifestURL = try environment.requireFixtureManifestURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        let relativeManifestURL = try environment.fixtureURL(relativePath: "manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: relativeManifestURL.path))
        XCTAssertThrowsError(try environment.fixtureURL(relativePath: "../Package.swift"))
    }

    func testTemporaryDirectoryIsRemoved() throws {
        let directory = try TemporaryDirectory(prefix: "TestSharedTests")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.url.path))
        directory.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.url.path))

        let collected = try TemporaryDirectory.withTemporaryDirectory { url -> String in
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            return url.lastPathComponent
        }
        XCTAssertFalse(collected.isEmpty)
    }

    func testClocks() {
        let fixed = FixedDateProvider()
        XCTAssertEqual(fixed.now, FixedDateProvider.reference)

        let adjustable = AdjustableTestClock()
        XCTAssertEqual(adjustable.now, FixedDateProvider.reference)
        adjustable.advance(by: 60)
        XCTAssertEqual(adjustable.now, FixedDateProvider.reference.addingTimeInterval(60))
        let newDate = Date(timeIntervalSince1970: 0)
        adjustable.set(newDate)
        XCTAssertEqual(adjustable.now, newDate)
    }
}
