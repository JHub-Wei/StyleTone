import Foundation

private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}

public struct ToneParameters: Codable, Sendable, Equatable {
    public var exposure: Double
    public var contrast: Double
    public var highlights: Double
    public var shadows: Double
    public var temperature: Double
    public var tint: Double
    public var saturation: Double

    public init(
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        temperature: Double = 0,
        tint: Double = 0,
        saturation: Double = 0
    ) {
        self.exposure = clamp(exposure, to: -1...1)
        self.contrast = clamp(contrast, to: -1...1)
        self.highlights = clamp(highlights, to: -1...1)
        self.shadows = clamp(shadows, to: -1...1)
        self.temperature = clamp(temperature, to: -1...1)
        self.tint = clamp(tint, to: -1...1)
        self.saturation = clamp(saturation, to: -1...1)
    }

    public static let neutral = ToneParameters()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ToneParameters()
        self.init(
            exposure: try container.decodeIfPresent(Double.self, forKey: .exposure) ?? fallback.exposure,
            contrast: try container.decodeIfPresent(Double.self, forKey: .contrast) ?? fallback.contrast,
            highlights: try container.decodeIfPresent(Double.self, forKey: .highlights) ?? fallback.highlights,
            shadows: try container.decodeIfPresent(Double.self, forKey: .shadows) ?? fallback.shadows,
            temperature: try container.decodeIfPresent(Double.self, forKey: .temperature) ?? fallback.temperature,
            tint: try container.decodeIfPresent(Double.self, forKey: .tint) ?? fallback.tint,
            saturation: try container.decodeIfPresent(Double.self, forKey: .saturation) ?? fallback.saturation
        )
    }

    private enum CodingKeys: String, CodingKey {
        case exposure, contrast, highlights, shadows, temperature, tint, saturation
    }
}

public struct SkinParameters: Codable, Sendable, Equatable {
    public var smoothing: Double
    public var evenness: Double
    public var blemish: Double

    public init(smoothing: Double = 0, evenness: Double = 0, blemish: Double = 0) {
        self.smoothing = clamp(smoothing, to: 0...1)
        self.evenness = clamp(evenness, to: 0...1)
        self.blemish = clamp(blemish, to: 0...1)
    }

    public static let neutral = SkinParameters()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SkinParameters()
        self.init(
            smoothing: try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? fallback.smoothing,
            evenness: try container.decodeIfPresent(Double.self, forKey: .evenness) ?? fallback.evenness,
            blemish: try container.decodeIfPresent(Double.self, forKey: .blemish) ?? fallback.blemish
        )
    }

    private enum CodingKeys: String, CodingKey {
        case smoothing, evenness, blemish
    }
}

public struct FaceParameters: Codable, Sendable, Equatable {
    public var slim: Double
    public var jaw: Double

    public init(slim: Double = 0, jaw: Double = 0) {
        self.slim = clamp(slim, to: 0...1)
        self.jaw = clamp(jaw, to: 0...1)
    }

    public static let neutral = FaceParameters()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = FaceParameters()
        self.init(
            slim: try container.decodeIfPresent(Double.self, forKey: .slim) ?? fallback.slim,
            jaw: try container.decodeIfPresent(Double.self, forKey: .jaw) ?? fallback.jaw
        )
    }

    private enum CodingKeys: String, CodingKey {
        case slim, jaw
    }
}

public struct BodyParameters: Codable, Sendable, Equatable {
    public var arm: Double
    public var waist: Double
    public var leg: Double
    public var legLength: Double

    public init(
        arm: Double = 0,
        waist: Double = 0,
        leg: Double = 0,
        legLength: Double = 1.0
    ) {
        self.arm = clamp(arm, to: 0...1)
        self.waist = clamp(waist, to: 0...1)
        self.leg = clamp(leg, to: 0...1)
        self.legLength = clamp(legLength, to: 1.0...1.15)
    }

    public static let neutral = BodyParameters()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = BodyParameters()
        self.init(
            arm: try container.decodeIfPresent(Double.self, forKey: .arm) ?? fallback.arm,
            waist: try container.decodeIfPresent(Double.self, forKey: .waist) ?? fallback.waist,
            leg: try container.decodeIfPresent(Double.self, forKey: .leg) ?? fallback.leg,
            legLength: try container.decodeIfPresent(Double.self, forKey: .legLength) ?? fallback.legLength
        )
    }

    private enum CodingKeys: String, CodingKey {
        case arm, waist, leg, legLength
    }
}

public struct FinishParameters: Codable, Sendable, Equatable {
    public var grain: Double
    public var vignette: Double

    public init(grain: Double = 0, vignette: Double = 0) {
        self.grain = clamp(grain, to: 0...1)
        self.vignette = clamp(vignette, to: -1...0)
    }

    public static let neutral = FinishParameters()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = FinishParameters()
        self.init(
            grain: try container.decodeIfPresent(Double.self, forKey: .grain) ?? fallback.grain,
            vignette: try container.decodeIfPresent(Double.self, forKey: .vignette) ?? fallback.vignette
        )
    }

    private enum CodingKeys: String, CodingKey {
        case grain, vignette
    }
}
