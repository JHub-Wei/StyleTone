import XCTest
import StyleToneCore
import StyleToneGeometry
import StyleToneImaging
import StyleToneLearning
import StyleTonePersistence
import StyleToneRetouch
import StyleToneUI
import StyleToneVision
@testable import StyleTone

/// Construction tests for the live A6 graph.
///
/// These only instantiate services; they do not load a profile, decode a photo
/// or write an export file.
@MainActor
final class A6LiveWiringTests: XCTestCase {
    private static let liveDependencies = A6Dependencies.live()

    func testLiveRootDependenciesUseRealServices() {
        let dependencies = Self.liveDependencies

        XCTAssertTrue(dependencies.profileStore is SwiftDataStyleProfileStore)
        XCTAssertTrue(dependencies.learner is StyleLearningEngine)
        XCTAssertTrue(dependencies.pairQualityAnalyzer is VisionPairQualityAnalyzer)
        XCTAssertTrue(dependencies.portraitAnalyzer is VisionPortraitAnalyzer)
        XCTAssertTrue(dependencies.retoucher is SkinRetoucher)
        XCTAssertTrue(dependencies.blemishRemover is SkinRetoucher)
        XCTAssertTrue(dependencies.geometryRenderer is GeometryRenderingEngine)
        XCTAssertTrue(dependencies.exporter is FileImageExporter)
        XCTAssertTrue(dependencies.quota is UnlimitedExportQuota)
    }

    func testEditorDependenciesAreWiredToTheRealEngines() {
        let dependencies = Self.liveDependencies
        let editor = dependencies.editorDependencies()

        XCTAssertTrue(editor.analyzer is VisionPortraitAnalyzer)
        XCTAssertTrue(editor.retoucher is SkinRetoucher)
        XCTAssertTrue(editor.blemishRemover is SkinRetoucher)
        XCTAssertTrue(editor.geometryRenderer is GeometryRenderingEngine)
        XCTAssertTrue(editor.exporter is FileImageExporter)
        XCTAssertTrue(editor.renderer is EditorRenderer)
        XCTAssertTrue(editor.styleProvider is StoreEditorStyleProvider)
    }

    func testExportDependenciesUsePhotoKitAndAnAllowAllPhaseAQuota() {
        let dependencies = Self.liveDependencies
        let export = dependencies.exportDependencies()

        XCTAssertTrue(export.renderer is EditorRenderer)
        XCTAssertTrue(export.exporter is FileImageExporter)
        XCTAssertTrue(export.quota is UnlimitedExportQuota)
        XCTAssertEqual(
            export.fileStore.directory.lastPathComponent,
            ExportTemporaryFileStore.directoryName
        )
        XCTAssertTrue(export.supportsSystemShare)

        #if os(iOS)
        XCTAssertTrue(export.photoLibrary is PhotoKitExportPhotoLibrary)
        #else
        XCTAssertTrue(export.photoLibrary is UnavailableExportPhotoLibrary)
        #endif
    }

    func testPairingDependenciesUseLiveAnalyzerAndImporter() {
        let dependencies = Self.liveDependencies
        let pairing = dependencies.pairingDependencies()

        XCTAssertTrue(pairing.qualityAnalyzer is VisionPairQualityAnalyzer)
        XCTAssertTrue(pairing.imageImporter is PairingImageImporter)
        XCTAssertTrue(pairing.sessionStore is InMemoryPairingSessionStore)
        XCTAssertTrue(pairing.availabilityProvider is SystemPairingPickerAvailability)
        XCTAssertEqual(pairing.target, .three)
    }

    func testSettingsLiveGraphCanBeConstructed() {
        let dependencies = Self.liveDependencies
        let settings = SettingsDependencies.live(profileStore: dependencies.profileStore)
        XCTAssertNotNil(settings)
    }

    func testInfoPlistDeclaresPhotoPrivacyAndNoCameraPermission() {
        let info = Bundle.main.infoDictionary ?? [:]

        let addUsage = info["NSPhotoLibraryAddUsageDescription"] as? String
        XCTAssertFalse(addUsage?.isEmpty ?? true)

        let readUsage = info["NSPhotoLibraryUsageDescription"] as? String
        XCTAssertFalse(readUsage?.isEmpty ?? true)

        XCTAssertNil(info["NSCameraUsageDescription"])
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
    }
}
