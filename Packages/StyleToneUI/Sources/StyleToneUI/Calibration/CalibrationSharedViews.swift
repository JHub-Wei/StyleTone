import StyleToneCore
import SwiftUI

// MARK: - Card surface

struct CalibrationCardModifier: ViewModifier {
    @Environment(\.styleToneTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(theme.spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.color(.surface),
                in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                    .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
            }
    }
}

extension View {
    func calibrationCard() -> some View {
        modifier(CalibrationCardModifier())
    }
}

// MARK: - Notice

@MainActor
struct CalibrationNoticeBanner: View {
    let notice: CalibrationNotice
    let dismiss: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.sm) {
            Image(systemName: iconName)
                .font(theme.typography.font(.body))
                .foregroundStyle(theme.color(.accent))
                .accessibilityHidden(true)

            Text(verbatim: message)
                .styleToneText(.caption, color: .textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: theme.spacing.xs)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(theme.typography.font(.label))
                    .foregroundStyle(theme.color(.textSecondary))
                    .frame(
                        width: theme.metrics.minTouchTarget,
                        height: theme.metrics.minTouchTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: CalibrationCopy.text(CalibrationCopy.noticeDismiss)))
        }
        .padding(.leading, theme.spacing.md)
        .padding(.trailing, theme.spacing.xs)
        .padding(.vertical, theme.spacing.xs)
        .background(
            theme.color(.surfaceElevated),
            in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
        }
        .accessibilityIdentifier(AccessibilityID.calibrationNotice.rawValue)
    }

    private var iconName: String {
        switch notice {
        case .restored: return "arrow.clockwise"
        case .cancelledLearning: return "pause.circle"
        case .progressUnavailable: return "exclamationmark.triangle"
        case .missingPairs: return "photo.badge.exclamationmark"
        }
    }

    private var message: String {
        switch notice {
        case .restored:
            return CalibrationCopy.text(CalibrationCopy.noticeRestored)
        case .cancelledLearning:
            return CalibrationCopy.text(CalibrationCopy.noticeCancelled)
        case .progressUnavailable:
            return CalibrationCopy.text(CalibrationCopy.noticeProgressUnavailable)
        case .missingPairs:
            return CalibrationCopy.text(CalibrationCopy.noticeMissingPairs)
        }
    }
}

// MARK: - Tier selector

@MainActor
struct CalibrationTierSelector: View {
    let eligiblePairs: Int
    let recommended: CalibrationPairTier?
    @Binding var selection: CalibrationPairTier?

