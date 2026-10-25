import Foundation

/// Editor-owned localized copy and accessibility identifiers.
///
/// Keys use the frozen `editor.` prefix. English fallbacks keep the screen
/// readable until WP-26 ships the string catalog; no user-visible text is
/// hardcoded in views.
public enum EditorCopy {
    // MARK: Areas

    public static let areaFace = LocalizationKey("editor.area.face")
    public static let areaBody = LocalizationKey("editor.area.body")
    public static let areaSkin = LocalizationKey("editor.area.skin")
    public static let areaTone = LocalizationKey("editor.area.tone")
    public static let areaUnavailableNoFace = LocalizationKey("editor.areaUnavailable.noFace")
    public static let areaUnavailableNoBody = LocalizationKey("editor.areaUnavailable.noBody")

    // MARK: Sliders

    public static let sliderFaceSlim = LocalizationKey("editor.slider.faceSlim")
    public static let sliderJaw = LocalizationKey("editor.slider.jaw")
    public static let sliderArm = LocalizationKey("editor.slider.arm")
    public static let sliderWaist = LocalizationKey("editor.slider.waist")
    public static let sliderLeg = LocalizationKey("editor.slider.leg")
    public static let sliderLegLength = LocalizationKey("editor.slider.legLength")
    public static let sliderSmoothing = LocalizationKey("editor.slider.smoothing")
    public static let sliderEvenness = LocalizationKey("editor.slider.evenness")
    public static let sliderBlemish = LocalizationKey("editor.slider.blemish")
    public static let sliderExposure = LocalizationKey("editor.slider.exposure")
    public static let sliderContrast = LocalizationKey("editor.slider.contrast")
    public static let sliderTemperature = LocalizationKey("editor.slider.temperature")
    public static let sliderSaturation = LocalizationKey("editor.slider.saturation")
    public static let sliderGrain = LocalizationKey("editor.slider.grain")

    // MARK: Canvas and shell actions

    public static let title = L10n.editorTitle
    public static let subtitle = L10n.editorSubtitle
    public static let note = L10n.editorNote
    public static let canvasEmptyTitle = L10n.editorCanvasEmptyTitle
    public static let canvasEmptyMessage = L10n.editorCanvasEmptyMessage
    public static let canvasLabel = LocalizationKey("editor.canvas.label")
    public static let canvasHint = LocalizationKey("editor.canvas.hint")
    public static let addPhotoButton = L10n.editorAddPhotoButton
    public static let exportButton = L10n.editorExportButton
    public static let styleButton = L10n.editorStyleButton
    public static let emptyState = LocalizationKey("editor.emptyState")

    // MARK: Strength and presets

    public static let strength = LocalizationKey("editor.strength")
    public static let strengthHint = LocalizationKey("editor.strengthHint")
    public static let naturalPreset = LocalizationKey("editor.naturalPreset")
    public static let naturalPresetHint = LocalizationKey("editor.naturalPresetHint")

    // MARK: Comparison

    public static let undo = LocalizationKey("editor.undo")
    public static let redo = LocalizationKey("editor.redo")
    public static let reset = LocalizationKey("editor.reset")
    public static let splitComparison = LocalizationKey("editor.splitComparison")
    public static let splitComparisonHint = LocalizationKey("editor.splitComparisonHint")
    public static let zoomReset = LocalizationKey("editor.zoomReset")
    public static let compareHint = LocalizationKey("editor.compareHint")
    public static let compareOriginal = LocalizationKey("editor.compareOriginal")
    public static let compareEdited = LocalizationKey("editor.compareEdited")

    // MARK: Background protection

    public static let backgroundProtection = LocalizationKey("editor.backgroundProtection")
    public static let backgroundProtectionHint = LocalizationKey("editor.backgroundProtectionHint")
    public static let backgroundProtectionOffTitle = LocalizationKey("editor.backgroundProtectionOff.title")
    public static let backgroundProtectionOffMessage = LocalizationKey("editor.backgroundProtectionOff.message")
    public static let backgroundProtectionOffConfirm = LocalizationKey("editor.backgroundProtectionOff.confirm")
    public static let cancel = LocalizationKey("editor.cancel")

    // MARK: Blemish points

    public static let blemishPoints = LocalizationKey("editor.blemishPoints")
    public static let blemishRemove = LocalizationKey("editor.blemishRemove")
    public static let blemishClear = LocalizationKey("editor.blemishClear")
    public static let blemishEmpty = LocalizationKey("editor.blemishEmpty")

    // MARK: Status

