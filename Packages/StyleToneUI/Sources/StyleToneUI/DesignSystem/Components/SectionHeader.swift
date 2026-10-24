import SwiftUI

/// Section heading with an optional subtitle and trailing accessory.
///
/// The title carries the `.isHeader` accessibility trait so VoiceOver can jump
/// between tool areas.
public struct SectionHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let accessibilityID: String?
    private let trailing: Trailing

    @Environment(\.styleToneTheme) private var theme

    public init(
        title: String,
        subtitle: String? = nil,
        accessibilityID: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessibilityID = accessibilityID
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(verbatim: title)
                    .styleToneText(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(verbatim: subtitle)
                        .styleToneText(.caption, color: .textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            trailing
        }
        .modifier(OptionalAccessibilityID(identifier: accessibilityID))
    }
}

public extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, accessibilityID: String? = nil) {
        self.init(
            title: title,
            subtitle: subtitle,
            accessibilityID: accessibilityID,
            trailing: { EmptyView() }
        )
    }
}

private struct OptionalAccessibilityID: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
