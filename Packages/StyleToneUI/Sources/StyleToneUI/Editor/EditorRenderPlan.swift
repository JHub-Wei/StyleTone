import Foundation
import StyleToneCore

// MARK: - Tone stage

/// Tone/colour/finish settings produced by the editor for the final pipeline
/// stage.
///
/// The frozen Core protocols do not define a tone engine, so WP-17 contributes
/// this protocol instead of changing `StyleToneCore`. The app composition root
/// injects the real implementation; `PassthroughToneRenderer` keeps the editor
/// runnable with mocks and is the standalone default.
public struct EditorToneSettings: Sendable, Equatable {
    public var tone: ToneParameters
    public var finish: FinishParameters

    public init(tone: ToneParameters = .neutral, finish: FinishParameters = .neutral) {
        self.tone = tone
        self.finish = finish
    }

    public var isNeutral: Bool {
        tone == .neutral && finish == .neutral
    }
}

public protocol EditorToneRendering: Sendable {
    func applyTone(
        _ image: ImageAsset,
        settings: EditorToneSettings,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset
}

/// No-op tone stage used by tests and previews before a tone engine is wired.
public struct PassthroughToneRenderer: EditorToneRendering {
    public init() {}

    public func applyTone(
        _ image: ImageAsset,
        settings: EditorToneSettings,
        analysis: PortraitAnalysis
    ) async throws -> ImageAsset {
        image
    }
}

// MARK: - Effective parameters

/// Style and manual offsets combined for one render.
///
/// The personal style supplies a baseline; the sliders are offsets on top of
/// it. The global strength multiplies the whole sum, so 0 always returns the
/// original. Manual leg length uses 0 as "untouched" in `ManualAdjustments`,
/// while the geometry parameter is a 1.0-based scale; `blendLegLength`
/// normalises both.
public struct EditorEffectiveParameters: Sendable, Equatable {
    public var tone: ToneParameters
    public var skin: SkinParameters
    public var face: FaceParameters
    public var body: BodyParameters
    public var finish: FinishParameters

    public init(
        tone: ToneParameters = .neutral,
        skin: SkinParameters = .neutral,
        face: FaceParameters = .neutral,
        body: BodyParameters = .neutral,
        finish: FinishParameters = .neutral
    ) {
        self.tone = tone
        self.skin = skin
        self.face = face
        self.body = body
        self.finish = finish
    }

    public static let neutral = EditorEffectiveParameters()

    public var isNeutral: Bool {
        tone == .neutral
            && skin == .neutral
            && face == .neutral
            && body == .neutral
            && finish == .neutral
    }

    public var toneSettings: EditorToneSettings {
        EditorToneSettings(tone: tone, finish: finish)
    }
}

// MARK: - Plan

/// The exact work a render request asks for.
///
/// Both `EditorViewModel` (for early no-op detection) and `EditorRenderer`
/// (for orchestration) build the plan from the same style/analysis/edit state,
/// so preview, full render and export can never disagree about what is
/// active.
public struct EditorRenderPlan: Sendable, Equatable {
    public let effective: EditorEffectiveParameters
    public let blemishPoints: [BlemishPoint]
    public let backgroundProtection: Bool
    public let strength: Double

    public init(
        effective: EditorEffectiveParameters,
        blemishPoints: [BlemishPoint],
        backgroundProtection: Bool,
        strength: Double
    ) {
        self.effective = effective
        self.blemishPoints = blemishPoints
        self.backgroundProtection = backgroundProtection
        self.strength = strength
    }

    public var shouldRetouch: Bool {
        effective.skin != .neutral
    }

    public var shouldRemoveBlemishes: Bool {
        !blemishPoints.isEmpty
    }

    public var shouldWarp: Bool {
        effective.face != .neutral || effective.body != .neutral
    }

    public var shouldApplyTone: Bool {
        !effective.toneSettings.isNeutral
    }

    /// True when all stages can be skipped and the original image is already
    /// the correct preview and export output.
    public var isNoOp: Bool {
        !shouldRetouch && !shouldRemoveBlemishes && !shouldWarp && !shouldApplyTone
    }

