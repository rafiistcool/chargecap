import XCTest
@testable import ChargeCap

final class BatteryStateTests: XCTestCase {

    // MARK: - BatteryCondition init from IOKit string

    func testBatteryCondition_normal() {
        XCTAssertEqual(BatteryCondition(ioKitString: "Normal"), .normal)
    }

    func testBatteryCondition_serviceRecommended() {
        XCTAssertEqual(BatteryCondition(ioKitString: "Service Recommended"), .serviceRecommended)
    }

    func testBatteryCondition_replaceSoon() {
        XCTAssertEqual(BatteryCondition(ioKitString: "Replace Soon"), .replaceSoon)
    }

    func testBatteryCondition_replaceNow() {
        XCTAssertEqual(BatteryCondition(ioKitString: "Replace Now"), .replaceNow)
    }

    func testBatteryCondition_poor() {
        XCTAssertEqual(BatteryCondition(ioKitString: "Poor"), .poor)
    }

    func testBatteryCondition_nil_returnsUnknown() {
        XCTAssertEqual(BatteryCondition(ioKitString: nil), .unknown)
    }

    func testBatteryCondition_unknownString_returnsUnknown() {
        XCTAssertEqual(BatteryCondition(ioKitString: "Something Else"), .unknown)
    }

    func testBatteryCondition_emptyString_returnsUnknown() {
        XCTAssertEqual(BatteryCondition(ioKitString: ""), .unknown)
    }

    // MARK: - Battery icon name

    func testBatteryIconName_charging() {
        var state = BatteryState.placeholder
        state.isCharging = true
        XCTAssertEqual(state.batteryIconName, "battery.100.bolt")
    }

    func testBatteryIconName_noBattery() {
        XCTAssertEqual(BatteryState.noBattery.batteryIconName, "desktopcomputer")
    }

