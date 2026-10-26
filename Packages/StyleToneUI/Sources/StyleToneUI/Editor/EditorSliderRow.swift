import Foundation
import SwiftUI

/// Editor slider row with gesture callbacks.
///
/// The design-system `SliderRow` deliberately has no `onEditingChanged`
/// closure; the editor needs it to group a drag into one undo step and to
/// switch from proxy to full-quality rendering on release. This row reuses the
/// same tokens and accessibility contract.
struct EditorSliderRow: View {
    private let title: String
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let systemImage: String?
    private let isEnabled: Bool
    private let valueFormatter: ((Double) -> String)?
    private let accessibilityID: String
    private let onEditingChanged: (Bool) -> Void

    @Environment(\.styleToneTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var scaledTouchTarget: CGFloat =
        LayoutMetrics.standard.minTouchTarget

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        step: Double = 0.01,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        valueFormatter: ((Double) -> String)? = nil,
        accessibilityID: String,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        self.title = title
        self._value = value
        self.range = range.lowerBound < range.upperBound ? range : 0...1
        self.step = step > 0 ? step : 0.01
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.valueFormatter = valueFormatter
        self.accessibilityID = accessibilityID
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            header
                .accessibilityHidden(true)

            Slider(
                value: $value,
                in: range,
                step: step,
                onEditingChanged: onEditingChanged
            )
            .tint(theme.color(.accent))
            .disabled(!isEnabled)
            .frame(minHeight: scaledTouchTarget)
            .accessibilityIdentifier(accessibilityID)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityValue(Text(verbatim: displayValue))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
            HStack(spacing: theme.spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(theme.typography.font(.label))
                        .foregroundStyle(theme.color(.textSecondary))
                }
                Text(verbatim: title)
                    .styleToneText(.label)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: theme.spacing.sm)

            Text(verbatim: displayValue)
                .styleToneText(.value, color: .textSecondary)
                .monospacedDigit()
        }
    }

    private var displayValue: String {
        if let valueFormatter {
            return valueFormatter(value)
        }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }
}