    /// Plan for the given style, analysis and edit state.
    ///
    /// Areas the analysis did not find are neutralised here. Keeping that rule
    /// in one place means a disabled face tool can never leak a stale manual
    /// value into geometry.
    public static func make(
        style: StyleProfile,
        analysis: PortraitAnalysis,
        edits: EditorEditState
    ) -> EditorRenderPlan {
        let strength = EditorEditState.clampStrength(edits.strength)
        let backgroundProtection = edits.backgroundProtection

        var skin = SkinParameters(
            smoothing: blend(style.skin.smoothing, edits.adjustments.smoothing, strength: strength),
            evenness: blend(style.skin.evenness, edits.adjustments.evenness, strength: strength),
            blemish: blend(style.skin.blemish, edits.adjustments.blemish, strength: strength)
        )
        var face = FaceParameters(
            slim: blend(style.face.slim, edits.adjustments.faceSlim, strength: strength),
            jaw: blend(style.face.jaw, edits.adjustments.jaw, strength: strength)
        )
        var body = BodyParameters(
            arm: blend(style.body.arm, edits.adjustments.arm, strength: strength),
            waist: blend(style.body.waist, edits.adjustments.waist, strength: strength),
            leg: blend(style.body.leg, edits.adjustments.leg, strength: strength),
            legLength: blendLegLength(
                style.body.legLength,
                edits.adjustments.legLength,
                strength: strength
            )
        )
        let tone = ToneParameters(
            exposure: blend(
                style.tone.exposure,
                edits.adjustments.exposure,
                strength: strength,
                range: -1...1
            ),
            contrast: blend(
                style.tone.contrast,
                edits.adjustments.contrast,
                strength: strength,
                range: -1...1
            ),
            highlights: blend(style.tone.highlights, 0, strength: strength, range: -1...1),
            shadows: blend(style.tone.shadows, 0, strength: strength, range: -1...1),
            temperature: blend(
                style.tone.temperature,
                edits.adjustments.temperature,
                strength: strength,
                range: -1...1
            ),
            tint: blend(style.tone.tint, 0, strength: strength, range: -1...1),
            saturation: blend(
                style.tone.saturation,
                edits.adjustments.saturation,
                strength: strength,
                range: -1...1
            )
        )
        let finish = FinishParameters(
            grain: blend(style.finish.grain, edits.adjustments.grain, strength: strength),
            vignette: blend(style.finish.vignette, 0, strength: strength, neutral: 0, range: -1...0)
        )

        if !analysis.hasFace {
            skin = .neutral
            face = .neutral
        }
        if !analysis.hasBody {
            body = .neutral
        }

        let points = strength > 0 ? edits.blemishPoints : []

        return EditorRenderPlan(
            effective: EditorEffectiveParameters(
                tone: tone,
                skin: skin,
                face: face,
                body: body,
                finish: finish
            ),
            blemishPoints: points,
            backgroundProtection: backgroundProtection,
            strength: strength
        )
    }

    // MARK: - Blending

    private static func blend(
        _ styleValue: Double,
        _ manualValue: Double,
        strength: Double,
        neutral: Double = 0,
        range: ClosedRange<Double> = 0...1
    ) -> Double {
        let styleOffset = styleValue - neutral
        let manualOffset = manualValue - neutral
        let combined = neutral + (styleOffset + manualOffset) * strength
        return clamp(combined, to: range)
    }

    private static func blendLegLength(
        _ styleValue: Double,
        _ manualValue: Double,
        strength: Double
    ) -> Double {
        let styleOffset = styleValue - 1.0
        // ManualAdjustments uses 0 for "untouched"; the UI stores 1.0 once it
        // is moved. Treat both as a zero offset.
        let manualOffset = manualValue == 0 ? 0 : manualValue - 1.0
        let combined = 1.0 + (styleOffset + manualOffset) * strength
        return clamp(combined, to: 1.0...1.15)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
