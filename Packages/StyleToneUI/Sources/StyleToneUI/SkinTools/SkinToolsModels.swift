import CoreGraphics
import Foundation
import StyleToneCore

/// Fixed limits for the skin tools.
///
/// The blemish radius range mirrors the frozen `BlemishPoint` contract
/// (`docs/10-task-decomposition/contracts.md` §3.4): `0.005...0.08` of the
/// image's short edge. Everything else is a UI budget, not an algorithm limit:
/// the engines clamp their own inputs.
public enum SkinToolsLimits {
    public static let minimumSmoothing = 0.0
    public static let maximumSmoothing = 1.0
    public static let minimumEvenness = 0.0
    public static let maximumEvenness = 1.0

    /// Contract range for `BlemishPoint.radius`.
    public static let minimumRadius = 0.005
    public static let maximumRadius = 0.08
    public static let defaultRadius = 0.018
    public static let radiusStep = 0.001

    public static let minimumZoom = 1.0
    public static let maximumZoom = 6.0
    public static let zoomStep = 1.0

    /// Defensive cap so a stuck tap cannot grow the undo history without
    /// bound. The editor (WP-17) owns the global 20-step undo stack.
    public static let maximumBlemishes = 24

    public static let defaultRenderDelay: Duration = .milliseconds(120)
}

/// Tunables for ``SkinToolsViewModel``.
public struct SkinToolsConfiguration: Sendable, Equatable {
    /// Coalescing delay before a slider change is rendered. The editor may
    /// override it; tests use ``immediate(defaultRadius:maximumBlemishes:)``.
    public var renderDelay: Duration
    public var defaultRadius: Double
    public var maximumBlemishes: Int
    public var minimumZoom: Double
    public var maximumZoom: Double

    public init(
        renderDelay: Duration = SkinToolsLimits.defaultRenderDelay,
        defaultRadius: Double = SkinToolsLimits.defaultRadius,
        maximumBlemishes: Int = SkinToolsLimits.maximumBlemishes,
        minimumZoom: Double = SkinToolsLimits.minimumZoom,
        maximumZoom: Double = SkinToolsLimits.maximumZoom
    ) {
        self.renderDelay = renderDelay < .zero ? .zero : renderDelay
        self.defaultRadius = SkinToolsMath.clampRadius(defaultRadius)
        self.maximumBlemishes = max(1, maximumBlemishes)
        let lowerZoom = max(1, minimumZoom)
        self.minimumZoom = lowerZoom
        self.maximumZoom = max(lowerZoom, maximumZoom)
    }

    public static let standard = SkinToolsConfiguration()

    /// Immediate rendering. Used by tests, previews and hosts that already
    /// throttle at the editor level.
    public static func immediate(
        defaultRadius: Double = SkinToolsLimits.defaultRadius,
        maximumBlemishes: Int = SkinToolsLimits.maximumBlemishes
    ) -> SkinToolsConfiguration {
        SkinToolsConfiguration(
            renderDelay: .zero,
            defaultRadius: defaultRadius,
            maximumBlemishes: maximumBlemishes
        )
    }
}

/// One applied blemish repair.
///
/// The engine (`BlemishRemoving`) is stateless and returns a new image, so the
/// UI keeps only the point and radius. Undo re-renders the remaining list from
/// the last neutral skin image instead of holding full-resolution copies.
public struct BlemishEdit: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let point: NormalizedPoint
    public let radius: Double

    public init(id: UUID = UUID(), point: NormalizedPoint, radius: Double) {
        self.id = id
        self.point = SkinToolsMath.clampPoint(point)
        self.radius = SkinToolsMath.clampRadius(radius)
    }

    /// The value passed to `BlemishRemoving`.
    public var blemishPoint: BlemishPoint {
        BlemishPoint(point: point, radius: radius)
    }
}

/// A recoverable skin-tool failure.
///
/// The UI never replaces `displayedImage` or the committed blemish list on a
/// failure. It keeps the last valid result and offers a retry.
public struct SkinToolsFailure: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        /// Smoothing/evenness rendering failed.
        case retouch
        /// A new blemish repair failed.
        case blemish
        /// Undo (or clearing the marks) failed.
        case undo
    }

    public let kind: Kind
    public let underlying: StyleToneError?

    public init(kind: Kind, underlying: StyleToneError? = nil) {
        self.kind = kind
        self.underlying = underlying
    }

    /// All three failures are retryable; retry re-runs the same snapshot.
    public var canRetry: Bool { true }

    /// A short support code with no user data.
    public var diagnosticCode: String {
        underlying?.code ?? "E_RETOUCH"
    }
}

/// A non-error status shown above the controls.
public enum SkinToolsNotice: String, Sendable, Equatable, CaseIterable {
    /// The user cancelled an in-flight render; the previous result is intact.
    case renderingCancelled
    /// The defensive blemish cap was reached.
    case blemishLimitReached
}

/// Why the skin controls cannot operate on the current photo.
public enum SkinToolsUnavailableReason: String, Sendable, Equatable, CaseIterable {
    /// `PortraitAnalysis` has no face, so there is no skin region to treat.
    case noFace
    /// The analysis belongs to a different pixel size than the image.
    case analysisMismatch
}

/// How the panel behaves when the current photo has no usable analysis.
public enum SkinToolsUnavailableBehavior: String, Sendable, CaseIterable {
    /// Show an explanatory card and remove the controls.
    case disable
    /// Render nothing at all.
    case hide
}

/// Small numeric guards shared by the view model and geometry.
enum SkinToolsMath {
    static func clampUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    static func clampRadius(_ value: Double) -> Double {
        guard value.isFinite else { return SkinToolsLimits.defaultRadius }
        return min(max(value, SkinToolsLimits.minimumRadius), SkinToolsLimits.maximumRadius)
    }

    static func clampPoint(_ point: NormalizedPoint) -> NormalizedPoint {
        guard point.x.isFinite, point.y.isFinite else {
            return NormalizedPoint(x: 0.5, y: 0.5)
        }
        return point.clamped()
    }
}