    func testBatteryIconName_100Percent() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.chargePercent = 100
        XCTAssertEqual(state.batteryIconName, "battery.100")
    }

    func testBatteryIconName_76Percent() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.chargePercent = 76
        XCTAssertEqual(state.batteryIconName, "battery.100")
    }

    func testBatteryIconName_75Percent() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.chargePercent = 75
        XCTAssertEqual(state.batteryIconName, "battery.75")
    }

    func testBatteryIconName_60Percent() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.chargePercent = 60
        XCTAssertEqual(state.batteryIconName, "battery.75")
    }

    func testBatteryIconName_51Percent() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.chargePercent = 51
        XCTAssertEqual(state.batteryIconName, "battery.75")
    }

    func testBatteryIconName_50Percent() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.chargePercent = 50
        XCTAssertEqual(state.batteryIconName, "battery.50")
    }

    func testBatteryIconName_40Percent() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.chargePercent = 40
        XCTAssertEqual(state.batteryIconName, "battery.50")
    }

    func testBatteryIconName_25Percent() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.chargePercent = 25
        XCTAssertEqual(state.batteryIconName, "battery.25")
    }

    func testBatteryIconName_15Percent() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.chargePercent = 15
        XCTAssertEqual(state.batteryIconName, "battery.25")
    }

    func testBatteryIconName_0Percent() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.chargePercent = 0
        XCTAssertEqual(state.batteryIconName, "battery.0")
    }

    // MARK: - Placeholder and noBattery static instances

    func testPlaceholder_hasBattery() {
        XCTAssertTrue(BatteryState.placeholder.hasBattery)
    }

    func testPlaceholder_isCharging() {
        XCTAssertTrue(BatteryState.placeholder.isCharging)
    }

    func testPlaceholder_isPluggedIn() {
        XCTAssertTrue(BatteryState.placeholder.isPluggedIn)
    }

    func testNoBattery_hasNoBattery() {
        XCTAssertFalse(BatteryState.noBattery.hasBattery)
    }

    func testNoBattery_values() {
        let state = BatteryState.noBattery
        XCTAssertEqual(state.chargePercent, 0)
        XCTAssertFalse(state.isCharging)
        XCTAssertEqual(state.healthPercent, 0)
        XCTAssertEqual(state.cycleCount, 0)
        XCTAssertEqual(state.condition, .unknown)
        XCTAssertEqual(state.maxCycleCount, 0)
        XCTAssertEqual(state.temperature, 0)
        XCTAssertEqual(state.designCapacity, 0)
        XCTAssertEqual(state.maxCapacity, 0)
    }

    func testResolvedBatteryChargingWatts_usesRemainingAdapterPowerWhenTelemetryLooksLikeAdapterInput() throws {
        let state = BatteryState(
            chargePercent: 54,
            isCharging: true,
            isPluggedIn: true,
            chargeLimit: 80,
            batteryRate: nil,
            systemLoadMilliwatts: 38_000,
            batteryPowerMilliwatts: 140_000,
            timeToFull: 50,
            timeToEmpty: 0,
            healthPercent: 97,
            condition: .normal,
            cycleCount: 41,
            maxCycleCount: 1000,
            temperature: 31.0,
            designCapacity: 8579,
            maxCapacity: 8214,
            adapterWattage: 140,
            isChargeInhibited: false,
            hasBattery: true
        )

        XCTAssertEqual(try XCTUnwrap(state.resolvedBatteryChargingWatts), 102.0, accuracy: 0.001)
    }

    func testResolvedBatteryChargingWatts_keepsMeasuredBatteryPowerWhenItFitsWithinAdapterBudget() throws {
        let state = BatteryState(
            chargePercent: 54,
            isCharging: true,
            isPluggedIn: true,
            chargeLimit: 80,
            batteryRate: nil,
            systemLoadMilliwatts: 22_000,
            batteryPowerMilliwatts: 67_000,
            timeToFull: 50,
            timeToEmpty: 0,
            healthPercent: 97,
            condition: .normal,
            cycleCount: 41,
            maxCycleCount: 1000,
            temperature: 31.0,
            designCapacity: 8579,
            maxCapacity: 8214,
            adapterWattage: 140,
            isChargeInhibited: false,
            hasBattery: true
        )

        XCTAssertEqual(try XCTUnwrap(state.resolvedBatteryChargingWatts), 67.0, accuracy: 0.001)
    }

    // MARK: - Equatable

    func testBatteryState_equalInstances() {
        let a = BatteryState.placeholder
        let b = BatteryState.placeholder
        XCTAssertEqual(a, b)
    }

    func testBatteryState_unequalInstances() {
        let a = BatteryState.placeholder
        var b = BatteryState.placeholder
        b.chargePercent = 50
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Charging state identification

    func testChargingState_charging() {
        var state = BatteryState.placeholder
        state.isCharging = true
        state.isPluggedIn = true
        XCTAssertTrue(state.isCharging)
        XCTAssertTrue(state.isPluggedIn)
    }

    func testChargingState_pluggedInNotCharging() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.isPluggedIn = true
        XCTAssertFalse(state.isCharging)
        XCTAssertTrue(state.isPluggedIn)
    }

    func testChargingState_onBattery() {
        var state = BatteryState.placeholder
        state.isCharging = false
        state.isPluggedIn = false
        XCTAssertFalse(state.isCharging)
        XCTAssertFalse(state.isPluggedIn)
    }

    // MARK: - BatteryCondition raw values

    func testBatteryCondition_rawValues() {
        XCTAssertEqual(BatteryCondition.normal.rawValue, "Normal")
        XCTAssertEqual(BatteryCondition.serviceRecommended.rawValue, "Service Recommended")
        XCTAssertEqual(BatteryCondition.replaceSoon.rawValue, "Replace Soon")
        XCTAssertEqual(BatteryCondition.replaceNow.rawValue, "Replace Now")
        XCTAssertEqual(BatteryCondition.poor.rawValue, "Poor")
        XCTAssertEqual(BatteryCondition.unknown.rawValue, "Unknown")
    }
}
