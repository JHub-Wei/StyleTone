import Foundation
import StyleToneCore

// MARK: - Tool areas

/// The four editor tool areas frozen by contracts 搂8.
///
/// Each area owns at most five sliders. Face and skin require a detected face;
/// body requires a detected body; tone is always available because it does not
/// depend on landmarks.
public enum EditorToolArea: String, CaseIterable, Identifiable, Sendable {
    case face
    case body
    case skin
    case tone

    public var id: String { rawValue }

    /// Localization key for the tab label.
    public var titleKey: LocalizationKey {
        LocalizationKey("editor.area.\(rawValue)")
    }

    /// `editor.tab.<area>` accessibility identifier.
    public var accessibilityID: AccessibilityID {
        AccessibilityID(.editor, "tab.\(rawValue)")
    }

    /// Whether the analysis supports this area.
    ///
    /// Tone remains available for portraits without a face or body; the other
    /// areas are disabled so a slider can never ask an engine to warp a
    /// landmark that was not found.
    public func isAvailable(in analysis: PortraitAnalysis?) -> Bool {
        guard let analysis else {
            return self == .tone
        }
        switch self {
        case .face, .skin:
            return analysis.hasFace
        case .body:
            return analysis.hasBody
        case .tone:
            return true
        }
    }

    /// Localization key explaining why the area is disabled.
    public func unavailableReasonKey(in analysis: PortraitAnalysis?) -> LocalizationKey? {
        guard !isAvailable(in: analysis) else { return nil }
        switch self {
        case .face, .skin:
            return LocalizationKey("editor.areaUnavailable.noFace")
        case .body:
            return LocalizationKey("editor.areaUnavailable.noBody")
        case .tone:
            return nil
        }
    }
}

// MARK: - Sliders

/// One editable slider mapped onto `ManualAdjustments`.
///
/// Ranges mirror the frozen Core parameter ranges. `legLength` is a scale
/// (1.0 = no change), while the tone controls are signed.
public enum EditorAdjustment: String, CaseIterable, Identifiable, Sendable {
    // Face
    case faceSlim
    case jaw

    // Body
    case arm
    case waist
    case leg
    case legLength

    // Skin
    case smoothing
    case evenness
    case blemish

    // Tone
    case exposure
    case contrast
    case temperature
    case saturation
    case grain

    public var id: String { rawValue }

    public var titleKey: LocalizationKey {
        LocalizationKey("editor.slider.\(rawValue)")
    }

    public var area: EditorToolArea {
        switch self {
        case .faceSlim, .jaw:
            return .face
        case .arm, .waist, .leg, .legLength:
            return .body
        case .smoothing, .evenness, .blemish:
            return .skin
        case .exposure, .contrast, .temperature, .saturation, .grain:
            return .tone
        }
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .legLength:
            return 1.0...1.15
        case .exposure, .contrast, .temperature, .saturation:
            return -1.0...1.0
        default:
            return 0.0...1.0
        }
    }

    public var defaultValue: Double {
        self == .legLength ? 1.0 : 0.0
    }

    /// Accessibility identifier; the three frozen design-system identifiers are
    /// reused for face slim, jaw and smoothing.
    public var accessibilityID: AccessibilityID {
        EditorAccessibility.adjustmentID(for: self)
    }

    public func value(in adjustments: ManualAdjustments) -> Double {
        switch self {
        case .faceSlim: return adjustments.faceSlim
        case .jaw: return adjustments.jaw
        case .arm: return adjustments.arm
        case .waist: return adjustments.waist
        case .leg: return adjustments.leg
        case .legLength: return adjustments.legLength == 0 ? 1.0 : adjustments.legLength
        case .smoothing: return adjustments.smoothing
        case .evenness: return adjustments.evenness
        case .blemish: return adjustments.blemish
        case .exposure: return adjustments.exposure
        case .contrast: return adjustments.contrast
        case .temperature: return adjustments.temperature
        case .saturation: return adjustments.saturation
        case .grain: return adjustments.grain
        }
    }

    /// Clamps to `range` and stores the value.
    public func set(_ value: Double, in adjustments: inout ManualAdjustments) {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        switch self {
        case .faceSlim:
            adjustments.faceSlim = clamped
        case .jaw:
            adjustments.jaw = clamped
        case .arm:
            adjustments.arm = clamped
        case .waist:
            adjustments.waist = clamped
        case .leg:
            adjustments.leg = clamped
        case .legLength:
            adjustments.legLength = clamped
        case .smoothing:
            adjustments.smoothing = clamped
        case .evenness:
            adjustments.evenness = clamped
        case .blemish:
            adjustments.blemish = clamped
        case .exposure:
            adjustments.exposure = clamped
        case .contrast:
            adjustments.contrast = clamped
        case .temperature:
            adjustments.temperature = clamped
        case .saturation:
            adjustments.saturation = clamped
        case .grain:
            adjustments.grain = clamped
        }
    }

    /// One slider per row in the selected area, capped by `contracts 搂8`.
    public static func all(in area: EditorToolArea) -> [EditorAdjustment] {
        allCases.filter { $0.area == area }
    }
}

