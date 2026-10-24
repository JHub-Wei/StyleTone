import Foundation
import StyleToneCore

/// Normalizes in-memory profiles before they are written or returned.
///
/// Core's parameter initializers already clamp decoded values. This type adds
/// the persistence-specific guarantees:
///
/// - non-finite doubles (possible when a caller constructs a profile in memory)
///   are replaced with the neutral value instead of failing JSON encoding;
/// - `schemaVersion` is always the current version;
/// - `algorithmVersion` is never empty;
/// - tags are trimmed, de-duplicated, capped and never localized display text.
public enum StyleProfileSanitizer {
    public static let maximumTagCount = 16
    public static let maximumTagLength = 64
    public static let maximumAlgorithmVersionLength = 32

    public static func sanitized(_ profile: StyleProfile) -> StyleProfile {
        StyleProfile(
            schemaVersion: StyleProfile.currentSchemaVersion,
            algorithmVersion: sanitizedAlgorithmVersion(profile.algorithmVersion),
            pairCount: max(0, profile.pairCount),
            confidence: profile.confidence,
            tone: ToneParameters(
                exposure: finite(profile.tone.exposure, in: -1...1),
                contrast: finite(profile.tone.contrast, in: -1...1),
                highlights: finite(profile.tone.highlights, in: -1...1),
                shadows: finite(profile.tone.shadows, in: -1...1),
                temperature: finite(profile.tone.temperature, in: -1...1),
                tint: finite(profile.tone.tint, in: -1...1),
                saturation: finite(profile.tone.saturation, in: -1...1)
            ),
            skin: SkinParameters(
                smoothing: finite(profile.skin.smoothing, in: 0...1),
                evenness: finite(profile.skin.evenness, in: 0...1),
                blemish: finite(profile.skin.blemish, in: 0...1)
            ),
            face: FaceParameters(
                slim: finite(profile.face.slim, in: 0...1),
                jaw: finite(profile.face.jaw, in: 0...1)
            ),
            body: BodyParameters(
                arm: finite(profile.body.arm, in: 0...1),
                waist: finite(profile.body.waist, in: 0...1),
                leg: finite(profile.body.leg, in: 0...1),
                legLength: finite(profile.body.legLength, in: 1.0...1.15)
            ),
            finish: FinishParameters(
                grain: finite(profile.finish.grain, in: 0...1),
                vignette: finite(profile.finish.vignette, in: -1...0)
            ),
            tags: sanitizedTags(profile.tags),
            updatedAt: profile.updatedAt
        )
    }

    private static func finite(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func sanitizedAlgorithmVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return StyleProfile.currentAlgorithmVersion
        }
        return String(trimmed.prefix(maximumAlgorithmVersionLength))
    }

    private static func sanitizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= maximumTagLength else {
                continue
            }
            guard seen.insert(trimmed).inserted else {
                continue
            }
            result.append(trimmed)
            if result.count == maximumTagCount {
                break
            }
        }
        return result
    }
}
