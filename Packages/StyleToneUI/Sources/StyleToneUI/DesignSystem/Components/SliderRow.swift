import Foundation
import SwiftUI

/// A labelled slider row for the four tool areas.
///
/// The header shows the localized title and a formatted value; at
/// accessibility Dynamic Type sizes it stacks instead of truncating. Drag-time
/// proxy rendering and throttling are owned by the editor pipeline (WP-17);
/// this component only binds a value.
public struct SliderRow: View {
    private let title: String
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let systemImage: String?
    private let isEnabled: Bool
    private let valueFormatter: (@MainActor (Double) -> String)?
    private let accessibilityID: String

    @Environment(\.styleToneTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var scaledTouchTarget: CGFloat =
        LayoutMetrics.standard.minTouchTarget

    /// - Parameters:
    ///   - title: Already-localized row label.
    ///   - value: Bound value.
    ///   - range: Valid range. An inverted or empty range is replaced by `0...1`.
    ///   - step: Slider step. Values `<= 0` fall back to `0.01`.
    ///   - valueFormatter: Optional formatter receiving the raw value. The
    ///     default displays a percentage of the range.
    ///   - accessibilityID: Required `screen.element` identifier.
    public init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        step: Double = 0.01,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        valueFormatter: (@MainActor (Double) -> String)? = nil,
        accessibilityID: String
    ) {
        self.title = title
        self._value = value
        self.range = range.lowerBound < range.upperBound ? range : 0...1
        self.step = step > 0 ? step : 0.01
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.valueFormatter = valueFormatter
        self.accessibilityID = accessibilityID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            header
                .accessibilityHidden(true)

            Slider(value: $value, in: range, step: step)
                .tint(theme.color(.accent))
                .disabled(!isEnabled)
                .frame(minHeight: scaledTouchTarget)
                .accessibilityIdentifier(accessibilityID)
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityValue(Text(verbatim: displayValue))
        }
    }

    @ViewBuilder
    private var header: some View {
        let titleView = HStack(spacing: theme.spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(theme.typography.font(.label))
                    .foregroundStyle(theme.color(.textSecondary))
            }
            Text(verbatim: title)
                .font(theme.typography.font(.label))
                .foregroundStyle(theme.color(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
        }

        let valueView = Text(verbatim: displayValue)
            .font(theme.typography.font(.value))
            .foregroundStyle(theme.color(.textSecondary))
            .monospacedDigit()

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                titleView
                valueView
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                titleView
                Spacer(minLength: theme.spacing.sm)
                valueView
            }
        }
    }

    private var displayValue: String {
        if let valueFormatter {
            return valueFormatter(value)
        }
        return Self.normalizedValue(value, in: range)
            .formatted(.percent.precision(.fractionLength(0)))
    }

    /// Maps a raw value to `0...1` within `range`.
    nonisolated public static func normalizedValue(
        _ value: Double,
        in range: ClosedRange<Double>
    ) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0, span.isFinite else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }
}
