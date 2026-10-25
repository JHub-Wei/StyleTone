import CoreGraphics
import StyleToneCore
import XCTest
@testable import StyleToneUI

@MainActor
final class SkinToolsPanelTests: XCTestCase {
    func testPanelBuildsForAFacePhoto() throws {
        let image = try SkinToolsTestFactory.image()
        let analysis = try SkinToolsTestFactory.analysis(for: image)
        let model = SkinToolsTestFactory.model(
            image: image,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: SkinToolsBlemishSpy()
        )

        let panel = SkinToolsPanel(model: model)
        XCTAssertFalse(panel.isHiddenForUnavailablePhoto)
        XCTAssertFalse(model.isBlemishMode)
        XCTAssertTrue(model.isAtOriginal)

        let panelWithCallback = SkinToolsPanel(model: model) { _ in }
        XCTAssertFalse(panelWithCallback.isHiddenForUnavailablePhoto)
    }

    func testNoFacePanelIsDisabledOrHidden() throws {
        let image = try SkinToolsTestFactory.image()
        let analysis = try SkinToolsTestFactory.analysis(for: image, faceCount: 0)
        let model = SkinToolsTestFactory.model(
            image: image,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: SkinToolsBlemishSpy()
        )

        let disabled = SkinToolsPanel(model: model, unavailableBehavior: .disable)
        let hidden = SkinToolsPanel(model: model, unavailableBehavior: .hide)

        XCTAssertFalse(disabled.isHiddenForUnavailablePhoto)
        XCTAssertTrue(hidden.isHiddenForUnavailablePhoto)
        XCTAssertEqual(model.unavailableReason, .noFace)
        XCTAssertFalse(model.areControlsEnabled)
    }

    func testUnavailableBehaviorDefaultsToDisable() throws {
        let image = try SkinToolsTestFactory.image()
        let analysis = try SkinToolsTestFactory.analysis(for: image, faceCount: 0)
        let model = SkinToolsTestFactory.model(
            image: image,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: SkinToolsBlemishSpy()
        )

        let panel = SkinToolsPanel(model: model)
        XCTAssertFalse(panel.isHiddenForUnavailablePhoto)
    }

    func testFullBlemishRepairUIScript() async throws {
        let original = try SkinToolsTestFactory.image()
        let retouched = try SkinToolsTestFactory.image(color: .midGray)
        let blemished = try SkinToolsTestFactory.image(color: .white)
        let analysis = try SkinToolsTestFactory.analysis(for: original)
        let retoucher = SkinToolsRetouchSpy(
            steps: [.success(retouched), .success(retouched), .success(retouched)]
        )
        let remover = SkinToolsBlemishSpy(steps: [.success(blemished)])
        let model = SkinToolsTestFactory.model(
            image: original,
            analysis: analysis,
            retoucher: retoucher,
            blemishRemover: remover
        )
        _ = SkinToolsPanel(model: model)

        // 1. Move the smoothing slider.
        model.setSmoothing(0.5)
        await model.waitForRendering()
        XCTAssertFalse(model.isShowingOriginal)

        // 2. Enter the point-picking mode.
        model.beginBlemishMode()
        XCTAssertTrue(model.isBlemishMode)

        // 3. Map a tap in a 300×400 canvas to the photo, then repair it.
        let geometry = SkinToolsImageGeometry(
            containerSize: CGSize(width: 300, height: 400),
            imageSize: CGSize(width: 96, height: 128)
        )
        let tap = try XCTUnwrap(geometry.normalizedPoint(at: CGPoint(x: 180, y: 280)))
        XCTAssertEqual(tap.x, 0.6, accuracy: 0.0001)
        XCTAssertEqual(tap.y, 0.7, accuracy: 0.0001)

        model.setRadius(0.025)
        model.addBlemish(at: tap)
        await model.waitForRendering()

        XCTAssertEqual(model.blemishes.count, 1)
        XCTAssertTrue(model.displayedImage.cgImage === blemished.cgImage)
        XCTAssertEqual(model.blemishPoints.first?.point, tap)
        XCTAssertEqual(model.blemishPoints.first?.radius ?? 0, 0.025, accuracy: 0.0001)

        // 4. Undo restores the retouched base and leaves the UI in picking mode.
        model.undoBlemish()
        await model.waitForRendering()

        XCTAssertEqual(model.blemishes.count, 0)
        XCTAssertTrue(model.displayedImage.cgImage === retouched.cgImage)
        XCTAssertTrue(model.isBlemishMode)

        // 5. The identifiers a UI test would query are the frozen ones.
        XCTAssertEqual(
            SkinToolsAccessibilityID.smoothingSlider.rawValue,
            "editor.smoothingSlider"
        )
        XCTAssertEqual(
            SkinToolsAccessibilityID.blemishCanvas.rawValue,
            "editor.blemishCanvas"
        )
        XCTAssertEqual(
            SkinToolsAccessibilityID.blemishUndoButton.rawValue,
            "editor.blemishUndoButton"
        )
    }

