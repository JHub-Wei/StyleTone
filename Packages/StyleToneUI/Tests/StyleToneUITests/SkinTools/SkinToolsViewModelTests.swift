import Foundation
import StyleToneCore
import XCTest
@testable import StyleToneUI

@MainActor
final class SkinToolsViewModelTests: XCTestCase {
    func testStrengthZeroReturnsTheSourceWithoutCallingTheEngine() async throws {
        let original = try SkinToolsTestFactory.image()
        let processed = try SkinToolsTestFactory.image(color: .white)
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let retoucher = SkinToolsRetouchSpy(steps: [.success(processed)])
        let remover = SkinToolsBlemishSpy()
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: retoucher,
            blemishRemover: remover
        )

        XCTAssertTrue(model.isShowingOriginal)
        XCTAssertTrue(model.isAtOriginal)
        let initialCalls = await retoucher.callCount()
        XCTAssertEqual(initialCalls, 0)

        model.setSmoothing(0.6)
        await model.waitForRendering()

        XCTAssertFalse(model.isShowingOriginal)
        XCTAssertTrue(model.displayedImage.cgImage === processed.cgImage)
        let renderedCalls = await retoucher.callCount()
        XCTAssertEqual(renderedCalls, 1)

        model.setSmoothing(0)
        await model.waitForRendering()