    @Environment(\.styleToneTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumHeight: CGFloat = 76

    var body: some View {
        let layout = dynamicTypeSize >= .accessibility1
            ? AnyLayout(VStackLayout(spacing: theme.spacing.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: theme.spacing.sm))

        return layout {
            ForEach(CalibrationPairTier.allCases) { tier in
                tierButton(tier)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tierButton(_ tier: CalibrationPairTier) -> some View {
        let isAvailable = eligiblePairs >= tier.pairCount
        let isSelected = selection == tier && isAvailable
        let isRecommended = recommended == tier

        return Button {
            guard isAvailable else { return }
            selection = tier
        } label: {
            VStack(spacing: theme.spacing.xxs) {
                HStack(spacing: theme.spacing.xs) {
                    Text(verbatim: CalibrationCopy.format(
                        CalibrationCopy.pairTierKey(for: tier),
                        tier.pairCount
                    ))
                    .styleToneText(.label, color: isSelected ? .onAccent : .textPrimary)

                    Image(systemName: isAvailable ? "checkmark.circle.fill" : "lock.fill")
                        .font(theme.typography.font(.caption))
                        .foregroundStyle(
                            isSelected
                                ? theme.color(.onAccent)
                                : theme.color(isAvailable ? .success : .textTertiary)
                        )
                        .accessibilityHidden(true)
                }

                if isRecommended {
                    Text(verbatim: CalibrationCopy.text(CalibrationCopy.pairsRecommended))
                        .styleToneText(.caption, color: isSelected ? .onAccent : .textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: minimumHeight)
            .padding(.horizontal, theme.spacing.xs)
            .background(
                isSelected ? theme.color(.accent) : theme.color(.surfaceElevated),
                in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.color(.accent) : theme.color(.border),
                        lineWidth: theme.metrics.hairline
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.55)
        .accessibilityIdentifier(accessibilityID(for: tier).rawValue)
        .accessibilityLabel(Text(verbatim: CalibrationCopy.tierDescription(
            tier,
            availablePairs: eligiblePairs
        )))
        .accessibilityHint(Text(verbatim: CalibrationCopy.text(CalibrationCopy.pairsTierHint)))
    }

    private func accessibilityID(for tier: CalibrationPairTier) -> AccessibilityID {
        switch tier {
        case .three: return .calibrationTierThree
        case .five: return .calibrationTierFive
        case .eight: return .calibrationTierEight
        }
    }
}

// MARK: - AB card

@MainActor
struct CalibrationABCard: View {
    let comparison: CalibrationComparison
    let chooseA: @MainActor () -> Void
    let chooseB: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            Text(verbatim: CalibrationCopy.text(comparison.dimensionKey))
                .styleToneText(.sectionTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityID.calibrationABPrompt.rawValue)

            choiceLayout
        }
        .calibrationCard()
    }

    private var choiceLayout: some View {
        let layout = dynamicTypeSize >= .accessibility1
            ? AnyLayout(VStackLayout(spacing: theme.spacing.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: theme.spacing.md))

        return layout {
            optionButton(
                comparison.optionA,
                labelKey: CalibrationCopy.abOptionA,
                accessibilityID: .calibrationABOptionAButton,
                action: chooseA
            )
            optionButton(
                comparison.optionB,
                labelKey: CalibrationCopy.abOptionB,
                accessibilityID: .calibrationABOptionBButton,
                action: chooseB
            )
        }
    }

    private func optionButton(
        _ option: CalibrationComparisonOption,
        labelKey: LocalizationKey,
        accessibilityID: AccessibilityID,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        let optionLabel = CalibrationCopy.text(labelKey)
        let detail = CalibrationCopy.text(option.detailKey)

        return Button(action: action) {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                CalibrationABOptionPreview(
                    option: option,
                    letter: labelKey == CalibrationCopy.abOptionA ? "A" : "B"
                )

                Text(verbatim: optionLabel)
                    .styleToneText(.label)
                Text(verbatim: detail)
                    .styleToneText(.body, color: .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.spacing.sm)
            .background(
                theme.color(.surfaceElevated),
                in: RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous)
                    .strokeBorder(theme.color(.border), lineWidth: theme.metrics.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: theme.radii.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID.rawValue)
        .accessibilityLabel(Text(verbatim: "\(optionLabel), \(detail)"))
        .accessibilityHint(Text(verbatim: CalibrationCopy.text(CalibrationCopy.abOptionHint)))
    }
}

private struct CalibrationABOptionPreview: View {
    let option: CalibrationComparisonOption
    let letter: String

    @Environment(\.styleToneTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 116

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    theme.color(.surfacePressed),
                    theme.color(.photoBackground),
                    theme.color(.accent).opacity(option.variant == .high ? 0.38 : 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: option.variant == .low ? "sun.max" : "camera.filters")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(theme.color(.onPhotoSecondary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(verbatim: letter)
                .styleToneText(.value, color: .onPhoto)
                .padding(.horizontal, theme.spacing.sm)
                .padding(.vertical, theme.spacing.xxs)
                .background(
                    theme.color(.scrim).opacity(0.55),
                    in: Capsule()
                )
                .padding(theme.spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: theme.radii.small, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Result card

@MainActor
struct CalibrationStyleCardPreview: View {
    let profile: StyleProfile
    let isNaturalDefault: Bool
    let open: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme
    @ScaledMetric(relativeTo: .title) private var minimumHeight: CGFloat = 252

    var body: some View {
        Button(action: open) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        theme.color(.surfaceElevated),
                        theme.color(.photoBackground),
                        theme.color(.accent).opacity(0.34),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 84, weight: .ultraLight))
                    .foregroundStyle(theme.color(.onPhotoSecondary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: theme.spacing.lg) {
                    HStack(alignment: .top) {
                        Text(verbatim: CalibrationCopy.text(CalibrationCopy.resultPreviewBadge))
                            .styleToneText(.caption, color: .onPhoto)
                            .padding(.horizontal, theme.spacing.sm)
                            .padding(.vertical, theme.spacing.xxs)
                            .background(theme.color(.scrim).opacity(0.55), in: Capsule())

                        Spacer()

                        Text(verbatim: CalibrationCopy.text(
                            CalibrationCopy.confidenceKey(for: profile.confidence)
                        ))
                        .styleToneText(.caption, color: .onPhoto)
                    }

                    Spacer(minLength: theme.spacing.lg)

                    Text(verbatim: isNaturalDefault
                        ? CalibrationCopy.text(CalibrationCopy.resultNaturalTitle)
                        : CalibrationCopy.text(CalibrationCopy.resultTitle))
                        .styleToneText(.screenTitle, color: .onPhoto)
                        .lineLimit(2)

                    HStack(spacing: theme.spacing.xs) {
                        ForEach(knownTags, id: \.self) { tag in
                            Text(verbatim: tag)
                                .styleToneText(.caption, color: .onPhoto)
                                .padding(.horizontal, theme.spacing.sm)
                                .padding(.vertical, theme.spacing.xxs)
                                .background(theme.color(.scrim).opacity(0.45), in: Capsule())
                        }
                    }
                }
                .padding(theme.spacing.lg)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: minimumHeight)
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.large, style: .continuous)
                    .strokeBorder(theme.color(.borderStrong), lineWidth: theme.metrics.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: theme.radii.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.calibrationStyleCardButton.rawValue)
        .accessibilityLabel(Text(verbatim: CalibrationCopy.text(CalibrationCopy.resultOpenCard)))
        .accessibilityHint(Text(verbatim: CalibrationCopy.text(CalibrationCopy.resultPreviewNote)))
    }

    private var knownTags: [String] {
        profile.tags.compactMap { tag in
            switch tag {
            case "style.tag.natural", CalibrationFlow.naturalDefaultTag:
                return CalibrationCopy.text(CalibrationCopy.resultTagNatural)
            case "style.tag.warm":
                return CalibrationCopy.text(CalibrationCopy.resultTagWarm)
            case "style.tag.soft":
                return CalibrationCopy.text(CalibrationCopy.resultTagSoft)
            case "style.tag.defined":
                return CalibrationCopy.text(CalibrationCopy.resultTagDefined)
            case "style.tag.editorial":
                return CalibrationCopy.text(CalibrationCopy.resultTagEditorial)
            default:
                return nil
            }
        }
    }
}

// MARK: - Failure

@MainActor
struct CalibrationFailureView: View {
    let failure: CalibrationFailure
    let retry: @MainActor () -> Void
    let backToComparisons: @MainActor () -> Void
    let useNaturalDefault: @MainActor () -> Void
    let backToPairs: @MainActor () -> Void

    @Environment(\.styleToneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(theme.typography.font(.display))
                .foregroundStyle(theme.color(.warning))
                .accessibilityHidden(true)

            Text(verbatim: CalibrationCopy.text(CalibrationCopy.errorTitle))
                .styleToneText(.screenTitle)
                .accessibilityAddTraits(.isHeader)

            Text(verbatim: message)
                .styleToneText(.body, color: .textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: CalibrationCopy.text(CalibrationCopy.errorPairsPreserved))
                .styleToneText(.caption, color: .textSecondary)

            VStack(spacing: theme.spacing.sm) {
                if failure.canRetry {
                    PrimaryButton(
                        CalibrationCopy.text(CalibrationCopy.errorRetry),
                        systemImage: "arrow.clockwise",
                        accessibilityID: AccessibilityID.calibrationErrorRetryButton.rawValue,
                        action: retry
                    )
                }

                if failure.kind == .learning || failure.kind == .savingProfile {
                    PrimaryButton(
                        CalibrationCopy.text(CalibrationCopy.errorBack),
                        role: .secondary,
                        accessibilityID: AccessibilityID.calibrationErrorBackButton.rawValue,
                        action: backToComparisons
                    )
                }

                PrimaryButton(
                    CalibrationCopy.text(CalibrationCopy.errorNatural),
                    role: .secondary,
                    accessibilityID: AccessibilityID.calibrationErrorNaturalButton.rawValue,
                    action: useNaturalDefault
                )

                PrimaryButton(
                    CalibrationCopy.text(CalibrationCopy.errorPairs),
                    role: .secondary,
                    accessibilityID: AccessibilityID.calibrationErrorPairsButton.rawValue,
                    action: backToPairs
                )
            }
        }
        .calibrationCard()
    }

    private var message: String {
        switch failure.kind {
        case .learning: return CalibrationCopy.text(CalibrationCopy.errorLearning)
        case .savingProfile: return CalibrationCopy.text(CalibrationCopy.errorSaving)
        case .restoring: return CalibrationCopy.text(CalibrationCopy.errorRestore)
        case .missingPairs: return CalibrationCopy.text(CalibrationCopy.errorMissingPairs)
        }
    }
}
