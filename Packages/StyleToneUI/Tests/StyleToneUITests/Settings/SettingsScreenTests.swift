import StyleToneCore
import StyleToneUI
import TestShared
import XCTest

/// Screen-level composition.
///
/// The package has no XCUITest bundle (that arrives with WP-24); these tests
/// build the view and drive the exact states the screen renders, while
/// ``SettingsAccessibilityTests`` locks the identifiers an XCUITest will query.
@MainActor
final class SettingsScreenTests: XCTestCase {
    func testScreenBuildsWithPlaceholderDependencies() {
        let viewModel = SettingsViewModel(dependencies: .placeholder)
        _ = SettingsScreen(viewModel: viewModel)
        XCTAssertEqual(viewModel.phase, .loading)
        XCTAssertFalse(viewModel.isDiagnosticsEnabled)
    }

    func testScreenBuildsInEveryDeletionStage() async {
        let fixture = SettingsTestFactory.diagnostics()
        let deleter = SettingsSequenceDeleter(reports: [SettingsTestFactory.report()])
        let viewModel = SettingsTestFactory.viewModel(
            diagnostics: fixture.service,
            deleter: deleter
        )
        await viewModel.load()

        _ = SettingsScreen(viewModel: viewModel)
        viewModel.requestDelete()
        _ = SettingsScreen(viewModel: viewModel)
        viewModel.continueDelete()
        _ = SettingsScreen(viewModel: viewModel)
        await viewModel.confirmDeletion()
        _ = SettingsScreen(viewModel: viewModel)
        XCTAssertEqual(viewModel.deleteStage, .deleted)
    }

    func testScreenInitializerAcceptsTheDeletionHandoff() {
        let fixture = SettingsTestFactory.diagnostics()
        let viewModel = SettingsTestFactory.viewModel(diagnostics: fixture.service)
        var handedOff = false
        _ = SettingsScreen(viewModel: viewModel) {
            handedOff = true
        }
        XCTAssertFalse(handedOff)
    }

    func testPlaceholderDependenciesExposeAllSections() async {
        let dependencies = SettingsDependencies.placeholder
        let viewModel = SettingsViewModel(dependencies: dependencies)

        XCTAssertEqual(viewModel.version.marketingVersion, "0.1.0")
        XCTAssertFalse(viewModel.support.email.isEmpty)
        XCTAssertFalse(viewModel.licenses.application.isEmpty)
        XCTAssertFalse(viewModel.licenses.hasThirdPartyComponents)
        XCTAssertTrue(SettingsDiagnosticCode.isWellFormed(viewModel.diagnosticCode))

        await viewModel.load()
        XCTAssertEqual(viewModel.phase, .ready)
        XCTAssertFalse(viewModel.isDiagnosticsEnabled)
    }

    func testDiagnosticsEntityCountDrivesTheVisibleCopy() async {
        let fixture = SettingsTestFactory.diagnostics(
            enabled: true,
            entries: [SettingsTestFactory.entry(.appLaunch)]
        )
        let viewModel = SettingsTestFactory.viewModel(diagnostics: fixture.service)
        await viewModel.load()

        // One stored entry plus the settings-opened event recorded by load.
        XCTAssertEqual(viewModel.diagnosticEntryCount, 2)
        XCTAssertEqual(SettingsCopy.entriesText(count: viewModel.diagnosticEntryCount),
                       "2 entries stored on this iPhone.")
    }
}
