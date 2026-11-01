import PhotosUI
import StyleToneCore
import StyleToneUI
import SwiftUI

/// Root of the Phase A self-use app.
///
/// It replaces `WP00PlaceholderView` / `AppShellView` as the entry flow while
/// keeping the WP-03 shell and placeholders available for previews. Every
/// screen it shows is a real product screen:
///
/// * minimal local-only welcome when no profile exists;
/// * `PairingScreen` with the live Vision analyzer and PHPicker;
/// * `CalibrationView` with `StyleLearningEngine` and the SwiftData store;
/// * `EditorView` with the real analysis/retouch/geometry/export engines;
/// * `ExportScreen` with add-only PhotoKit;
/// * `SettingsScreen` with the live data-deletion coordinator.
///
/// There is deliberately no account, paywall, StoreKit, style-card or full
/// onboarding stage in this build.
@MainActor
struct A6RootView: View {
    @State private var model: A6AppModel

    init(dependencies: A6Dependencies = .live()) {
        _model = State(initialValue: A6AppModel(dependencies: dependencies))
    }

    var body: some View {
        Group {
            switch model.flow.stage {
            case .launching:
                A6LaunchView()

            case .welcome:
                A6WelcomeView(
                    isBusy: model.isSavingProfile,
                    onStartPairing: { model.beginPairing() },
                    onNaturalDefault: {
                        Task { await model.useNaturalDefault() }
                    }
                )

            case .pairing:
                NavigationStack {
                    PairingScreen(
                        dependencies: model.pairingDependencies,
                        onFinish: { samples, _ in
                            model.finishPairing(samples)
                        },
                        onSkip: { _ in
                            Task { await model.skipPairing() }
                        }
                    )
                }

            case .calibration:
                if let calibrationModel = model.calibrationModel {
                    NavigationStack {
                        CalibrationView(
                            model: calibrationModel,
                            onAddPairs: { model.beginPairing() },
                            onContinue: { profile in
                                Task { await model.completeCalibration(profile) }
                            },
                            onClose: {
                                Task { await model.cancelCalibration() }
                            }
                        )
                    }
                } else {
                    // Defensive: the calibration view model is created in the
                    // same transaction as the transition, so this only shows
                    // during a missing-store edge case.
                    A6LaunchView()
                }

            case .editor:
                A6MainView(model: model)
            }
        }
        .background { A6ScreenBackground() }
        .styleToneThemeProvider()
        .preferredColorScheme(.dark)
        .task { await model.start() }
        .alert(
            A6Copy.alertTitle,
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.dismissError()
                    }
                }
            )
        ) {
            Button(role: .cancel) {
                model.dismissError()
            } label: {
                Text(verbatim: A6Copy.okButton)
            }
        } message: {
            if let message = model.errorMessage {
                Text(verbatim: message)
            }
        }
    }
}

// MARK: - Background

private struct A6ScreenBackground: View {
    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        theme.color(.background)
            .ignoresSafeArea()
    }
}

// MARK: - Launch

@MainActor
private struct A6LaunchView: View {
    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.md) {
            ProgressView()
                .tint(theme.color(.accent))
                .accessibilityHidden(true)

            Text(verbatim: A6Copy.launching)
                .styleToneText(.body, color: .textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.shellRoot.rawValue)
    }
}

// MARK: - Minimal welcome

/// The Phase A replacement for WP-22 onboarding: two exits and a privacy note,
/// no account and no demo carousel.
@MainActor
private struct A6WelcomeView: View {
    let isBusy: Bool
    let onStartPairing: @MainActor () -> Void
    let onNaturalDefault: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    Text(verbatim: A6Copy.welcomeTitle)
                        .styleToneText(.display)

                    Text(verbatim: A6Copy.welcomeSubtitle)
                        .styleToneText(.body, color: .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: theme.spacing.md) {
                    PrimaryButton(
                        A6Copy.startPairingButton,
                        systemImage: "rectangle.on.rectangle",
                        isLoading: isBusy,
                        isEnabled: !isBusy,
                        accessibilityID: AccessibilityID.onboardingStartButton.rawValue
                    ) {
                        onStartPairing()
                    }

                    PrimaryButton(
                        A6Copy.naturalDefaultButton,
                        systemImage: "leaf",
                        role: .secondary,
                        isEnabled: !isBusy,
                        accessibilityID: AccessibilityID.onboardingNaturalDefaultButton.rawValue
                    ) {
                        onNaturalDefault()
                    }
                }

                privacyNote
            }
            .padding(.horizontal, theme.spacing.screenHorizontal)
            .padding(.vertical, theme.spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier(AccessibilityID.shellRoot.rawValue)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: theme.spacing.xs) {
            Image(systemName: "lock.shield")
                .font(theme.typography.font(.caption))
                .foregroundStyle(theme.color(.textTertiary))
                .accessibilityHidden(true)

            Text(verbatim: A6Copy.welcomeNote)
                .styleToneText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Editor + settings tabs

private enum A6Tab: Hashable {
    case editor
    case settings
}

@MainActor
private struct A6MainView: View {
    let model: A6AppModel

    @State private var selection: A6Tab = .editor
    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                A6EditorHostView(model: model)
            }
            .tabItem {
                tabLabel(A6Copy.editorTab, systemImage: "slider.horizontal.3")
            }
            .tag(A6Tab.editor)

            NavigationStack {
                A6SettingsHostView(model: model)
            }
            .tabItem {
                tabLabel(A6Copy.settingsTab, systemImage: "gearshape")
            }
            .tag(A6Tab.settings)
        }
        .tint(theme.color(.accent))
    }

    private func tabLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(verbatim: title)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

// MARK: - Editor host