        XCTAssertTrue(model.isShowingOriginal)
        XCTAssertTrue(model.isAtOriginal)
        XCTAssertTrue(model.displayedImage.cgImage === original.cgImage)
        let neutralCalls = await retoucher.callCount()
        XCTAssertEqual(neutralCalls, 1, "A neutral job must not call the engine")
    }

    func testEvennessRendersWithContractParametersAndSourceAnalysis() async throws {
        let original = try SkinToolsTestFactory.image()
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let retoucher = SkinToolsRetouchSpy()
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: retoucher,
            blemishRemover: SkinToolsBlemishSpy()
        )

        model.setEvenness(0.4)
        await model.waitForRendering()

        let parameters = await retoucher.lastParameters()
        XCTAssertEqual(
            parameters,
            SkinParameters(smoothing: 0, evenness: 0.4, blemish: 0)
        )
        let analysisSizes = await retoucher.recordedAnalysisSizes()
        XCTAssertEqual(analysisSizes, [original.pixelSize])
    }

    func testSliderValuesAndRadiusAreClamped() async throws {
        let original = try SkinToolsTestFactory.image()
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: SkinToolsBlemishSpy()
        )

        model.setSmoothing(4)
        XCTAssertEqual(model.smoothing, 1, accuracy: 0.0001)
        model.setSmoothing(-1)
        XCTAssertEqual(model.smoothing, 0, accuracy: 0.0001)
        model.setEvenness(-2)
        XCTAssertEqual(model.evenness, 0, accuracy: 0.0001)
        model.setEvenness(0.25)
        XCTAssertEqual(model.evenness, 0.25, accuracy: 0.0001)
        await model.waitForRendering()

        model.setRadius(2)
        XCTAssertEqual(model.radius, SkinToolsLimits.maximumRadius, accuracy: 0.0001)
        model.setRadius(-2)
        XCTAssertEqual(model.radius, SkinToolsLimits.minimumRadius, accuracy: 0.0001)
        model.setRadius(.nan)
        XCTAssertEqual(model.radius, SkinToolsLimits.defaultRadius, accuracy: 0.0001)
    }

    func testNoFaceDisablesAndIgnoresEveryAction() async throws {
        let original = try SkinToolsTestFactory.image()
        let analysis = try SkinToolsTestFactory.analysis(for: original, faceCount: 0)
        let retoucher = SkinToolsRetouchSpy()
        let remover = SkinToolsBlemishSpy()
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: retoucher,
            blemishRemover: remover
        )

        XCTAssertFalse(model.isFaceAvailable)
        XCTAssertEqual(model.unavailableReason, .noFace)
        XCTAssertFalse(model.areControlsEnabled)
        XCTAssertFalse(model.canApplyBlemish)
        XCTAssertFalse(model.canUndoBlemish)

        model.setSmoothing(0.8)
        model.setEvenness(0.5)
        model.beginBlemishMode()
        model.addBlemish(at: NormalizedPoint(x: 0.5, y: 0.5))
        await model.waitForRendering()

        XCTAssertEqual(model.smoothing, 0)
        XCTAssertEqual(model.evenness, 0)
        XCTAssertFalse(model.isBlemishMode)
        XCTAssertTrue(model.blemishes.isEmpty)
        XCTAssertTrue(model.isShowingOriginal)
        let retouchCalls = await retoucher.callCount()
        let blemishCalls = await remover.callCount()
        XCTAssertEqual(retouchCalls, 0)
        XCTAssertEqual(blemishCalls, 0)
    }

    func testIncompatibleAnalysisDisablesRendering() async throws {
        let original = try SkinToolsTestFactory.image(size: PixelSize(width: 96, height: 128))
        let otherSize = try SkinToolsTestFactory.image(size: PixelSize(width: 64, height: 64))
        let analysis = try SkinToolsTestFactory.analysis(for: otherSize)
        let retoucher = SkinToolsRetouchSpy()
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: retoucher,
            blemishRemover: SkinToolsBlemishSpy()
        )

        XCTAssertTrue(model.isFaceAvailable)
        XCTAssertFalse(model.isAnalysisCompatible)
        XCTAssertEqual(model.unavailableReason, .analysisMismatch)
        XCTAssertFalse(model.areControlsEnabled)

        model.setSmoothing(0.5)
        await model.waitForRendering()

        XCTAssertEqual(model.smoothing, 0)
        XCTAssertTrue(model.isShowingOriginal)
        let calls = await retoucher.callCount()
        XCTAssertEqual(calls, 0)
    }

    func testMissingSkinMaskIsReportedWithoutDisablingControls() async throws {
        let original = try SkinToolsTestFactory.image()
        let analysis = try SkinToolsTestFactory.analysis(for: original, includesMasks: false)
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: SkinToolsBlemishSpy()
        )

        XCTAssertTrue(model.isFaceAvailable)
        XCTAssertTrue(model.areControlsEnabled)
        XCTAssertFalse(model.isSkinMaskAvailable)
        XCTAssertTrue(model.isAtOriginal)
    }

    func testWrongSizeSkinMaskIsReportedWithoutDisablingControls() throws {
        let original = try SkinToolsTestFactory.image()
        let valid = try SkinToolsTestFactory.analysis(for: original)
        let wrongMask = try MaskBuffer(
            width: 8,
            height: 8,
            bytes: Data(repeating: 255, count: 64)
        )
        let analysis = PortraitAnalysis(
            imageSize: valid.imageSize,
            faces: valid.faces,
            body: valid.body,
            personMask: valid.personMask,
            skinMask: wrongMask,
            backgroundEdgeMask: valid.backgroundEdgeMask,
            warnings: valid.warnings
        )
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: SkinToolsBlemishSpy()
        )

        XCTAssertTrue(model.isFaceAvailable)
        XCTAssertTrue(model.areControlsEnabled)
        XCTAssertFalse(model.isSkinMaskAvailable)
    }

    func testBlemishTapAppliesAndUndoRestoresOriginalWithoutRerendering() async throws {
        let original = try SkinToolsTestFactory.image()
        let blemished = try SkinToolsTestFactory.image(color: .white)
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let remover = SkinToolsBlemishSpy(steps: [.success(blemished)])
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: remover
        )

        model.setRadius(0.02)
        model.beginBlemishMode()
        model.addBlemish(at: NormalizedPoint(x: 0.4, y: 0.6))
        await model.waitForRendering()

        XCTAssertTrue(model.isBlemishMode)
        XCTAssertEqual(model.blemishes.count, 1)
        XCTAssertEqual(model.blemishes.first?.radius ?? 0, 0.02, accuracy: 0.0001)
        XCTAssertFalse(model.isShowingOriginal)
        XCTAssertTrue(model.displayedImage.cgImage === blemished.cgImage)

        let recorded = await remover.recordedPoints()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.point, NormalizedPoint(x: 0.4, y: 0.6))
        XCTAssertEqual(recorded.first?.radius ?? 0, 0.02, accuracy: 0.0001)

        model.undoBlemish()
        await model.waitForRendering()

        XCTAssertTrue(model.blemishes.isEmpty)
        XCTAssertTrue(model.isShowingOriginal)
        XCTAssertTrue(model.displayedImage.cgImage === original.cgImage)
        let calls = await remover.callCount()
        XCTAssertEqual(calls, 1, "A neutral undo restores the source directly")
    }

    func testBlemishFailureKeepsImageAndHistoryThenRetryCommits() async throws {
        let original = try SkinToolsTestFactory.image()
        let blemished = try SkinToolsTestFactory.image(color: .white)
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let remover = SkinToolsBlemishSpy(steps: [.failure(.retouchingFailed)])
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: remover
        )

        model.addBlemish(at: NormalizedPoint(x: 0.3, y: 0.4))
        await model.waitForRendering()

        XCTAssertTrue(model.blemishes.isEmpty)
        XCTAssertTrue(model.isShowingOriginal)
        XCTAssertTrue(model.displayedImage.cgImage === original.cgImage)
        XCTAssertTrue(model.sourceImage.cgImage === original.cgImage)
        XCTAssertEqual(model.failure?.kind, .blemish)
        XCTAssertEqual(model.failure?.underlying, .retouchingFailed)
        XCTAssertTrue(model.failure?.diagnosticCode.hasPrefix("E_") == true)

        await remover.enqueue(.success(blemished))
        model.retry()
        await model.waitForRendering()

        XCTAssertNil(model.failure)
        XCTAssertEqual(model.blemishes.count, 1)
        XCTAssertTrue(model.displayedImage.cgImage === blemished.cgImage)
    }

    func testUndoFailureKeepsMarksAndRetryCanRemoveOne() async throws {
        let original = try SkinToolsTestFactory.image()
        let first = try SkinToolsTestFactory.image(color: .white)
        let second = try SkinToolsTestFactory.image(color: .black)
        let third = try SkinToolsTestFactory.image(color: .midGray)
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let remover = SkinToolsBlemishSpy(steps: [.success(first), .success(second)])
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: remover
        )

        model.addBlemish(at: NormalizedPoint(x: 0.3, y: 0.4))
        await model.waitForRendering()
        model.addBlemish(at: NormalizedPoint(x: 0.6, y: 0.5))
        await model.waitForRendering()
        XCTAssertEqual(model.blemishes.count, 2)
        XCTAssertTrue(model.displayedImage.cgImage === second.cgImage)

        await remover.enqueue(.failure(.retouchingFailed))
        model.undoBlemish()
        await model.waitForRendering()

        XCTAssertEqual(model.blemishes.count, 2, "A failed undo must not drop a mark")
        XCTAssertTrue(model.displayedImage.cgImage === second.cgImage)
        XCTAssertEqual(model.failure?.kind, .undo)

        await remover.enqueue(.success(third))
        model.retry()
        await model.waitForRendering()

        XCTAssertNil(model.failure)
        XCTAssertEqual(model.blemishes.count, 1)
        XCTAssertTrue(model.displayedImage.cgImage === third.cgImage)
    }

    func testSmoothingChangeRecomposesExistingMarksOnTheRetouchedBase() async throws {
        let original = try SkinToolsTestFactory.image()
        let retouched = try SkinToolsTestFactory.image(color: .white)
        let first = try SkinToolsTestFactory.image(color: .black)
        let second = try SkinToolsTestFactory.image(color: .midGray)
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let retoucher = SkinToolsRetouchSpy(steps: [.success(retouched)])
        let remover = SkinToolsBlemishSpy(steps: [.success(first), .success(second)])
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: retoucher,
            blemishRemover: remover
        )

        model.addBlemish(at: NormalizedPoint(x: 0.4, y: 0.6))
        await model.waitForRendering()
        XCTAssertEqual(model.blemishes.count, 1)
        XCTAssertTrue(model.displayedImage.cgImage === first.cgImage)

        model.setSmoothing(0.5)
        await model.waitForRendering()

        let retouchCalls = await retoucher.callCount()
        let parameters = await retoucher.lastParameters()
        let blemishCalls = await remover.callCount()
        XCTAssertEqual(retouchCalls, 1)
        XCTAssertEqual(
            parameters,
            SkinParameters(smoothing: 0.5, evenness: 0, blemish: 1)
        )
        XCTAssertEqual(blemishCalls, 2, "Existing marks are re-applied to the new base")
        XCTAssertEqual(model.blemishes.count, 1)
        XCTAssertTrue(model.displayedImage.cgImage === second.cgImage)
        XCTAssertTrue(model.sourceImage.cgImage === original.cgImage)
    }

    func testResetClearsEverythingAndReturnsToTheOriginal() async throws {
        let original = try SkinToolsTestFactory.image()
        let blemished = try SkinToolsTestFactory.image(color: .white)
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: SkinToolsBlemishSpy(steps: [.success(blemished)])
        )

        model.setSmoothing(0.5)
        model.setEvenness(0.3)
        await model.waitForRendering()

        model.beginBlemishMode()
        model.addBlemish(at: NormalizedPoint(x: 0.5, y: 0.5))
        await model.waitForRendering()
        XCTAssertTrue(model.canReset)

        model.reset()

        XCTAssertEqual(model.smoothing, 0)
        XCTAssertEqual(model.evenness, 0)
        XCTAssertTrue(model.blemishes.isEmpty)
        XCTAssertFalse(model.isBlemishMode)
        XCTAssertTrue(model.isAtOriginal)
        XCTAssertTrue(model.displayedImage.cgImage === original.cgImage)
        XCTAssertFalse(model.canReset)
        XCTAssertNil(model.failure)
        XCTAssertNil(model.notice)
    }

    func testCancelRenderingKeepsTheLastImageAndReportsCancellation() async throws {
        let original = try SkinToolsTestFactory.image()
        let processed = try SkinToolsTestFactory.image(color: .white)
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let gate = SkinToolsGatedRetoucher(output: processed)
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: gate,
            blemishRemover: SkinToolsBlemishSpy()
        )

        model.setSmoothing(0.5)
        await gate.waitUntilStarted()
        XCTAssertTrue(model.isRendering)
        XCTAssertTrue(model.isShowingOriginal)

        model.cancelRendering()
        await gate.release()
        await model.waitForRendering()

        XCTAssertFalse(model.isRendering)
        XCTAssertEqual(model.notice, .renderingCancelled)
        XCTAssertTrue(model.isShowingOriginal)
        XCTAssertTrue(model.displayedImage.cgImage === original.cgImage)
        XCTAssertNil(model.failure)
    }

    func testReplaceSourceResetsTheSkinArea() async throws {
        let original = try SkinToolsTestFactory.image()
        let replacement = try SkinToolsTestFactory.image(color: .white)
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let replacementAnalysis = try SkinToolsTestFactory.analysis(for: replacement)
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: SkinToolsBlemishSpy()
        )

        model.setSmoothing(0.5)
        await model.waitForRendering()

        model.replaceSource(replacement, analysis: replacementAnalysis)

        XCTAssertEqual(model.smoothing, 0)
        XCTAssertEqual(model.evenness, 0)
        XCTAssertTrue(model.blemishes.isEmpty)
        XCTAssertFalse(model.isBlemishMode)
        XCTAssertTrue(model.isShowingOriginal)
        XCTAssertTrue(model.displayedImage.cgImage === replacement.cgImage)
        XCTAssertTrue(model.sourceImage.cgImage === replacement.cgImage)
        XCTAssertEqual(model.analysis.imageSize, replacement.pixelSize)
    }

    func testBlemishLimitNoticeAndEditorParameterMapping() async throws {
        let original = try SkinToolsTestFactory.image()
        let first = try SkinToolsTestFactory.image(color: .white)
        let second = try SkinToolsTestFactory.image(color: .black)
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let remover = SkinToolsBlemishSpy(steps: [.success(first), .success(second)])
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: remover,
            configuration: .immediate(maximumBlemishes: 2)
        )

        model.setSmoothing(0.4)
        model.setEvenness(0.2)
        model.setRadius(0.03)
        await model.waitForRendering()

        model.addBlemish(at: NormalizedPoint(x: 0.2, y: 0.3))
        await model.waitForRendering()
        model.addBlemish(at: NormalizedPoint(x: 0.8, y: 0.7))
        await model.waitForRendering()

        // Each successful add recomposes the whole list: the first mark costs
        // one call, the second replays the first and adds the second.
        let callsBeforeLimit = await remover.callCount()

        model.addBlemish(at: NormalizedPoint(x: 0.5, y: 0.5))
        await model.waitForRendering()

        XCTAssertEqual(model.blemishes.count, 2)
        XCTAssertEqual(model.notice, .blemishLimitReached)
        let callsAfterLimit = await remover.callCount()
        XCTAssertEqual(
            callsAfterLimit,
            callsBeforeLimit,
            "A blocked mark must not call the engine"
        )

        XCTAssertEqual(
            model.skinParameters,
            SkinParameters(smoothing: 0.4, evenness: 0.2, blemish: 1)
        )
        XCTAssertEqual(model.manualAdjustments.smoothing, 0.4, accuracy: 0.0001)
        XCTAssertEqual(model.manualAdjustments.evenness, 0.2, accuracy: 0.0001)
        XCTAssertEqual(model.manualAdjustments.blemish, 1, accuracy: 0.0001)

        var editorAdjustments = ManualAdjustments(exposure: 0.5, faceSlim: 0.25)
        model.applySkinFields(to: &editorAdjustments)
        XCTAssertEqual(editorAdjustments.exposure, 0.5, accuracy: 0.0001)
        XCTAssertEqual(editorAdjustments.faceSlim, 0.25, accuracy: 0.0001)
        XCTAssertEqual(editorAdjustments.smoothing, 0.4, accuracy: 0.0001)
        XCTAssertEqual(editorAdjustments.evenness, 0.2, accuracy: 0.0001)
        XCTAssertEqual(editorAdjustments.blemish, 1, accuracy: 0.0001)

        let points = model.blemishPoints
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.first?.point, NormalizedPoint(x: 0.2, y: 0.3))
        XCTAssertEqual(points.first?.radius ?? 0, 0.03, accuracy: 0.0001)
        XCTAssertEqual(points.last?.point, NormalizedPoint(x: 0.8, y: 0.7))
    }

    func testDerivedPointAndRadiusClampingIsSafe() {
        let outOfRange = BlemishEdit(
            point: NormalizedPoint(x: -1, y: 2),
            radius: 1
        )
        XCTAssertEqual(outOfRange.point, NormalizedPoint(x: 0, y: 1))
        XCTAssertEqual(outOfRange.radius, SkinToolsLimits.maximumRadius, accuracy: 0.0001)

        let nonFinite = BlemishEdit(
            point: NormalizedPoint(x: .nan, y: .infinity),
            radius: .nan
        )
        XCTAssertEqual(nonFinite.point, NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(nonFinite.radius, SkinToolsLimits.defaultRadius, accuracy: 0.0001)
    }
}
