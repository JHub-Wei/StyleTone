import SwiftUI
import StyleToneUI

/// Root of the app shell.
///
/// Owns navigation state and toast presentation, injects the dependency
/// container, and forces the darkroom appearance. Wire it from
/// `StyleToneApp.swift` with a single line once the WP-00 owner approves the
/// entry-point change:
///
/// ```swift
/// WindowGroup { AppShellView() }
/// ```
@MainActor
struct AppShellView: View {
    private let dependencies: AppDependencies
    @State private var routeState: AppRouteState
    @State private var toastPresenter = ShellToastPresenter()

    init(
        dependencies: AppDependencies = .placeholder,
        initialState: AppRouteState = AppRouteState()
    ) {
        self.dependencies = dependencies
        _routeState = State(initialValue: initialState)
    }

    var body: some View {
        AppShellContent(
            routeState: $routeState,
            toastPresenter: toastPresenter,
            dependencies: dependencies
        )
        .environment(\.appDependencies, dependencies)
        .styleToneThemeProvider()
        .preferredColorScheme(.dark)
        .accessibilityIdentifier(AccessibilityID.shellRoot.rawValue)
    }
}

private struct AppShellContent: View {
    @Binding var routeState: AppRouteState
    let toastPresenter: ShellToastPresenter
    let dependencies: AppDependencies

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        TabView(selection: tabSelection) {
            tabStack(for: .editor) {
                EditorPlaceholderScreen(actions: actions)
            }

            tabStack(for: .style) {
                CalibrationPlaceholderScreen(actions: actions)
            }

            tabStack(for: .settings) {
                SettingsPlaceholderScreen(actions: actions)
            }
        }
        .tint(theme.color(.accent))
        .overlay(alignment: .bottom) {
            toastOverlay
        }
        .animation(.easeOut(duration: 0.2), value: toastPresenter.message?.id)
        .sheet(item: sheetSelection) { route in
            NavigationStack {
                destination(for: route)
            }
            .presentationDragIndicator(.visible)
            .environment(\.appDependencies, dependencies)
            .overlay(alignment: .bottom) {
                toastOverlay
            }
            .animation(.easeOut(duration: 0.2), value: toastPresenter.message?.id)
        }
    }

    // MARK: Tabs

    private func tabStack<Root: View>(
        for tab: AppTab,
        @ViewBuilder root: () -> Root
    ) -> some View {
        NavigationStack(path: pathBinding(for: tab)) {
            root()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .tabItem {
            Label {
                Text(verbatim: tabTitle(for: tab))
                    .accessibilityIdentifier(tab.accessibilityID.rawValue)
            } icon: {
                Image(systemName: tab.systemImage)
            }
        }
        .tag(tab)
    }

    private func tabTitle(for tab: AppTab) -> String {
        switch tab {
        case .editor: return ShellCopy.tabEditor
        case .style: return ShellCopy.tabStyle
        case .settings: return ShellCopy.tabSettings
        }
    }

    // MARK: Destinations

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .onboarding:
            OnboardingPlaceholderScreen(actions: actions)
        case .pairing:
            PairingPlaceholderScreen(actions: actions)
        case .calibration:
            CalibrationPlaceholderScreen(actions: actions)
        case .editor:
            EditorPlaceholderScreen(actions: actions)
        case .styleProfile:
            StyleProfilePlaceholderScreen(actions: actions)
        case .settings:
            SettingsPlaceholderScreen(actions: actions)
        case .paywall:
            PaywallPlaceholderScreen(actions: actions)
        case .export:
            ExportPlaceholderScreen(actions: actions)
        }
    }

    // MARK: Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = toastPresenter.message {
            ToastView(
                message: message,
                dismissLabel: ShellCopy.dismissButton,
                onDismiss: { toastPresenter.dismiss() }
            )
            .padding(.horizontal, theme.spacing.lg)
            .padding(.bottom, theme.spacing.xxxl + theme.spacing.xl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Bindings and actions

    private var routeBinding: Binding<AppRouteState> {
        $routeState
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { routeBinding.wrappedValue.selectedTab },
            set: { newValue in
                var state = routeBinding.wrappedValue
                state.select(newValue)
                routeBinding.wrappedValue = state
            }
        )
    }

    private var sheetSelection: Binding<AppRoute?> {
        Binding(
            get: { routeBinding.wrappedValue.presentedSheet },
            set: { newValue in
                var state = routeBinding.wrappedValue
                if let newValue {
                    _ = state.present(newValue)
                } else {
                    state.dismissSheet()
                }
                routeBinding.wrappedValue = state
            }
        )
    }

    private func pathBinding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { routeBinding.wrappedValue.path(for: tab) },
            set: { newValue in
                var state = routeBinding.wrappedValue
                state.setPath(newValue, for: tab)
                routeBinding.wrappedValue = state
            }
        )
    }

    private var actions: ShellActions {
        ShellActions(
            navigate: { route in
                var state = routeBinding.wrappedValue
                _ = state.navigate(route)
                routeBinding.wrappedValue = state
            },
            presentToast: { message in
                toastPresenter.show(message)
            },
            dismissSheet: {
                var state = routeBinding.wrappedValue
                state.dismissSheet()
                routeBinding.wrappedValue = state
            }
        )
    }
}

#if DEBUG
private extension AppRouteState {
    /// Builds a shell state that already contains `route`, for previews of
    /// pushed destinations and sheets.
    static func preview(navigatingTo route: AppRoute) -> AppRouteState {
        var state = AppRouteState()
        _ = state.navigate(route)
        return state
    }
}

#Preview("App shell / editor") {
    AppShellView()
}

#Preview("App shell / style tab") {
    AppShellView(initialState: AppRouteState(selectedTab: .style))
}

#Preview("App shell / settings tab") {
    AppShellView(initialState: AppRouteState(selectedTab: .settings))
}

#Preview("App shell / pairing route") {
    AppShellView(initialState: .preview(navigatingTo: .pairing))
}

#Preview("App shell / onboarding route") {
    AppShellView(initialState: .preview(navigatingTo: .onboarding))
}

#Preview("App shell / paywall sheet") {
    AppShellView(initialState: .preview(navigatingTo: .paywall))
}
#endif