/// Hosts the real `EditorView` and supplies the two callbacks it cannot own:
/// photo picking (PhotosPicker/`ImageLoader`) and the export destination.
///
/// The editor's built-in export button renders and encodes a temporary file;
/// the host discards that intermediate file and opens `ExportScreen`, which
/// performs the add-only PhotoKit save or system share from the same render
/// request.
@MainActor
private struct A6EditorHostView: View {
    let model: A6AppModel

    @State private var isPhotoPickerPresented = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isImporting = false
    @State private var isRecalibrateDialogPresented = false
    @State private var exportPresentation: A6ExportPresentation?

    var body: some View {
        EditorView(
            model: model.editorModel,
            onAddPhoto: {
                isPhotoPickerPresented = true
            },
            onOpenStyle: {
                isRecalibrateDialogPresented = true
            },
            onExported: { result in
                model.discardTemporaryExport(result)
                guard let source = model.makeExportSource() else {
                    model.report(A6Copy.exportUnavailable)
                    return
                }
                exportPresentation = A6ExportPresentation(source: source)
            }
        )
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $pickedPhoto,
            matching: .images
        )
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { @MainActor in
                await importPhoto(item)
            }
        }
        .overlay {
            if isImporting {
                LoadingView(
                    message: A6Copy.importingPhoto,
                    style: .overlay,
                    accessibilityID: AccessibilityID.designSystemLoading.rawValue
                )
            }
        }
        .confirmationDialog(
            A6Copy.recalibrateTitle,
            isPresented: $isRecalibrateDialogPresented,
            titleVisibility: .visible
        ) {
            Button {
                model.beginPairing()
            } label: {
                Text(verbatim: A6Copy.recalibrateStart)
            }

            Button(role: .cancel) {} label: {
                Text(verbatim: A6Copy.cancelButton)
            }
        } message: {
            Text(verbatim: A6Copy.recalibrateMessage)
        }
        .sheet(item: $exportPresentation) { presentation in
            NavigationStack {
                ExportScreen(
                    source: presentation.source,
                    dependencies: model.exportDependencies,
                    onClose: {
                        exportPresentation = nil
                    }
                )
            }
            .styleToneThemeProvider()
            .preferredColorScheme(.dark)
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        isImporting = true
        defer {
            isImporting = false
            pickedPhoto = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  !data.isEmpty
            else {
                model.report(A6Copy.photoImportFailed)
                return
            }

            let loaded = await model.loadEditorImage(from: data)
            if !loaded {
                model.report(A6Copy.photoImportFailed)
            }
        } catch is CancellationError {
            return
        } catch {
            model.report(A6Copy.photoImportFailed)
        }
    }
}

private struct A6ExportPresentation: Identifiable {
    let id = UUID()
    let source: ExportSource
}

// MARK: - Settings host

@MainActor
private struct A6SettingsHostView: View {
    let model: A6AppModel

    var body: some View {
        Group {
            if let dependencies = model.settingsDependencies() {
                SettingsScreen(
                    dependencies: dependencies,
                    onAllDataDeleted: {
                        model.handleAllDataDeleted()
                    }
                )
            } else {
                A6FallbackSettingsView(
                    profileStore: model.dependencies.profileStore,
                    onAllDataDeleted: {
                        model.handleAllDataDeleted()
                    }
                )
            }
        }
    }
}

/// Only used when the sandbox locations cannot be resolved and the full WP-21
/// settings screen cannot be constructed. It still offers a verified
/// delete-all-data path and the local-privacy copy; it is not a placeholder.
@MainActor
private struct A6FallbackSettingsView: View {
    let profileStore: any StyleProfileStore
    let onAllDataDeleted: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme
    @State private var isConfirmingDeletion = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sectionGap) {
                Text(verbatim: A6Copy.settingsTitle)
                    .styleToneText(.display)

                SectionHeader(
                    title: A6Copy.privacyTitle,
                    subtitle: A6Copy.privacyBody
                )

                VStack(alignment: .leading, spacing: theme.spacing.md) {
                    PrimaryButton(
                        A6Copy.deleteDataButton,
                        systemImage: "trash",
                        role: .destructive,
                        isLoading: isDeleting,
                        isEnabled: !isDeleting,
                        accessibilityID: AccessibilityID.settingsDeleteDataButton.rawValue
                    ) {
                        isConfirmingDeletion = true
                    }

                    Text(verbatim: A6Copy.deleteHint)
                        .styleToneText(.caption, color: .textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(theme.spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    theme.color(.surface),
                    in: RoundedRectangle(
                        cornerRadius: theme.radii.card,
                        style: .continuous
                    )
                )
            }
            .padding(.horizontal, theme.spacing.screenHorizontal)
            .padding(.vertical, theme.spacing.screenVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(theme.color(.background).ignoresSafeArea())
        .navigationTitle(Text(verbatim: A6Copy.settingsTitle))
        .confirmationDialog(
            A6Copy.deleteTitle,
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                deleteAll()
            } label: {
                Text(verbatim: A6Copy.deleteConfirmButton)
            }

            Button(role: .cancel) {} label: {
                Text(verbatim: A6Copy.cancelButton)
            }
        } message: {
            Text(verbatim: A6Copy.deleteMessage)
        }
        .alert(
            A6Copy.alertTitle,
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button(role: .cancel) {
                errorMessage = nil
            } label: {
                Text(verbatim: A6Copy.okButton)
            }
        } message: {
            if let errorMessage {
                Text(verbatim: errorMessage)
            }
        }
    }

    private func deleteAll() {
        guard !isDeleting else { return }
        isDeleting = true

        Task { @MainActor in
            do {
                try await profileStore.deleteAll()
                isDeleting = false
                onAllDataDeleted()
            } catch {
                isDeleting = false
                errorMessage = A6Copy.deleteFailed
            }
        }
    }
}
