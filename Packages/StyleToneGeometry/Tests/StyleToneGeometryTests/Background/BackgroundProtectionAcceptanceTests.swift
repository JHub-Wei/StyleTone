import Foundation
import StyleToneCore
import XCTest
@testable import StyleToneGeometry

/// Deterministic 100-case acceptance proxy for WP-15.
///
/// The real task card requires **100 authorized real-photo samples, manually
/// reviewed**. The repository intentionally contains no real photos
/// (`Fixtures/samples/` is empty by the privacy contract), so this test provides
/// the automated proxy: 100 synthetic door-frame / floor-tile / table-edge
/// backgrounds with a deterministic warp field, half of them with a synthetic
/// subject mask. It measures the same quantities a human review would rate:
///
/// - straight lines must not bend (`maximumLineDeviationAfter`);
/// - structure cores must not visibly translate (`maximumStructureDisplacementAfter`);
/// - the subject must keep its displacement (`subjectRetention`).
///
/// The manual protocol and its pending status are documented in
/// `Packages/StyleToneGeometry/Background/ACCEPTANCE.md`.
final class BackgroundProtectionAcceptanceTests: XCTestCase {
    private struct CaseResult {
        let index: Int
        let backgroundKind: String
        let detectedLines: Int
        let detectedRectangles: Int
        let distortion: Bool
        let detectionFailed: Bool
        let deviationBefore: Float
        let deviationAfter: Float
        let structureDisplacementAfter: Float
        let subjectRetention: Float
        let backgroundRetention: Float
    }

    private let constraint = BackgroundWarpConstraint()
    private let distortionDeviation: Float = 0.005
    private let distortionDisplacement: Float = 0.006

    func testHundredSyntheticBackgrounds() throws {
        var results: [CaseResult] = []
        results.reserveCapacity(100)
        for seed in 0 ..< 100 {
            results.append(try run(seed: seed))
        }

        let distorted = results.filter { $0.distortion }
        let detectionFailures = results.filter { $0.detectionFailed }
        let deviationBeforeMax = results.map(\.deviationBefore).max() ?? 0
        let deviationAfterMax = results.map(\.deviationAfter).max() ?? 0
        let displacementAfterMax = results.map(\.structureDisplacementAfter).max() ?? 0
        let subjectRetentionMin = results.map(\.subjectRetention).min() ?? 0
        let backgroundRetentionMean = results
            .map { Double($0.backgroundRetention) }
            .reduce(0, +) / Double(results.count)
        let casesWhereProtectionMatters = results.filter {
            $0.deviationBefore > distortionDeviation
        }.count

        print(
            "BACKGROUND_ACCEPTANCE cases=\(results.count) "
                + "distorted=\(distorted.count) "
                + "detectionFailures=\(detectionFailures.count) "
                + "casesWithBentLinesBefore=\(casesWhereProtectionMatters) "
                + "maxDeviationBefore=\(deviationBeforeMax) "
                + "maxDeviationAfter=\(deviationAfterMax) "
                + "maxStructureDisplacementAfter=\(displacementAfterMax) "
                + "minSubjectRetention=\(subjectRetentionMin) "
                + "meanBackgroundRetention=\(backgroundRetentionMean)"
        )

        XCTAssertEqual(detectionFailures.count, 0, "clean synthetic structures must be detected")
        XCTAssertGreaterThan(
            casesWhereProtectionMatters,
            10,
            "the corpus must contain cases where the field really bends lines"
        )
        XCTAssertLessThan(
            Double(distorted.count) / Double(results.count),
            0.05,
            "fewer than 5 % of cases may show obvious background distortion"
        )
        XCTAssertGreaterThanOrEqual(
            subjectRetentionMin,
            0.99,
            "background protection must not weaken subject slimming"
        )
    }

