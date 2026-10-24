import Foundation

/// Top-level destinations of the app shell.
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case editor
    case style
    case settings

    public var id: String { rawValue }

    public var titleKey: LocalizationKey {
        switch self {
        case .editor: return L10n.shellTabEditor
        case .style: return L10n.shellTabStyle
        case .settings: return L10n.shellTabSettings
        }
    }

    public var systemImage: String {
        switch self {
        case .editor: return "slider.horizontal.3"
        case .style: return "person.crop.circle"
        case .settings: return "gearshape"
        }
    }

    public var accessibilityID: AccessibilityID {
        switch self {
        case .editor: return .shellTabEditor
        case .style: return .shellTabStyle
        case .settings: return .shellTabSettings
        }
    }

    /// The route rendered as the tab's root. Root routes are not pushed onto a
    /// navigation stack; `AppRouteState.navigate` selects the owning tab.
    public var rootRoute: AppRoute {
        switch self {
        case .editor: return .editor
        case .style: return .calibration
        case .settings: return .settings
        }
    }
}

/// How a route is presented.
public enum RoutePresentation: String, CaseIterable, Sendable {
    /// Pushed onto the current tab's navigation stack.
    case push
    /// Presented as a modal sheet above the current tab.
    case sheet
}

/// All routes the app shell can present. Feature screens receive route values
/// (and navigation callbacks) rather than owning navigation themselves.
public enum AppRoute: String, CaseIterable, Identifiable, Sendable {
    case onboarding
    case pairing
    case calibration
    case editor
    case styleProfile
    case settings
    case paywall
    case export

    public var id: String { rawValue }

    public var presentation: RoutePresentation {
        switch self {
        case .paywall, .export: return .sheet
        case .onboarding, .pairing, .calibration, .editor, .styleProfile, .settings: return .push
        }
    }

    public var titleKey: LocalizationKey {
        switch self {
        case .onboarding: return L10n.onboardingTitle
        case .pairing: return L10n.pairingTitle
        case .calibration: return L10n.calibrationTitle
        case .editor: return L10n.editorTitle
        case .styleProfile: return L10n.calibrationStyleCardTitle
        case .settings: return L10n.settingsTitle
        case .paywall: return L10n.paywallTitle
        case .export: return L10n.exportTitle
        }
    }

    public var systemImage: String {
        switch self {
        case .onboarding: return "hand.wave"
        case .pairing: return "rectangle.on.rectangle"
        case .calibration: return "slider.horizontal.3"
        case .editor: return "photo"
        case .styleProfile: return "person.crop.circle.badge.checkmark"
        case .settings: return "gearshape"
        case .paywall: return "creditcard"
        case .export: return "square.and.arrow.up"
        }
    }

    public var accessibilityScreen: AccessibilityScreen {
        switch self {
        case .onboarding: return .onboarding
        case .pairing: return .pairing
        case .calibration: return .calibration
        case .editor: return .editor
        case .styleProfile: return .styleProfile
        case .settings: return .settings
        case .paywall: return .paywall
        case .export: return .export
        }
    }

    /// Identifier for the screen's root container.
    public var accessibilityID: AccessibilityID {
        AccessibilityID(accessibilityScreen, "root")
    }
}

/// Pure navigation state for the app shell.
///
/// Keeping the state machine free of SwiftUI makes route transitions testable
/// on any platform. The shell binds it to `NavigationStack` paths and a sheet.
public struct AppRouteState: Sendable, Equatable {
    /// Defensive cap so a buggy caller cannot grow a stack without bound.
    public static let maxPathDepth = 12

    public private(set) var selectedTab: AppTab
    public private(set) var presentedSheet: AppRoute?
    private var paths: [AppTab: [AppRoute]]

    public init(selectedTab: AppTab = .editor) {
        self.selectedTab = selectedTab
        self.presentedSheet = nil
        self.paths = [:]
    }

    /// The navigation path for a tab. Empty means the tab's root is visible.
    public func path(for tab: AppTab) -> [AppRoute] {
        paths[tab] ?? []
    }

    /// The topmost pushed route, if any.
    public func topRoute(for tab: AppTab) -> AppRoute? {
        path(for: tab).last
    }

    /// Selects a tab without changing any navigation path.
    public mutating func select(_ tab: AppTab) {
        selectedTab = tab
    }

    /// Replaces a tab's path, dropping sheets and trimming to the depth cap.
    public mutating func setPath(_ path: [AppRoute], for tab: AppTab) {
        let pushable = path.filter { $0.presentation == .push }
        paths[tab] = Array(pushable.prefix(Self.maxPathDepth))
    }

    /// Pushes a route on a tab. Rejects sheet routes, tab roots, immediate
    /// duplicates and stacks beyond `maxPathDepth`.
    @discardableResult
    public mutating func push(_ route: AppRoute, in tab: AppTab? = nil) -> Bool {
        guard route.presentation == .push else { return false }
        let target = tab ?? selectedTab
        guard route != target.rootRoute else { return false }

        var path = path(for: target)
        guard path.last != route, path.count < Self.maxPathDepth else { return false }

        path.append(route)
        paths[target] = path
        return true
    }

    /// Pops the top route and returns it, or `nil` when already at the root.
    @discardableResult
    public mutating func pop(in tab: AppTab? = nil) -> AppRoute? {
        let target = tab ?? selectedTab
        var path = path(for: target)
        guard !path.isEmpty else { return nil }

        let popped = path.removeLast()
        paths[target] = path
        return popped
    }

    /// Clears a tab's stack. Returns `false` when it was already at the root.
    @discardableResult
    public mutating func popToRoot(in tab: AppTab? = nil) -> Bool {
        let target = tab ?? selectedTab
        guard !path(for: target).isEmpty else { return false }
        paths[target] = []
        return true
    }

    /// Presents a sheet route. Rejects push routes.
    @discardableResult
    public mutating func present(_ route: AppRoute) -> Bool {
        guard route.presentation == .sheet else { return false }
        presentedSheet = route
        return true
    }

    /// Dismisses the current sheet, if any.
    public mutating func dismissSheet() {
        presentedSheet = nil
    }

    /// Presents a route according to its `RoutePresentation`.
    ///
    /// Navigating to another tab's root route selects that tab and clears its
    /// stack instead of duplicating the root inside the current stack.
    @discardableResult
    public mutating func navigate(_ route: AppRoute, in tab: AppTab? = nil) -> Bool {
        if route.presentation == .push,
           let owningTab = AppTab.allCases.first(where: { $0.rootRoute == route }) {
            selectedTab = owningTab
            paths[owningTab] = []
            return true
        }

        switch route.presentation {
        case .push:
            return push(route, in: tab)
        case .sheet:
            return present(route)
        }
    }
}
