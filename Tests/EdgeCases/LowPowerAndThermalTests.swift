import StyleToneUI
import XCTest

/// Low-power, low-battery, thermal and storage advisories are notices, never
/// blockers, and they never duplicate themselves.
final class LowPowerAndThermalTests: XCTestCase {
    private let advisor = ErrorAdvisor.standard

    func testLowPowerModeRaisesOneNotice() {
        let states = advisor.advisories(
            for: DeviceConditions(isLowPowerModeEnabled: true, batteryLevel: 0.9)
        )

        XCTAssertEqual(states.count, 1)
        guard let state = states.first else {
            return XCTFail("expected a low-battery advisory")
        }
        XCTAssertEqual(state.kind, .lowBattery)
        XCTAssertEqual(state.severity, .notice)
        XCTAssertEqual(state.diagnosticCode.rawValue, "ST-SYS-001")
        XCTAssertEqual(state.recoveryActions, [.continueAnyway, .dismiss])
        XCTAssertEqual(state.sourceCode, "LOW_POWER_MODE")
        XCTAssertFalse(state.isSilent)
    }

    func testLowBatteryLevelRaisesOneNotice() {
        let states = advisor.advisories(
            for: DeviceConditions(batteryLevel: 0.1)
        )
        XCTAssertEqual(states.map(\.kind), [.lowBattery])
        XCTAssertEqual(states.first?.sourceCode, "BATTERY_LOW")
    }

    func testHealthyBatteryRaisesNothing() {
        XCTAssertTrue(advisor.advisories(for: .healthy).isEmpty)
        XCTAssertTrue(
            advisor.advisories(for: DeviceConditions(batteryLevel: 0.85)).isEmpty
        )
        XCTAssertTrue(
            advisor.advisories(for: DeviceConditions(batteryLevel: nil)).isEmpty
        )
    }

    func testBatteryLevelIsClampedAndNonFiniteValuesAreIgnored() {
        XCTAssertEqual(DeviceConditions(batteryLevel: -3).batteryLevel, 0)
        XCTAssertEqual(DeviceConditions(batteryLevel: 4).batteryLevel, 1)
        XCTAssertNil(DeviceConditions(batteryLevel: .nan).batteryLevel)
        XCTAssertNil(DeviceConditions(batteryLevel: .infinity).batteryLevel)
        XCTAssertEqual(DeviceConditions(batteryLevel: 0.5).batteryLevel, 0.5)
    }

    func testThermalPressureIsAdvisory() {
        for pressure in [ThermalPressure.serious, .critical] {
            let states = advisor.advisories(
                for: DeviceConditions(batteryLevel: 1, thermalState: pressure)
            )
            XCTAssertEqual(states.map(\.kind), [.thermalPressure])
            XCTAssertEqual(states.first?.severity, .notice)
            XCTAssertEqual(
                states.first?.recoveryActions,
                [.continueAnyway, .dismiss]
            )
            XCTAssertEqual(states.first?.diagnosticCode.rawValue, "ST-SYS-002")
            XCTAssertEqual(
                states.first?.sourceCode,
                "THERMAL_\(pressure == .serious ? "SERIOUS" : "CRITICAL")"
            )
        }

        for pressure in [ThermalPressure.nominal, .fair] {
            XCTAssertTrue(
                advisor.advisories(
                    for: DeviceConditions(batteryLevel: 1, thermalState: pressure)
                ).isEmpty
            )
        }
    }

    func testAdvisoriesHaveStableOrderAndNoDuplicates() {
        let conditions = DeviceConditions(
            isLowPowerModeEnabled: true,
            batteryLevel: 0.1,
            thermalState: .critical,
            availableDiskBytes: 1_000
        )
        let states = advisor.advisories(for: conditions)
        XCTAssertEqual(
            states.map(\.kind),
            [.lowBattery, .thermalPressure, .storageLow]
        )
        XCTAssertEqual(Set(states.map(\.diagnosticCode.rawValue)).count, 3)
        XCTAssertTrue(states.allSatisfy { $0.severity == .notice })
        XCTAssertTrue(states.allSatisfy { !$0.isSilent })
    }

    func testLowBatteryDoesNotBlockCoreCapabilities() {
        let state = ErrorState(kind: .lowBattery)
        XCTAssertEqual(state.severity, .notice)
        XCTAssertFalse(state.recoveryActions.contains(.retry))
        XCTAssertTrue(state.recoveryActions.contains(.continueAnyway))
        XCTAssertEqual(
            OfflineCapability.availability(of: .editing, isOffline: true),
            .available
        )
        XCTAssertEqual(
            OfflineCapability.availability(of: .fullRendering, isOffline: true),
            .available
        )
    }

    func testAdvisorThresholdsAreClamped() {
        let clamped = ErrorAdvisor(
            lowBatteryThreshold: 2,
            lowStorageThresholdBytes: -1
        )
        XCTAssertEqual(clamped.lowBatteryThreshold, 1)
        XCTAssertEqual(clamped.lowStorageThresholdBytes, 0)

        let negative = ErrorAdvisor(lowBatteryThreshold: -1)
        XCTAssertEqual(negative.lowBatteryThreshold, 0)
    }

    func testPassiveOfflineIsNotPartOfTheAdvisoryList() {
        let states = advisor.advisories(
            for: DeviceConditions(isOffline: true, batteryLevel: 1)
        )
        XCTAssertTrue(states.isEmpty)
        XCTAssertFalse(states.contains(where: { $0.kind == .offline }))
    }
}
