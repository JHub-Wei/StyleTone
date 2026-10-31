import SwiftUI

/// Phase A A6 application entry point.
///
/// The self-use build boots into the real local-only flow in `A6RootView`:
/// active profile → editor, or minimal welcome → pairing → calibration →
/// editor. The WP-03 shell and placeholder screens remain in the target for
/// previews, but they are no longer the entry point.
@main
struct StyleToneApp: App {
    var body: some Scene {
        WindowGroup {
            A6RootView()
        }
    }
}