    public static let analysisLoading = LocalizationKey("editor.status.analysisLoading")
    public static let renderingPreview = LocalizationKey("editor.status.renderingPreview")
    public static let renderingFull = LocalizationKey("editor.status.renderingFull")
    public static let degradedBadge = LocalizationKey("editor.status.degraded")
    public static let previewBadge = LocalizationKey("editor.status.preview")
    public static let exporting = LocalizationKey("editor.status.exporting")
    public static let exportCompleted = LocalizationKey("editor.status.exportCompleted")

    // MARK: Warnings

    public static let warningNoFace = LocalizationKey("editor.warning.noFace")
    public static let warningMultipleFaces = LocalizationKey("editor.warning.multipleFaces")
    public static let warningNoBody = LocalizationKey("editor.warning.noBody")
    public static let warningOcclusion = LocalizationKey("editor.warning.occlusion")
    public static let warningLowLight = LocalizationKey("editor.warning.lowLight")
    public static let warningLowConfidence = LocalizationKey("editor.warning.lowConfidence")
    public static let warningBackgroundRisk = LocalizationKey("editor.warning.backgroundRisk")

    // MARK: Recoverable issues

    public static let issueRetry = LocalizationKey("editor.issue.retry")
    public static let issueDismiss = LocalizationKey("editor.issue.dismiss")
    public static let issueUseNatural = LocalizationKey("editor.issue.useNatural")
    public static let issueAnalysisTitle = LocalizationKey("editor.issue.analysis.title")
    public static let issueAnalysisMessage = LocalizationKey("editor.issue.analysis.message")
    public static let issueStyleTitle = LocalizationKey("editor.issue.style.title")
    public static let issueStyleMessage = LocalizationKey("editor.issue.style.message")
    public static let issueRenderTitle = LocalizationKey("editor.issue.render.title")
    public static let issueRenderMessage = LocalizationKey("editor.issue.render.message")
    public static let issueExportTitle = LocalizationKey("editor.issue.export.title")
    public static let issueExportMessage = LocalizationKey("editor.issue.export.message")

    /// Every key defined by the editor, for documentation and tests.
    public static let allKeys: [LocalizationKey] = [
        areaFace, areaBody, areaSkin, areaTone,
        areaUnavailableNoFace, areaUnavailableNoBody,
        sliderFaceSlim, sliderJaw, sliderArm, sliderWaist, sliderLeg, sliderLegLength,
        sliderSmoothing, sliderEvenness, sliderBlemish,
        sliderExposure, sliderContrast, sliderTemperature, sliderSaturation, sliderGrain,
        title, subtitle, note, canvasEmptyTitle, canvasEmptyMessage, canvasLabel, canvasHint,
        addPhotoButton, exportButton, styleButton, emptyState,
        strength, strengthHint, naturalPreset, naturalPresetHint,
        undo, redo, reset,
        splitComparison, splitComparisonHint, zoomReset, compareHint, compareOriginal, compareEdited,
        backgroundProtection, backgroundProtectionHint,
        backgroundProtectionOffTitle, backgroundProtectionOffMessage, backgroundProtectionOffConfirm, cancel,
        blemishPoints, blemishRemove, blemishClear, blemishEmpty,
        analysisLoading, renderingPreview, renderingFull, degradedBadge, previewBadge,
        exporting, exportCompleted,
        warningNoFace, warningMultipleFaces, warningNoBody, warningOcclusion,
        warningLowLight, warningLowConfidence, warningBackgroundRisk,
        issueRetry, issueDismiss, issueUseNatural,
        issueAnalysisTitle, issueAnalysisMessage, issueStyleTitle, issueStyleMessage,
        issueRenderTitle, issueRenderMessage, issueExportTitle, issueExportMessage,
    ]

    /// Resolves a key with its English development fallback.
    public static func text(_ key: LocalizationKey) -> String {
        L10n.resolve(key, fallback: fallbacks[key.rawValue] ?? key.rawValue)
    }

