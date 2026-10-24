import StyleToneUI

/// Navigation and feedback callbacks handed to placeholder screens.
///
/// Screens stay unaware of the router: they request a route or a toast and the
/// shell decides how to present it. Feature work packages can keep this shape.
@MainActor
struct ShellActions {
    let navigate: @MainActor (AppRoute) -> Void
    let presentToast: @MainActor (ToastMessage) -> Void
    let dismissSheet: @MainActor () -> Void
}