// MARK: - Edit state

/// The undoable part of the editor state.
///
/// `strength` is the global 0...150 % strength. `backgroundProtection` only
/// affects geometry passes; toggling it with no warp is a no-op.
public struct EditorEditState: Sendable, Equatable {
    public static let minimumStrength = 0.0
    public static let maximumStrength = 1.5
    /// Natural preset strength from the product requirements (roughly 70 %).
    public static let naturalStrength = 0.7
    public static let defaultStrength = 1.0
    public static let maximumBlemishPoints = 60
    public static let minimumBlemishRadius = 0.005
    public static let maximumBlemishRadius = 0.08

    public var adjustments: ManualAdjustments
    public var strength: Double
    public var backgroundProtection: Bool
    public var blemishPoints: [BlemishPoint]

    public init(
        adjustments: ManualAdjustments = ManualAdjustments(),
        strength: Double = EditorEditState.defaultStrength,
        backgroundProtection: Bool = true,
        blemishPoints: [BlemishPoint] = []
    ) {
        self.adjustments = adjustments
        self.strength = Self.clampStrength(strength)
        self.backgroundProtection = backgroundProtection
        self.blemishPoints = Array(blemishPoints.prefix(Self.maximumBlemishPoints))
    }

    /// Initial editor state: no manual edits, full strength, protection on.
    public static let initial = EditorEditState()

    /// No-effect state used by "reset to original": strength 0 makes the style
    /// and manual offsets disappear without discarding the active style.
    public static let original = EditorEditState(strength: 0)

    public static func clampStrength(_ value: Double) -> Double {
        guard value.isFinite else { return defaultStrength }
        return min(max(value, minimumStrength), maximumStrength)
    }

    /// Whether the user changed anything from the initial state.
    public var hasUserEdits: Bool {
        !adjustments.isNeutral
            || !blemishPoints.isEmpty
            || strength != Self.defaultStrength
            || !backgroundProtection
    }

    public var hasBlemishPoints: Bool { !blemishPoints.isEmpty }

    public mutating func setStrength(_ value: Double) {
        strength = Self.clampStrength(value)
    }

    /// Adds a point, clamping coordinates and radius, and de-duplicates points
    /// that land on almost the same spot.
    @discardableResult
    public mutating func addBlemishPoint(_ point: NormalizedPoint, radius: Double) -> Bool {
        guard blemishPoints.count < Self.maximumBlemishPoints else { return false }
        let clampedPoint = point.clamped()
        for existing in blemishPoints where existing.point.distance(to: clampedPoint) < 0.01 {
            return false
        }
        let clampedRadius = min(max(radius, Self.minimumBlemishRadius), Self.maximumBlemishRadius)
        blemishPoints.append(BlemishPoint(point: clampedPoint, radius: clampedRadius))
        return true
    }

    @discardableResult
    public mutating func removeLastBlemishPoint() -> Bool {
        guard !blemishPoints.isEmpty else { return false }
        blemishPoints.removeLast()
        return true
    }
}

// MARK: - Render state

/// Which resolution tier produced the displayed image.
public enum EditorRenderQuality: String, CaseIterable, Sendable, Equatable {
    /// Downscaled proxy used while a slider is moving.
    case preview
    /// Full-resolution render used after a gesture ends and for export.
    case full
}

public enum EditorRenderState: Sendable, Equatable {
    case idle
    case rendering(EditorRenderQuality)
    case ready(EditorRenderQuality)
    case failed

    public var isRendering: Bool {
        if case .rendering(_) = self { return true }
        return false
    }

    public var quality: EditorRenderQuality? {
        switch self {
        case let .rendering(quality), let .ready(quality):
            return quality
        case .idle, .failed:
            return nil
        }
    }
}

// MARK: - Comparison and zoom

/// Long-press compare is transient; split compare is a mode with a divider.
public struct EditorZoomState: Sendable, Equatable {
    public static let minimumScale = 1.0
    public static let maximumScale = 4.0
    public static let maximumOffset = 1.0

    public private(set) var scale: Double
    public private(set) var offsetX: Double
    public private(set) var offsetY: Double

    public init(scale: Double = 1.0, offsetX: Double = 0.0, offsetY: Double = 0.0) {
        self.scale = Self.clamp(scale, to: Self.minimumScale...Self.maximumScale)
        self.offsetX = Self.clamp(offsetX, to: -Self.maximumOffset...Self.maximumOffset)
        self.offsetY = Self.clamp(offsetY, to: -Self.maximumOffset...Self.maximumOffset)
        if !isZoomed {
            self.offsetX = 0
            self.offsetY = 0
        }
    }

    public var isZoomed: Bool {
        scale > Self.minimumScale + 0.0001
    }

    /// Normalized pan offset applied by the view as a fraction of the canvas.
    public var normalizedOffset: (x: Double, y: Double) {
        (offsetX, offsetY)
    }

    public mutating func setScale(_ value: Double) {
        scale = Self.clamp(value, to: Self.minimumScale...Self.maximumScale)
        if !isZoomed {
            offsetX = 0
            offsetY = 0
        }
    }