    private static let fallbacks: [String: String] = [
        "editor.area.face": "Face",
        "editor.area.body": "Body",
        "editor.area.skin": "Skin",
        "editor.area.tone": "Tone",
        "editor.areaUnavailable.noFace": "No face found, so face and skin tools are off.",
        "editor.areaUnavailable.noBody": "No body found, so body tools are off.",

        "editor.slider.faceSlim": "Face slim",
        "editor.slider.jaw": "Jaw",
        "editor.slider.arm": "Arms",
        "editor.slider.waist": "Waist",
        "editor.slider.leg": "Legs",
        "editor.slider.legLength": "Leg length",
        "editor.slider.smoothing": "Smoothing",
        "editor.slider.evenness": "Evenness",
        "editor.slider.blemish": "Blemish",
        "editor.slider.exposure": "Exposure",
        "editor.slider.contrast": "Contrast",
        "editor.slider.temperature": "Temperature",
        "editor.slider.saturation": "Saturation",
        "editor.slider.grain": "Grain",

        "editor.title": "Editor",
        "editor.subtitle": "Adjust the texture and structure that matter to you.",
        "editor.note": "Photos stay on this device.",
        "editor.canvas.emptyTitle": "Choose a portrait",
        "editor.canvas.emptyMessage": "Pick one photo to edit. It is processed locally.",
        "editor.canvas.label": "Photo preview",
        "editor.canvas.hint": "Press and hold to see the original. Pinch to zoom.",
        "editor.addPhotoButton": "Add photo",
        "editor.exportButton": "Export",
        "editor.styleButton": "Style",
        "editor.emptyState": "No photo yet",

        "editor.strength": "Total strength",
        "editor.strengthHint": "Scales the style and every manual adjustment together. Zero shows the original.",
        "editor.naturalPreset": "Natural 70%",
        "editor.naturalPresetHint": "A conservative starting point. You can still adjust every tool.",

        "editor.undo": "Undo",
        "editor.redo": "Redo",
        "editor.reset": "Reset",
        "editor.splitComparison": "Split",
        "editor.splitComparisonHint": "Drag the divider to compare the original and the edit.",
        "editor.zoomReset": "Fit",
        "editor.compareHint": "Press and hold the photo to see the original.",
        "editor.compareOriginal": "Original",
        "editor.compareEdited": "Edited",

        "editor.backgroundProtection": "Protect background",
        "editor.backgroundProtectionHint": "Keeps straight lines and edges stable while the portrait is reshaped.",
        "editor.backgroundProtectionOff.title": "Turn off background protection?",
        "editor.backgroundProtectionOff.message": "Walls, door frames and other straight lines may bend.",
        "editor.backgroundProtectionOff.confirm": "Turn off",
        "editor.cancel": "Cancel",

        "editor.blemishPoints": "Blemish points",
        "editor.blemishRemove": "Remove last point",
        "editor.blemishClear": "Clear points",
        "editor.blemishEmpty": "No blemish points yet.",

        "editor.status.analysisLoading": "Finding the face and body",
        "editor.status.renderingPreview": "Updating preview",
        "editor.status.renderingFull": "Rendering full quality",
        "editor.status.degraded": "Reduced preview quality",
        "editor.status.preview": "Preview",
        "editor.status.exporting": "Exporting",
        "editor.status.exportCompleted": "Export ready",

        "editor.warning.noFace": "No face detected. Face and skin tools are unavailable.",
        "editor.warning.multipleFaces": "Several faces detected. Start with the main subject and check the result.",
        "editor.warning.noBody": "No body detected. Body tools are unavailable.",
        "editor.warning.occlusion": "Part of the portrait is covered. Results may be uneven.",
        "editor.warning.lowLight": "Low light. Skin and tone results may be noisier.",
        "editor.warning.lowConfidence": "The portrait was detected with low confidence. Check the result before exporting.",
        "editor.warning.backgroundRisk": "Background protection is off. Straight lines may bend.",

        "editor.issue.retry": "Try again",
        "editor.issue.dismiss": "Dismiss",
        "editor.issue.useNatural": "Use natural strength",
        "editor.issue.analysis.title": "Portrait analysis failed",
        "editor.issue.analysis.message": "The photo is still here. Try the analysis again or edit tone only.",
        "editor.issue.style.title": "Personal style unavailable",
        "editor.issue.style.message": "Using the natural default. Your photo is unchanged until you adjust a tool.",
        "editor.issue.render.title": "Rendering failed",
        "editor.issue.render.message": "The previous preview is unchanged. Try again or lower the strength.",
        "editor.issue.export.title": "Export failed",
        "editor.issue.export.message": "Nothing was saved. Check the export options and try again.",
    ]
}

// MARK: - Accessibility identifiers

/// Editor identifiers. The three frozen slider identifiers plus the canvas,
/// photo, export and style buttons come from the design system; the rest are
/// added here under the same `editor.` screen.
public enum EditorAccessibility {
    public static let root = AccessibilityID(.editor, "root")
    public static let tabFace = AccessibilityID(.editor, "tab.face")
    public static let tabBody = AccessibilityID(.editor, "tab.body")
    public static let tabSkin = AccessibilityID(.editor, "tab.skin")
    public static let tabTone = AccessibilityID(.editor, "tab.tone")

