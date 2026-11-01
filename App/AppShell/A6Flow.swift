import Foundation

/// Phase A self-use flow stages.
///
/// The A6 build deliberately has no account, paywall, style-card or full
/// onboarding stage. The whole first-run journey is:
///
/// ```text
/// launch → welcome (no profile) → pairing → calibration → editor
///        ↘ editor (existing profile)
/// ```
///
/// `welcome` is the minimal local-only screen required by Phase A: it offers
/// "start pairing" and "use natural default" only.
enum A6Stage: String, CaseIterable, Sendable, Equatable {
    case launching
    case welcome
    case pairing
    case calibration
    case editor
}

/// Events that can move ``A6FlowState`` between stages.
///
/// The event carries no UI or service types so the state machine can be tested
/// without images, SwiftData or SwiftUI.
enum A6FlowEvent: Sendable, Equatable {
    /// The first profile read finished. `hasProfile == false` lands on the
    /// minimal welcome screen.
    case launch(hasProfile: Bool)
    /// Enter pairing (first run or recalibration from the editor).
    case beginPairing
    /// Pairing finished with at least the trial minimum of usable samples.
    case finishPairing
    /// Pairing was skipped; the host saves the natural default first.
    case skipPairing
    /// The user chose the natural default from welcome or calibration.
    case useNaturalDefault
    /// The calibrated profile was persisted and can be edited with.
    case completeCalibration
    /// Calibration was dismissed without completing; the host decides whether
    /// an existing profile is still active.
    case cancelCalibration(hasProfile: Bool)
    /// "Delete all local data" completed; every local profile is gone.
    case allDataDeleted
}

/// Pure stage machine for the A6 flow.
///
/// Keeping this free of services and associated image types makes the
/// transition rules unit-testable on any machine. The view model applies
/// side-effects (profile saves, sample hand-off) only after a transition is
/// accepted.
struct A6FlowState: Sendable, Equatable {
    private(set) var stage: A6Stage

    init(stage: A6Stage = .launching) {
        self.stage = stage
    }

    /// Applies `event` when it is valid for the current stage.
    ///
    /// - Returns: `true` when the stage changed (or the event was accepted);
    ///   `false` for an out-of-order action so callers can ignore duplicate
    ///   taps without corrupting the flow.
    @discardableResult
    mutating func reduce(_ event: A6FlowEvent) -> Bool {
        switch (stage, event) {
        case (.launching, .launch(let hasProfile)):
            stage = hasProfile ? .editor : .welcome
            return true

        case (.welcome, .beginPairing),
             (.editor, .beginPairing),
             (.calibration, .beginPairing):
            stage = .pairing
            return true

        case (.pairing, .finishPairing):
            stage = .calibration
            return true

        case (.pairing, .skipPairing),
             (.welcome, .useNaturalDefault),
             (.calibration, .useNaturalDefault),
             (.calibration, .completeCalibration):
            stage = .editor
            return true

        case (.calibration, .cancelCalibration(let hasProfile)):
            stage = hasProfile ? .editor : .welcome
            return true

        case (_, .allDataDeleted):
            stage = .welcome
            return true

        default:
            return false
        }
    }
}