    private func run(seed: Int) throws -> CaseResult {
        let size = BackgroundTestSupport.compactSize
        let kind = seed % 3
        let hasSubject = seed.isMultiple(of: 2)
        let fieldKind = (seed / 3) % 4
        let amplitude = Float(0.015 + 0.005 * Double(seed % 4))
        let grid = 32

        let edgeMask: MaskBuffer
        let backgroundKind: String
        switch kind {
        case 0:
            backgroundKind = "door-frame"
            let left = 0.16 + 0.01 * Double(seed % 4)
            let top = 0.08 + 0.01 * Double(seed % 3)
            edgeMask = try BackgroundTestSupport.edgeMask(
                size: size,
                horizontal: [(top, left, 1 - left), (1 - top, left, 1 - left)],
                vertical: [(left, top, 1 - top), (1 - left, top, 1 - top)]
            )
        case 1:
            backgroundKind = "floor-tiles"
            let spacing = 0.22 + 0.02 * Double(seed % 3)
            edgeMask = try BackgroundTestSupport.gridMask(
                size: size,
                spacing: spacing,
                inset: 0.08
            )
        default:
            backgroundKind = "table-edge"
            let position = 0.42 + 0.02 * Double(seed % 8)
            let inset = 0.10 + 0.01 * Double(seed % 3)
            edgeMask = try BackgroundTestSupport.edgeMask(
                size: size,
                horizontal: [(position, inset, 1 - inset)],
                thickness: 3
            )
        }

        let personMask: MaskBuffer?
        if hasSubject {
            personMask = try BackgroundTestSupport.personMask(
                size: size,
                rect: NormalizedRect(x: 0.30, y: 0.08, width: 0.40, height: 0.84),
                feather: 0.08
            )
        } else {
            personMask = nil
        }
        let analysis = BackgroundTestSupport.analysis(
            size: size,
            personMask: personMask,
            edgeMask: edgeMask
        )

        let field: WarpField
        switch fieldKind {
        case 0:
            field = try BackgroundTestSupport.horizontalWaveField(
                dimension: grid,
                amplitude: amplitude,
                cycles: 1,
                phase: Double(seed % 5) * 0.3
            )
        case 1:
            field = try BackgroundTestSupport.field(dimension: grid) { x, _ in
                SIMD2<Float>(0, Float(Double(amplitude) * sin(2 * Double.pi * x)))
            }
        case 2:
            field = try BackgroundTestSupport.verticalBumpField(
                dimension: grid,
                amplitude: amplitude,
                centerX: 0.30 + 0.10 * Double(seed % 5),
                centerY: 0.40 + 0.10 * Double(seed % 3),
                sigma: 0.08
            )
        default:
            field = try BackgroundTestSupport.constantField(
                dimension: grid,
                offset: SIMD2<Float>(amplitude, amplitude * 0.5)
            )
        }

        let plan = try constraint.makePlan(field: field, analysis: analysis)
        let metrics = plan.metrics

        let detectionFailed: Bool
        switch kind {
        case 0:
            detectionFailed = plan.lines.count < 3 || plan.rectangles.isEmpty
        case 1:
            detectionFailed = plan.lines.count < 4 || plan.rectangles.isEmpty
        default:
            detectionFailed = plan.lines.isEmpty
        }

        let distortion = metrics.maximumLineDeviationAfter > distortionDeviation
            || metrics.maximumStructureDisplacementAfter > distortionDisplacement

        return CaseResult(
            index: seed,
            backgroundKind: backgroundKind,
            detectedLines: plan.lines.count,
            detectedRectangles: plan.rectangles.count,
            distortion: distortion,
            detectionFailed: detectionFailed,
            deviationBefore: metrics.maximumLineDeviationBefore,
            deviationAfter: metrics.maximumLineDeviationAfter,
            structureDisplacementAfter: metrics.maximumStructureDisplacementAfter,
            subjectRetention: hasSubject ? metrics.subjectRetention : 1,
            backgroundRetention: metrics.backgroundRetention
        )
    }
}
