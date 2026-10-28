import Foundation
import PerformanceKit
import StyleToneUI
import XCTest

/// Verifies the thermal/low-power/low-end policy and its compatibility with the
/// WP-17 adaptive governor. Hardware thermal transitions cannot be induced in
/// CI; the device runbook in `docs/performance/instruments.md` covers the soak.
final class ThermalPolicyPerformanceTests: XCTestCase {
    private let policy = ThermalPerformancePolicy()

    func testCurrentStateProducesAConsistentPolicy() {
        let thermal = Self.currentThermalPressure()
        let power: PowerReserve = ProcessInfo.processInfo.isLowPowerModeEnabled
            ? .lowPower
            : .normal
        let degradation = policy.degradation(
            thermal: thermal,
            power: power,
            deviceClass: PerformanceTestEnvironment.deviceClass
        )

        XCTAssertEqual(
            degradation.previewLongEdge,
            degradation.tier.previewLongEdge
        )
        XCTAssertTrue(degradation.allowsExport, "export must never be silently blocked")
        XCTAssertEqual(
            degradation.showsNotice,
            !degradation.reasons.isEmpty,
            "a notice is shown exactly when a reason contributed"
        )
        if degradation.tier != .full {
            XCTAssertTrue(degradation.showsNotice)
            XCTAssertNotNil(degradation.noticeLocalizationKey)
        }
    }

    func testGovernorTierMapsToOneToOneIntoThePolicy() {
        var governor = EditorPerformanceGovernor()
        XCTAssertEqual(governor.level, .full)

        governor.record(duration: 0.5, quality: .preview)
        governor.record(duration: 0.5, quality: .preview)
        XCTAssertEqual(governor.level, .reduced)

        governor.record(duration: 0.5, quality: .preview)
        governor.record(duration: 0.5, quality: .preview)
        XCTAssertEqual(governor.level, .minimal)

        let tier = PreviewQualityTier(rawValue: governor.level.rawValue)
        XCTAssertEqual(tier, .minimal)

        let degradation = policy.degradation(
            thermal: .nominal,
            power: .normal,
            deviceClass: .reference,
            governorTier: tier ?? .full
        )
        XCTAssertEqual(degradation.tier, .minimal)
        XCTAssertTrue(degradation.reasons.contains(.adaptiveGovernor))
    }

    func testThermalPressureIsMonotonic() {
        var previous = PreviewQualityTier.full
        for thermal in ThermalPressure.allCases {
            let degradation = policy.degradation(
                thermal: thermal,
                power: .normal,
                deviceClass: .reference
            )
            XCTAssertGreaterThanOrEqual(degradation.tier, previous)
            previous = degradation.tier
        }
    }

    func testCriticalThermalDefersFullRenderButKeepsExport() {
        let degradation = policy.degradation(
            thermal: .critical,
            power: .lowPower,
            deviceClass: .lowEnd
        )
        XCTAssertEqual(degradation.tier, .minimal)
        XCTAssertFalse(degradation.allowsHighQualityRender)
        XCTAssertTrue(degradation.allowsExport)
        XCTAssertTrue(degradation.showsExportWarning)
        XCTAssertEqual(
            degradation.noticeLocalizationKey,
            "editor.performance.thermalCritical"
        )
    }

    // MARK: - Mapping

    private static func currentThermalPressure() -> ThermalPressure {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .fair
        }
    }
}