    func testAcceptanceConstantsMatchTheCoreContract() {
        XCTAssertEqual(SkinToolsLimits.minimumSmoothing, 0, accuracy: 0.0001)
        XCTAssertEqual(SkinToolsLimits.maximumSmoothing, 1, accuracy: 0.0001)
        XCTAssertEqual(SkinToolsLimits.minimumEvenness, 0, accuracy: 0.0001)
        XCTAssertEqual(SkinToolsLimits.maximumEvenness, 1, accuracy: 0.0001)
        XCTAssertEqual(SkinToolsLimits.minimumRadius, 0.005, accuracy: 0.0001)
        XCTAssertEqual(SkinToolsLimits.maximumRadius, 0.08, accuracy: 0.0001)
        XCTAssertEqual(SkinToolsLimits.minimumZoom, 1, accuracy: 0.0001)
        XCTAssertEqual(SkinToolsLimits.maximumZoom, 6, accuracy: 0.0001)
        XCTAssertGreaterThan(SkinToolsLimits.maximumBlemishes, 0)
        XCTAssertEqual(SkinToolsUnavailableBehavior.allCases, [.disable, .hide])
        XCTAssertEqual(SkinToolsNotice.allCases, [.renderingCancelled, .blemishLimitReached])
    }

    func testConfigurationIsSanitized() {
        let configuration = SkinToolsConfiguration(
            renderDelay: .milliseconds(-1),
            defaultRadius: 10,
            maximumBlemishes: 0,
            minimumZoom: 0.5,
            maximumZoom: 0.2
        )

        XCTAssertEqual(configuration.renderDelay, .zero)
        XCTAssertEqual(configuration.defaultRadius, SkinToolsLimits.maximumRadius, accuracy: 0.0001)
        XCTAssertEqual(configuration.maximumBlemishes, 1)
        XCTAssertEqual(configuration.minimumZoom, 1, accuracy: 0.0001)
        XCTAssertEqual(configuration.maximumZoom, 1, accuracy: 0.0001)
        XCTAssertEqual(SkinToolsConfiguration.standard.defaultRadius, SkinToolsLimits.defaultRadius, accuracy: 0.0001)
    }

    func testZoomControlsClampToConfiguredRange() throws {
        let image = try SkinToolsTestFactory.image()
        let analysis = try SkinToolsTestFactory.analysis(for: image)
        let model = SkinToolsTestFactory.model(
            image: image,
            analysis: analysis,
            retoucher: SkinToolsRetouchSpy(),
            blemishRemover: SkinToolsBlemishSpy()
        )

        XCTAssertEqual(model.zoomScale, 1, accuracy: 0.0001)
        XCTAssertFalse(model.canZoomOut)
        XCTAssertTrue(model.canZoomIn)

        model.zoomIn()
        XCTAssertEqual(model.zoomScale, 2, accuracy: 0.0001)
        model.setZoom(100)
        XCTAssertEqual(model.zoomScale, 6, accuracy: 0.0001)
        XCTAssertFalse(model.canZoomIn)
        model.zoomOut()
        XCTAssertEqual(model.zoomScale, 5, accuracy: 0.0001)
        model.resetZoom()
        XCTAssertEqual(model.zoomScale, 1, accuracy: 0.0001)
        XCTAssertFalse(model.canResetZoom)
    }
}
