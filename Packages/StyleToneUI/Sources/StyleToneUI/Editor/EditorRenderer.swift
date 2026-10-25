import Foundation
import StyleToneCore

/// Protocol-only implementation of the frozen render pipeline order from
/// `contracts §5`:
///
/// 1. analysis output is consumed as input (WP-05 already ran);
/// 2. skin retouch (WP-07) and explicit blemish points;
/// 3. geometry warp (WP-06/12/13/14/15);
/// 4. tone/colour/finish (`EditorToneRendering`);
/// 5. the completed `RenderOutput` is returned for display or export.
///
/// This type contains no image algorithm and no network or file access. A
/// no-op request returns the exact input `ImageAsset` without invoking any
/// engine, which is what makes preview and export bit-identical to the original
/// when nothing is edited.
public struct EditorRenderer: ImageRendering {
    private let retoucher: any RetouchRendering
    private let blemishRemover: any BlemishRemoving
    private let geometryRenderer: any GeometryRendering
    private let toneRenderer: any EditorToneRendering
    private let dateProvider: any DateProviding

    public init(
        retoucher: any RetouchRendering,
        blemishRemover: any BlemishRemoving,
        geometryRenderer: any GeometryRendering,
        toneRenderer: any EditorToneRendering = PassthroughToneRenderer(),
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.retoucher = retoucher
        self.blemishRemover = blemishRemover
        self.geometryRenderer = geometryRenderer
        self.toneRenderer = toneRenderer
        self.dateProvider = dateProvider
    }

    public func render(_ request: RenderRequest) async throws -> RenderOutput {
        let startedAt = dateProvider.now
        let edits = EditorEditState(
            adjustments: request.adjustments,
            strength: request.strength,
            backgroundProtection: request.backgroundProtection,
            blemishPoints: request.blemishPoints
        )
        let plan = EditorRenderPlan.make(
            style: request.style,
            analysis: request.analysis,
            edits: edits
        )
        let warnings = Self.renderWarnings(for: plan, analysis: request.analysis)

        if plan.isNoOp {
            return RenderOutput(
                image: request.image,
                warnings: warnings,
                duration: Self.duration(since: startedAt, now: dateProvider.now)
            )
        }

        var image = request.image

        if plan.shouldRetouch {
            try Task.checkCancellation()
            image = try await retoucher.retouch(
                image,
                analysis: request.analysis,
                parameters: plan.effective.skin
            )
        }

        if plan.shouldRemoveBlemishes {
            // Smoothing runs first so a point repair is not softened afterwards.
            for point in plan.blemishPoints {
                try Task.checkCancellation()
                image = try await blemishRemover.removeBlemish(
                    image,
                    at: point,
                    analysis: request.analysis
                )
            }
        }

        if plan.shouldWarp {
            try Task.checkCancellation()
            image = try await geometryRenderer.warp(
                image,
                analysis: request.analysis,
                parameters: plan.effective.face,
                body: plan.effective.body,
                backgroundProtection: plan.backgroundProtection
            )
        }

        if plan.shouldApplyTone {
            try Task.checkCancellation()
            image = try await toneRenderer.applyTone(
                image,
                settings: plan.effective.toneSettings,
                analysis: request.analysis
            )
        }

        try Task.checkCancellation()
        return RenderOutput(
            image: image,
            warnings: warnings,
            duration: Self.duration(since: startedAt, now: dateProvider.now)
        )
    }

    /// Scene warnings the renderer can attribute to its own stages. Analysis
    /// warnings the Core `RenderWarning.Kind` cannot express (`multipleFaces`,
    /// `lowLight`) remain the view model's responsibility.
    static func renderWarnings(
        for plan: EditorRenderPlan,
        analysis: PortraitAnalysis
    ) -> [RenderWarning] {
        var warnings: [RenderWarning] = []

        for warning in analysis.warnings {
            switch warning {
            case .noFace:
                warnings.append(
                    RenderWarning(kind: .noFace, messageKey: "editor.warning.noFace")
                )
            case .noBody:
                warnings.append(
                    RenderWarning(kind: .noBody, messageKey: "editor.warning.noBody")
                )
            case .occlusion:
                warnings.append(
                    RenderWarning(kind: .occlusion, messageKey: "editor.warning.occlusion")
                )
            case .lowConfidence:
                warnings.append(
                    RenderWarning(
                        kind: .lowConfidence,
                        messageKey: "editor.warning.lowConfidence"
                    )
                )
            case .multipleFaces, .lowLight:
                continue
            }
        }

        if plan.shouldWarp && !plan.backgroundProtection {
            warnings.append(
                RenderWarning(
                    kind: .backgroundRisk,
                    messageKey: "editor.warning.backgroundRisk"
                )
            )
        }

        var seen = Set<String>()
        return warnings.filter { seen.insert($0.kind.rawValue).inserted }
    }

    private static func duration(since start: Date, now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(start))
    }
}