    public mutating func magnify(by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        setScale(scale * factor)
    }

    public mutating func setOffset(x: Double, y: Double) {
        guard isZoomed else {
            offsetX = 0
            offsetY = 0
            return
        }
        offsetX = Self.clamp(x, to: -Self.maximumOffset...Self.maximumOffset)
        offsetY = Self.clamp(y, to: -Self.maximumOffset...Self.maximumOffset)
    }

    public mutating func pan(dx: Double, dy: Double) {
        setOffset(x: offsetX + dx, y: offsetY + dy)
    }

    public mutating func reset() {
        scale = Self.minimumScale
        offsetX = 0
        offsetY = 0
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Export

public enum EditorExportState: Sendable, Equatable {
    case idle
    case preparing
    case exporting
    case completed
    case failed

    public var isBusy: Bool {
        switch self {
        case .preparing, .exporting:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }
}

// MARK: - Issue

/// A recoverable editor problem. The view renders the `AppError` keys and
/// offers the matching recovery action.
public struct EditorIssue: Identifiable, Sendable, Equatable {
    public enum Recovery: String, Sendable, Equatable {
        case retryAnalysis
        case retryRender
        case reloadStyle
        case retryExport
    }

    public let id: UUID
    public let error: AppError
    public let recovery: Recovery?

    public init(id: UUID = UUID(), error: AppError, recovery: Recovery? = nil) {
        self.id = id
        self.error = error
        self.recovery = recovery
    }
}

// MARK: - Warnings

/// A scene warning surfaced above the preview.
///
/// Warnings come from analysis, from the render pipeline (for example a closed
/// background protection switch), and stay visible until the underlying state
/// changes. They never block editing by themselves; tool availability is
/// derived from the analysis separately.
public struct EditorWarning: Identifiable, Sendable, Hashable {
    public enum Kind: String, CaseIterable, Sendable, Hashable {
        case noFace
        case multipleFaces
        case noBody
        case occlusion
        case lowLight
        case lowConfidence
        case backgroundRisk
    }

    public enum Severity: String, Sendable, Hashable {
        case info
        case caution
    }

    public let kind: Kind
    public let severity: Severity
    public let messageKey: LocalizationKey
    public let affectedAreas: Set<EditorToolArea>

    public var id: String { kind.rawValue }

    public init(
        kind: Kind,
        severity: Severity,
        messageKey: LocalizationKey,
        affectedAreas: Set<EditorToolArea>
    ) {
        self.kind = kind
        self.severity = severity
        self.messageKey = messageKey
        self.affectedAreas = affectedAreas
    }

    public static func from(_ warning: AnalysisWarning) -> EditorWarning {
        switch warning {
        case .noFace:
            return EditorWarning(
                kind: .noFace,
                severity: .caution,
                messageKey: LocalizationKey("editor.warning.noFace"),
                affectedAreas: [.face, .skin]
            )
        case .multipleFaces:
            return EditorWarning(
                kind: .multipleFaces,
                severity: .caution,
                messageKey: LocalizationKey("editor.warning.multipleFaces"),
                affectedAreas: [.face, .body, .skin]
            )
        case .noBody:
            return EditorWarning(
                kind: .noBody,
                severity: .info,
                messageKey: LocalizationKey("editor.warning.noBody"),
                affectedAreas: [.body]
            )
        case .occlusion:
            return EditorWarning(
                kind: .occlusion,
                severity: .caution,
                messageKey: LocalizationKey("editor.warning.occlusion"),
                affectedAreas: [.face, .body, .skin]
            )
        case .lowLight:
            return EditorWarning(
                kind: .lowLight,
                severity: .info,
                messageKey: LocalizationKey("editor.warning.lowLight"),
                affectedAreas: [.tone, .skin]
            )
        case .lowConfidence:
            return EditorWarning(
                kind: .lowConfidence,
                severity: .caution,
                messageKey: LocalizationKey("editor.warning.lowConfidence"),
                affectedAreas: [.face, .body, .skin, .tone]
            )
        }
    }

    public static func from(_ warning: RenderWarning) -> EditorWarning {
        switch warning.kind {
        case .noFace:
            return from(.noFace)
        case .noBody:
            return from(.noBody)
        case .occlusion:
            return from(.occlusion)
        case .lowConfidence:
            return from(.lowConfidence)
        case .backgroundRisk:
            return backgroundRisk
        }
    }

    public static let backgroundRisk = EditorWarning(
        kind: .backgroundRisk,
        severity: .caution,
        messageKey: LocalizationKey("editor.warning.backgroundRisk"),
        affectedAreas: [.face, .body]
    )

    /// Merges warning groups, keeping the first occurrence of each kind so the
    /// banner order stays stable.
    public static func merge(_ groups: [[EditorWarning]]) -> [EditorWarning] {
        var seen = Set<Kind>()
        var merged: [EditorWarning] = []
        for group in groups {
            for warning in group where !seen.contains(warning.kind) {
                seen.insert(warning.kind)
                merged.append(warning)
            }
        }
        return merged
    }
}
