import XCTest
import StyleToneCore
@testable import StyleToneUI

final class CalibrationCopyTests: XCTestCase {
    func testEveryKeyIsValidUniqueAndHasFallbackCopy() {
        let keys = CalibrationCopy.allKeys
        XCTAssertFalse(keys.isEmpty)
        XCTAssertEqual(Set(keys.map(\.rawValue)).count, keys.count)

        for key in keys {
            XCTAssertTrue(key.isValid, "Invalid key: \(key.rawValue)")
            XCTAssertEqual(key.prefix?.rawValue, LocalizationPrefix.calibration.rawValue)
            let fallback = CalibrationCopy.fallback(for: key)
            XCTAssertNotNil(fallback, "Missing fallback: \(key.rawValue)")
            XCTAssertFalse(fallback?.isEmpty ?? true)
        }
    }

    func testAccessibilityIdentifiersFollowConventionAndAreUnique() {
        let identifiers = AccessibilityID.calibrationAll
        XCTAssertFalse(identifiers.isEmpty)
        XCTAssertEqual(Set(identifiers.map(\.rawValue)).count, identifiers.count)

        for identifier in identifiers {
            XCTAssertTrue(identifier.isValid, "Invalid identifier: \(identifier.rawValue)")
            XCTAssertEqual(identifier.screen?.rawValue, AccessibilityScreen.calibration.rawValue)
        }
    }

    func testCalibrationCopyHasNoAccountEntry() {
        let entryWords = ["sign in", "log in", "login", "create account", "password", "user name"]
        for key in CalibrationCopy.allKeys {
            let fallback = (CalibrationCopy.fallback(for: key) ?? "").lowercased()
            for word in entryWords {
                XCTAssertFalse(
                    fallback.contains(word),
                    "Unexpected account entry in \(key.rawValue): \(fallback)"
                )
            }
        }

        let privacyNote = CalibrationCopy.text(CalibrationCopy.pairsLocalOnly).lowercased()
        XCTAssertTrue(privacyNote.contains("no account"))
        XCTAssertTrue(keysContainAccountOnlyAsPrivacyNote())
    }

    func testFormattingUsesArgumentsWithoutCrashing() {
        let progress = CalibrationCopy.format(CalibrationCopy.abProgress, 3, 8)
        XCTAssertTrue(progress.contains("3"))
        XCTAssertTrue(progress.contains("8"))

        let quality = CalibrationCopy.format(CalibrationCopy.pairsQuality, 2, 1, 0)
        XCTAssertTrue(quality.contains("2"))
        XCTAssertTrue(quality.contains("1"))

        let tier = CalibrationCopy.tierDescription(.five, availablePairs: 4)
        XCTAssertFalse(tier.isEmpty)
        XCTAssertTrue(tier.contains("5"))

        let pairSubtitle = CalibrationCopy.text(CalibrationCopy.pairsSubtitle)
        XCTAssertTrue(pairSubtitle.contains("4 minutes"))
        XCTAssertEqual(CalibrationLimits.pairStageTargetSeconds, 4 * 60)
    }

    func testDimensionAndDetailKeysExistForEveryCombination() {
        for dimension in CalibrationDimension.allCases {
            let key = CalibrationCopy.dimensionKey(for: dimension)
            XCTAssertNotNil(CalibrationCopy.fallback(for: key))
            XCTAssertTrue(key.isValid)

            for variant in [CalibrationComparisonOption.Variant.low, .high] {
                let detail = CalibrationCopy.detailKey(for: dimension, variant: variant)
                XCTAssertNotNil(CalibrationCopy.fallback(for: detail))
                XCTAssertTrue(detail.isValid)
            }
        }
    }

    func testABPlanCoversAllDimensionsAndIsDeterministic() {
        let plan = CalibrationComparison.planned
        XCTAssertEqual(plan.count, CalibrationLimits.plannedComparisonCount)
        for dimension in CalibrationDimension.allCases {
            XCTAssertTrue(
                plan.contains { $0.dimension == dimension },
                "Missing AB dimension: \(dimension)"
            )
        }
        XCTAssertEqual(plan.map(\.index), Array(0..<CalibrationLimits.plannedComparisonCount))
        XCTAssertEqual(CalibrationComparison.planned, plan)

        for comparison in plan {
            XCTAssertNotEqual(
                comparison.optionA.strengthDelta,
                comparison.optionB.strengthDelta
            )
            XCTAssertNotEqual(comparison.optionA.variant, comparison.optionB.variant)
        }
    }

    private func keysContainAccountOnlyAsPrivacyNote() -> Bool {
        let offenders = CalibrationCopy.allKeys.filter { key in
            let fallback = (CalibrationCopy.fallback(for: key) ?? "").lowercased()
            return fallback.contains("account") && key != CalibrationCopy.pairsLocalOnly
        }
        return offenders.isEmpty
    }
}
