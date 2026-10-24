import CoreGraphics

/// 4-point spacing scale. Screens use these values instead of magic numbers.
public struct SpacingTokens: Sendable, Hashable {
    public let xxs: CGFloat
    public let xs: CGFloat
    public let sm: CGFloat
    public let md: CGFloat
    public let lg: CGFloat
    public let xl: CGFloat
    public let xxl: CGFloat
    public let xxxl: CGFloat

    /// Horizontal screen inset.
    public let screenHorizontal: CGFloat
    /// Vertical screen inset above and below content.
    public let screenVertical: CGFloat
    /// Gap between major sections.
    public let sectionGap: CGFloat
    /// Gap between inline controls.
    public let inlineGap: CGFloat

    public init(
        xxs: CGFloat = 2,
        xs: CGFloat = 4,
        sm: CGFloat = 8,
        md: CGFloat = 12,
        lg: CGFloat = 16,
        xl: CGFloat = 24,
        xxl: CGFloat = 32,
        xxxl: CGFloat = 48,
        screenHorizontal: CGFloat = 20,
        screenVertical: CGFloat = 24,
        sectionGap: CGFloat = 24,
        inlineGap: CGFloat = 8
    ) {
        self.xxs = xxs
        self.xs = xs
        self.sm = sm
        self.md = md
        self.lg = lg
        self.xl = xl
        self.xxl = xxl
        self.xxxl = xxxl
        self.screenHorizontal = screenHorizontal
        self.screenVertical = screenVertical
        self.sectionGap = sectionGap
        self.inlineGap = inlineGap
    }

    public static let standard = SpacingTokens()
}

/// Corner radii. Keep shape language consistent across components.
public struct RadiusTokens: Sendable, Hashable {
    public let small: CGFloat
    public let medium: CGFloat
    public let large: CGFloat
    public let extraLarge: CGFloat
    /// Buttons and other controls.
    public let control: CGFloat
    /// Cards and photo canvases.
    public let card: CGFloat

    public init(
        small: CGFloat = 8,
        medium: CGFloat = 12,
        large: CGFloat = 16,
        extraLarge: CGFloat = 24,
        control: CGFloat = 12,
        card: CGFloat = 16
    ) {
        self.small = small
        self.medium = medium
        self.large = large
        self.extraLarge = extraLarge
        self.control = control
        self.card = card
    }

    public static let standard = RadiusTokens()
}

/// Component sizing constants that are independent of Dynamic Type.
/// Components scale touch targets with `@ScaledMetric`, using these as the base.
public struct LayoutMetrics: Sendable, Hashable {
    /// Apple's minimum touch target.
    public let minTouchTarget: CGFloat
    public let controlHeight: CGFloat
    public let iconSmall: CGFloat
    public let iconMedium: CGFloat
    public let iconLarge: CGFloat
    public let hairline: CGFloat
    public let photoMinHeight: CGFloat
    public let toastMaxWidth: CGFloat
    /// Opacity applied to `ColorToken.scrim` for modal overlays.
    public let scrimOpacity: Double

    public init(
        minTouchTarget: CGFloat = 44,
        controlHeight: CGFloat = 48,
        iconSmall: CGFloat = 16,
        iconMedium: CGFloat = 20,
        iconLarge: CGFloat = 24,
        hairline: CGFloat = 1,
        photoMinHeight: CGFloat = 240,
        toastMaxWidth: CGFloat = 560,
        scrimOpacity: Double = 0.6
    ) {
        self.minTouchTarget = minTouchTarget
        self.controlHeight = controlHeight
        self.iconSmall = iconSmall
        self.iconMedium = iconMedium
        self.iconLarge = iconLarge
        self.hairline = hairline
        self.photoMinHeight = photoMinHeight
        self.toastMaxWidth = toastMaxWidth
        self.scrimOpacity = scrimOpacity
    }

    public static let standard = LayoutMetrics()
}
