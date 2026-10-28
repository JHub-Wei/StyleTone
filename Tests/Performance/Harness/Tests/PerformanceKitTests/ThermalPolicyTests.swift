import XCTest
@testable import PerformanceKit

final class ThermalPolicyTests: XCTestCase {
    private let policy = ThermalPerformancePolicy()

    func testNominalReferenceDeviceStaysFull() {
        let degradation = policy.degradation(
            thermal: .nominal,
            power: .normal,
            deviceClass: .reference
        )
        XCTAssertEqual(degradation.tier, .full)
        XCTAssertEqual(degradation.previewLongEdge, 1280)
        XCTAssertTrue(degradation.allowsHighQualityRender)
        XCTAssertTrue(degradation.allowsExport)
        XCTAssertFalse(degradation.showsNotice)
        XCTAssertNil(degradation.noticeLocalizationKey)
        XCTAssertFalse(degradation.showsExportWarning)
        XCTAssertTrue(degradation.reasons.isEmpty)
    }

    func testLowEndDeviceStartsReduced() {
        let degradation = policy.degradation(
            thermal: .nominal,
            power: .normal,
            deviceClass: .lowEnd
        )
        XCTAssertEqual(degradation.tier, .reduced)
        XCTAssertEqual(degradation.previewLongEdge, 960)
        XCTAssertTrue(degradation.showsNotice)
        XCTAssertEqual(
            degradation.noticeLocalizationKey,
            "editor.performance.lowEnd"
        )
    }

    func testLowPowerModeDegradesOneTier() {
        let degradation = policy.degradation(
            thermal: .nominal,
            power: .lowPower,
            deviceClass: .reference
        )
        XCTAssertEqual(degradation.tier, .reduced)
        XCTAssertTrue(degradation.reasons.contains(.lowPowerMode))
        XCTAssertEqual(
            degradation.noticeLocalizationKey,
            "editor.performance.lowPower"
        )
    }

    func testFairThermalDegradesToReduced() {
        let degradation = policy.degradation(
            thermal: .fair,
            power: .normal,
            deviceClass: .reference
        )
        XCTAssertEqual(degradation.tier, .reduced)
        XCTAssertTrue(degradation.reasons.contains(.thermalFair))
        XCTAssertEqual(
            degradation.noticeLocalizationKey,
            "editor.performance.thermalFair"
        )
    }

    func testSeriousThermalGoesMinimalAndWarnsOnExport() {
        let degradation = policy.degradation(
            thermal: .serious,
            power: .normal,
            deviceClass: .reference
        )
        XCTAssertEqual(degradation.tier, .minimal)
        XCTAssertEqual(degradation.previewLongEdge, 640)
        XCTAssertTrue(degradation.allowsHighQualityRender)
        XCTAssertTrue(degradation.allowsExport)
        XCTAssertTrue(degradation.showsExportWarning)
        XCTAssertEqual(
            degradation.noticeLocalizationKey,
            "editor.performance.thermalSerious"
        )
    }

    func testCriticalThermalDefersFullRenderButNeverBlocksExport() {
        let degradation = policy.degradation(
            thermal: .critical,
            power: .normal,
            deviceClass: .reference
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

    func testAdaptiveGovernorCanOnlyMakeDegradationWorse() {
        let withGovernor = policy.degradation(
            thermal: .nominal,
            power: .normal,
            deviceClass: .reference,
            governorTier: .minimal
        )
        XCTAssertEqual(withGovernor.tier, .minimal)
        XCTAssertTrue(withGovernor.reasons.contains(.adaptiveGovernor))

        let governorDoesNotRecoverThermal = policy.degradation(
            thermal: .serious,
            power: .normal,
            deviceClass: .reference,
            governorTier: .full
        )
        XCTAssertEqual(governorDoesNotRecoverThermal.tier, .minimal)
    }

    func testCombinedStatesKeepEveryReason() {
        let degradation = policy.degradation(
            thermal: .fair,
            power: .lowPower,
            deviceClass: .lowEnd,
            governorTier: .minimal
        )
        XCTAssertEqual(degradation.tier, .minimal)
        XCTAssertEqual(
            Set(degradation.reasons),
            [.lowEndDevice, .thermalFair, .lowPowerMode, .adaptiveGovernor]
        )
        // Low power is the more actionable message when both apply.
        XCTAssertEqual(
            degradation.noticeLocalizationKey,
            "editor.performance.lowPower"
        )
    }

    func testTierOrdering() {
        XCTAssertLessThan(PreviewQualityTier.full, PreviewQualityTier.reduced)
        XCTAssertLessThan(PreviewQualityTier.reduced, PreviewQualityTier.minimal)
        XCTAssertLessThan(ThermalPressure.nominal, ThermalPressure.critical)
    }
}
