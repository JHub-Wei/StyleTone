import Foundation

public struct ManualAdjustments: Codable, Sendable, Equatable {
    public var exposure: Double
    public var contrast: Double
    public var temperature: Double
    public var saturation: Double
    public var grain: Double
    public var faceSlim: Double
    public var jaw: Double
    public var arm: Double
    public var waist: Double
    public var leg: Double
    public var legLength: Double
    public var smoothing: Double
    public var evenness: Double
    public var blemish: Double

    public init(
        exposure: Double = 0,
        contrast: Double = 0,
        temperature: Double = 0,
        saturation: Double = 0,
        grain: Double = 0,
        faceSlim: Double = 0,
        jaw: Double = 0,
        arm: Double = 0,
        waist: Double = 0,
        leg: Double = 0,
        legLength: Double = 0,
        smoothing: Double = 0,
        evenness: Double = 0,
        blemish: Double = 0
    ) {
        self.exposure = exposure
        self.contrast = contrast
        self.temperature = temperature
        self.saturation = saturation
        self.grain = grain
        self.faceSlim = faceSlim
        self.jaw = jaw
        self.arm = arm
        self.waist = waist
        self.leg = leg
        self.legLength = legLength
        self.smoothing = smoothing
        self.evenness = evenness
        self.blemish = blemish
    }

    public var isNeutral: Bool {
        self == ManualAdjustments()
    }
}

public struct BlemishPoint: Sendable, Equatable {
    public let point: NormalizedPoint
    public let radius: Double

    public init(point: NormalizedPoint, radius: Double) {
        self.point = point
        self.radius = min(max(radius, 0.005), 0.08)
    }
}

public struct RenderRequest: Sendable {
    public let image: ImageAsset
    public let analysis: PortraitAnalysis
    public let style: StyleProfile
    public let strength: Double
    public let adjustments: ManualAdjustments
    public let backgroundProtection: Bool
    public let blemishPoints: [BlemishPoint]

    public init(
        image: ImageAsset,
        analysis: PortraitAnalysis,
        style: StyleProfile,
        strength: Double = 1.0,
        adjustments: ManualAdjustments = ManualAdjustments(),
        backgroundProtection: Bool = true,
        blemishPoints: [BlemishPoint] = []
    ) {
        self.image = image
        self.analysis = analysis
        self.style = style
        self.strength = min(max(strength, 0), 1.5)
        self.adjustments = adjustments
        self.backgroundProtection = backgroundProtection
        self.blemishPoints = blemishPoints
    }
}

public struct RenderWarning: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case noFace
        case noBody
        case occlusion
        case lowConfidence
        case backgroundRisk
    }

    public let kind: Kind
    public let messageKey: String

    public init(kind: Kind, messageKey: String) {
        self.kind = kind
        self.messageKey = messageKey
    }
}

public struct RenderOutput: Sendable {
    public let image: ImageAsset
    public let warnings: [RenderWarning]
    public let duration: TimeInterval

    public init(image: ImageAsset, warnings: [RenderWarning] = [], duration: TimeInterval = 0) {
        self.image = image
        self.warnings = warnings
        self.duration = max(0, duration)
    }
}