    public static let armSlider = AccessibilityID(.editor, "armSlider")
    public static let waistSlider = AccessibilityID(.editor, "waistSlider")
    public static let legSlider = AccessibilityID(.editor, "legSlider")
    public static let legLengthSlider = AccessibilityID(.editor, "legLengthSlider")
    public static let evennessSlider = AccessibilityID(.editor, "evennessSlider")
    public static let blemishSlider = AccessibilityID(.editor, "blemishSlider")
    public static let exposureSlider = AccessibilityID(.editor, "exposureSlider")
    public static let contrastSlider = AccessibilityID(.editor, "contrastSlider")
    public static let temperatureSlider = AccessibilityID(.editor, "temperatureSlider")
    public static let saturationSlider = AccessibilityID(.editor, "saturationSlider")
    public static let grainSlider = AccessibilityID(.editor, "grainSlider")

    public static let strengthSlider = AccessibilityID(.editor, "strengthSlider")
    public static let naturalButton = AccessibilityID(.editor, "naturalButton")
    public static let backgroundProtectionToggle = AccessibilityID(.editor, "backgroundProtectionToggle")
    public static let undoButton = AccessibilityID(.editor, "undoButton")
    public static let redoButton = AccessibilityID(.editor, "redoButton")
    public static let resetButton = AccessibilityID(.editor, "resetButton")

    public static let splitToggle = AccessibilityID(.editor, "splitToggle")
    public static let splitHandle = AccessibilityID(.editor, "splitHandle")
    public static let zoomResetButton = AccessibilityID(.editor, "zoomResetButton")
    public static let compareHint = AccessibilityID(.editor, "compareHint")

    public static let warningBanner = AccessibilityID(.editor, "warningBanner")
    public static let issueBanner = AccessibilityID(.editor, "issueBanner")
    public static let issueRetryButton = AccessibilityID(.editor, "issue.retryButton")
    public static let issueDismissButton = AccessibilityID(.editor, "issue.dismissButton")

    public static let renderingIndicator = AccessibilityID(.editor, "renderingIndicator")
    public static let exportProgress = AccessibilityID(.editor, "exportProgress")
    public static let emptyState = AccessibilityID(.editor, "emptyState")
    public static let blemishRemoveButton = AccessibilityID(.editor, "blemishRemoveButton")
    public static let blemishClearButton = AccessibilityID(.editor, "blemishClearButton")

    /// Identifiers frozen by WP-03 and reused by the editor.
    public static let frozenIdentifiers: [AccessibilityID] = [
        AccessibilityID.editorCanvas,
        AccessibilityID.editorFaceSlimSlider,
        AccessibilityID.editorJawSlider,
        AccessibilityID.editorSmoothingSlider,
        AccessibilityID.editorAddPhotoButton,
        AccessibilityID.editorExportButton,
        AccessibilityID.editorStyleButton,
    ]

    /// Identifiers introduced by WP-17.
    public static let newIdentifiers: [AccessibilityID] = [
        root, tabFace, tabBody, tabSkin, tabTone,
        armSlider, waistSlider, legSlider, legLengthSlider,
        evennessSlider, blemishSlider,
        exposureSlider, contrastSlider, temperatureSlider, saturationSlider, grainSlider,
        strengthSlider, naturalButton, backgroundProtectionToggle,
        undoButton, redoButton, resetButton,
        splitToggle, splitHandle, zoomResetButton, compareHint,
        warningBanner, issueBanner, issueRetryButton, issueDismissButton,
        renderingIndicator, exportProgress, emptyState,
        blemishRemoveButton, blemishClearButton,
    ]

    /// Frozen plus new identifiers, without duplicates.
    public static let all: [AccessibilityID] = frozenIdentifiers + newIdentifiers

    /// The identifier for one slider, reusing the three frozen identifiers.
    public static func adjustmentID(for adjustment: EditorAdjustment) -> AccessibilityID {
        switch adjustment {
        case .faceSlim:
            return AccessibilityID.editorFaceSlimSlider
        case .jaw:
            return AccessibilityID.editorJawSlider
        case .smoothing:
            return AccessibilityID.editorSmoothingSlider
        case .arm:
            return armSlider
        case .waist:
            return waistSlider
        case .leg:
            return legSlider
        case .legLength:
            return legLengthSlider
        case .evenness:
            return evennessSlider
        case .blemish:
            return blemishSlider
        case .exposure:
            return exposureSlider
        case .contrast:
            return contrastSlider
        case .temperature:
            return temperatureSlider
        case .saturation:
            return saturationSlider
        case .grain:
            return grainSlider
        }
    }
}
