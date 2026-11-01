import Foundation
import Observation
import StyleToneCore
import StyleToneImaging
import StyleToneUI

/// Host state for the Phase A self-use flow.
///
/// The model owns the long-lived store/services, the pure `A6FlowState` machine
/// and the screen view models. Views only render its state and call its
/// actions; no screen constructs services on its own.
///
/// Side effects run in the order the UI needs them:
/// * profile saves finish before the flow moves to the editor;
/// * calibration receives the exact samples pairing handed over;
/// * returning to the editor reloads the active style so a recalibration or a
///   natural-default choice is visible immediately.
@MainActor
@Observable
final class A6AppModel {
    // MARK: Long-lived graph

    let dependencies: A6Dependencies
    let editorModel: EditorViewModel
    let exportDependencies: ExportDependencies

    // MARK: Observable flow state

    private(set) var flow = A6FlowState()
    private(set) var samples: [PairSample] = []
    private(set) var profile: StyleProfile?
    private(set) var calibrationModel: CalibrationViewModel?
    private(set) var pairingDependencies: PairingDependencies
    private(set) var isSavingProfile = false
    private(set) var errorMessage: String?

    // MARK: Private state

    private var didStart = false
    private var cachedSettingsDependencies: SettingsDependencies?

    // MARK: Init

    init(dependencies: A6Dependencies = .live()) {
        self.dependencies = dependencies
        self.editorModel = EditorViewModel(dependencies: dependencies.editorDependencies())
        self.exportDependencies = dependencies.exportDependencies()
        self.pairingDependencies = dependencies.pairingDependencies()
    }

    // MARK: Launch

    /// Loads the active profile once and chooses welcome vs. editor.
    ///
    /// A store failure is reported and treated like "no profile": Phase A can
    /// always fall back to the natural default, so the app must boot even if
    /// the local index needs recovery.
    func start() async {
        guard !didStart else { return }
        didStart = true

        do {
            let active = try await dependencies.profileStore.loadActive()
            profile = active
            _ = flow.reduce(.launch(hasProfile: active != nil))
        } catch {
            profile = nil
            _ = flow.reduce(.launch(hasProfile: false))
            report(A6Copy.profileLoadFailed)
        }
    }

    // MARK: Pairing / calibration

    /// Enters pairing. From calibration this restarts with a fresh session;
    /// from the editor it is the recalibration entry point.
    func beginPairing() {
        guard flow.reduce(.beginPairing) else { return }
        samples = []
        calibrationModel = nil
        pairingDependencies = dependencies.pairingDependencies()
    }

    /// Hand-off from `PairingScreen.onFinish`.
    ///
    /// Pairing already filtered rejected pairs and enforced the three-pair
    /// minimum, so the samples are passed through unchanged.
    func finishPairing(_ newSamples: [PairSample]) {
        guard flow.reduce(.finishPairing) else { return }
        samples = newSamples
        calibrationModel = CalibrationViewModel(
            samples: newSamples,
            learner: dependencies.learner,
            profileStore: dependencies.profileStore,
            progressStore: CalibrationInMemoryProgressStore(),
            dateProvider: dependencies.dateProvider
        )
    }

    /// Pairing was skipped. Persist the natural default, then show the editor.
    func skipPairing() async {
        await saveNaturalDefault(reducing: .skipPairing)
    }

    /// Minimal welcome escape and the explicit "use natural default" action.
    func useNaturalDefault() async {
        await saveNaturalDefault(reducing: .useNaturalDefault)
    }

    /// `CalibrationView.onContinue` — persists the learned profile and opens the
    /// editor.
    ///
    /// The calibration model already saved the profile before showing the
    /// result, so this second save is idempotent; it makes the host contract
    /// explicit and keeps the flow closed even if the view model's save was
    /// skipped by a future change.
    func completeCalibration(_ newProfile: StyleProfile) async {
        guard flow.stage == .calibration, !isSavingProfile else { return }
        isSavingProfile = true
        defer { isSavingProfile = false }

        do {
            try await dependencies.profileStore.save(newProfile)
            profile = newProfile
            guard flow.reduce(.completeCalibration) else { return }
            calibrationModel = nil
            samples = []
            await editorModel.reloadStyle()
        } catch {
            report(A6Copy.profileSaveFailed)
        }
    }

    /// Calibration's "save for later" close button.
    ///
    /// The calibration draft is already paused by the view. This only decides
    /// where to go: back to the editor when a profile still exists, otherwise
    /// back to the minimal welcome screen.
    func cancelCalibration() async {
        guard flow.stage == .calibration, !isSavingProfile else { return }

        do {
            if let active = try await dependencies.profileStore.loadActive() {
                profile = active
            }
        } catch {
            // Keep the last known profile; routing below already handles both
            // cases without claiming a save succeeded.
        }

        calibrationModel = nil
        samples = []
        _ = flow.reduce(.cancelCalibration(hasProfile: profile != nil))
    }

    // MARK: Editor image input

    /// Decodes picker data through the real `ImageLoader` and starts an editor
    /// session. Returns `false` for unreadable data without mutating the
    /// current image.
    func loadEditorImage(from data: Data) async -> Bool {
        do {
            let image = try await dependencies.imageLoader.load(data: data)
            await editorModel.load(image: image)
            return true
        } catch is CancellationError {
            return false
        } catch {
            return false
        }
    }

    // MARK: Export hand-off

    /// Builds the full-resolution request for the export screen from the
    /// editor's current state.
    func makeExportSource() -> ExportSource? {
        guard let image = editorModel.image, let analysis = editorModel.analysis else {
            return nil
        }
        let request = RenderRequest(
            image: image,
            analysis: analysis,
            style: editorModel.style,
            strength: editorModel.edits.strength,
            adjustments: editorModel.edits.adjustments,
            backgroundProtection: editorModel.edits.backgroundProtection,
            blemishPoints: editorModel.edits.blemishPoints
        )
        return ExportSource(request: request, preview: editorModel.displayedImage)
    }

    /// The editor's own export writes a temporary file before the host hands
    /// the render to `ExportScreen`. That intermediate file is not user data
    /// and must not accumulate in `tmp/`.
    func discardTemporaryExport(_ result: ExportResult) {
        _ = ExportTemporaryFileStore().remove(result.url)
    }

    // MARK: Settings

    /// Lazily builds the live settings graph. Cached so repeated body
    /// evaluations do not recreate diagnostics services or UserDefaults
    /// readers.
    func settingsDependencies() -> SettingsDependencies? {
        if let cachedSettingsDependencies {
            return cachedSettingsDependencies
        }
        let created = SettingsDependencies.live(profileStore: dependencies.profileStore)
        cachedSettingsDependencies = created
        return created
    }

    /// Called after `SettingsScreen` verified that every local store is empty.
    func handleAllDataDeleted() {
        profile = nil
        samples = []
        calibrationModel = nil
        cachedSettingsDependencies = nil
        _ = flow.reduce(.allDataDeleted)
    }

    // MARK: Errors

    func report(_ message: String) {
        errorMessage = message
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Private

    private func saveNaturalDefault(reducing event: A6FlowEvent) async {
        guard !isSavingProfile else { return }
        isSavingProfile = true
        defer { isSavingProfile = false }

        let natural = StyleProfile.editorNaturalDefault
        do {
            try await dependencies.profileStore.save(natural)
            profile = natural
            guard flow.reduce(event) else { return }
            calibrationModel = nil
            samples = []
            await editorModel.reloadStyle()
        } catch {
            report(A6Copy.profileSaveFailed)
        }
    }
}
