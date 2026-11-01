import XCTest
import StyleToneCore
import StyleToneUI
@testable import StyleTone

/// Flow-level tests for the A6 host model with mock persistence and fail-closed
/// services. No photo decode, export or SwiftData write happens here.
@MainActor
final class A6AppModelTests: XCTestCase {
    func testStartWithoutProfileShowsWelcome() async {
        let store = A6MockProfileStore()
        let model = A6AppModel(dependencies: .testing(profileStore: store))

        await model.start()

        XCTAssertEqual(model.flow.stage, .welcome)
        XCTAssertNil(model.profile)
        let saved = await store.savedProfiles
        XCTAssertTrue(saved.isEmpty)
    }

    func testStartWithExistingProfileGoesStraightToEditor() async {
        let stored = StyleProfile(pairCount: 5, confidence: .standard)
        let store = A6MockProfileStore(active: stored)
        let model = A6AppModel(dependencies: .testing(profileStore: store))

        await model.start()

        XCTAssertEqual(model.flow.stage, .editor)
        XCTAssertEqual(model.profile, stored)
    }

    func testWelcomeNaturalDefaultSavesProfileBeforeEnteringEditor() async {
        let store = A6MockProfileStore()
        let model = A6AppModel(dependencies: .testing(profileStore: store))
        await model.start()

        await model.useNaturalDefault()

        XCTAssertEqual(model.flow.stage, .editor)
        XCTAssertEqual(model.profile, StyleProfile.editorNaturalDefault)
        let saved = await store.savedProfiles
        XCTAssertEqual(saved.last, StyleProfile.editorNaturalDefault)
    }

    func testPairingHandoffCreatesCalibrationViewModel() async {
        let store = A6MockProfileStore()
        let model = A6AppModel(dependencies: .testing(profileStore: store))
        await model.start()

        model.beginPairing()
        XCTAssertEqual(model.flow.stage, .pairing)

        model.finishPairing([])

        XCTAssertEqual(model.flow.stage, .calibration)
        XCTAssertNotNil(model.calibrationModel)
        XCTAssertTrue(model.samples.isEmpty)
    }

    func testSkipPairingUsesNaturalDefault() async {
        let store = A6MockProfileStore()
        let model = A6AppModel(dependencies: .testing(profileStore: store))
        await model.start()
        model.beginPairing()

        await model.skipPairing()

        XCTAssertEqual(model.flow.stage, .editor)
        let saved = await store.savedProfiles
        XCTAssertEqual(saved.last, StyleProfile.editorNaturalDefault)
    }

    func testCompleteCalibrationPersistsProfileAndOpensEditor() async {
        let store = A6MockProfileStore()
        let model = A6AppModel(dependencies: .testing(profileStore: store))
        await model.start()
        model.beginPairing()
        model.finishPairing([])

        let learned = StyleProfile(pairCount: 3, confidence: .trial, tags: ["test.a6"])
        await model.completeCalibration(learned)

        XCTAssertEqual(model.flow.stage, .editor)
        XCTAssertEqual(model.profile, learned)
        XCTAssertNil(model.calibrationModel)
        let saved = await store.savedProfiles
        XCTAssertEqual(saved.last, learned)
    }

    func testDeleteAllDataResetsToWelcome() async {
        let store = A6MockProfileStore(active: StyleProfile(pairCount: 3))
        let model = A6AppModel(dependencies: .testing(profileStore: store))
        await model.start()
        XCTAssertEqual(model.flow.stage, .editor)

        try? await store.deleteAll()
        model.handleAllDataDeleted()

        XCTAssertEqual(model.flow.stage, .welcome)
        XCTAssertNil(model.profile)
    }
}
