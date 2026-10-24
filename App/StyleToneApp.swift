import SwiftUI

/// WP-00 application entry point.
///
/// Business screens, navigation and dependency wiring are implemented by later
/// work packages. This target exists so the project, package graph and CI can
/// be validated before feature work starts.
@main
struct StyleToneApp: App {
    var body: some Scene {
        WindowGroup {
            WP00PlaceholderView()
        }
    }
}

private struct WP00PlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("私调")
                .font(.largeTitle.bold())
            Text("StyleTone")
                .font(.headline)
            Text("WP-00 工程骨架")
                .font(.subheadline)
            Text("业务功能由后续工作包实现")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .accessibilityIdentifier("wp00.root")
    }
}
