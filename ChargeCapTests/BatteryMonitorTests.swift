import IOKit.ps
import XCTest
@testable import ChargeCap

final class BatteryMonitorTests: XCTestCase {

    // MARK: - Power source parsing

    func testParsePowerSourceDescription_parsesInternalBatteryValues() {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 78,
            kIOPSIsChargingKey: true,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSTimeToFullChargeKey: 42,
            kIOPSTimeToEmptyKey: -1,
            kIOPSBatteryHealthConditionKey: "Normal",
        ]

        let snapshot = BatteryMonitor.parsePowerSourceDescription(description)

        XCTAssertEqual(snapshot?.chargePercent, 78)
        XCTAssertEqual(snapshot?.isCharging, true)
        XCTAssertEqual(snapshot?.isPluggedIn, true)
        XCTAssertEqual(snapshot?.timeToFull, 42)
        XCTAssertEqual(snapshot?.timeToEmpty, 0)
        XCTAssertEqual(snapshot?.condition, .normal)
    }

    func testParsePowerSourceDescription_clampsPercentageToBounds() {
        let highDescription: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 130,
        ]
        let lowDescription: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: -8,
        ]

        XCTAssertEqual(BatteryMonitor.parsePowerSourceDescription(highDescription)?.chargePercent, 100)
        XCTAssertEqual(BatteryMonitor.parsePowerSourceDescription(lowDescription)?.chargePercent, 0)
    }

    func testParsePowerSourceDescription_missingValuesFallsBackGracefully() {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
        ]

        let snapshot = BatteryMonitor.parsePowerSourceDescription(description)

        XCTAssertEqual(snapshot?.chargePercent, 0)
        XCTAssertEqual(snapshot?.isCharging, false)
        XCTAssertEqual(snapshot?.isPluggedIn, false)
        XCTAssertEqual(snapshot?.timeToFull, 0)
        XCTAssertEqual(snapshot?.timeToEmpty, 0)
        XCTAssertEqual(snapshot?.condition, .unknown)
    }

    func testParsePowerSourceDescription_nonBatteryReturnsNil() {
        let description: [String: Any] = [
            kIOPSTypeKey: "UPS Power",
            kIOPSCurrentCapacityKey: 80,
        ]

        XCTAssertNil(BatteryMonitor.parsePowerSourceDescription(description))
    }

    // MARK: - Registry parsing

    func testParseRegistryProperties_parsesCycleCountAndHealth() {
        let properties: [String: Any] = [
            "CycleCount": 312,
            "DesignCapacity": 5000,
            "AppleRawMaxCapacity": 4500,
            "Temperature": 2984,
            "AdapterDetails": ["Watts": 67],
        ]

        let snapshot = BatteryMonitor.parseRegistryProperties(properties)

        XCTAssertEqual(snapshot.cycleCount, 312)
        XCTAssertEqual(snapshot.designCapacity, 5000)
        XCTAssertEqual(snapshot.maxCapacity, 4500)
        XCTAssertEqual(snapshot.healthPercent, 90)
        XCTAssertEqual(snapshot.temperature, 25.25, accuracy: 0.01)
        XCTAssertEqual(snapshot.adapterWattage, 67)
    }

    func testMakeBatteryState_combinesParsedSnapshots() {
        let powerSource = BatteryMonitor.PowerSourceSnapshot(
            chargePercent: 80,
            isCharging: false,
            isPluggedIn: true,
            timeToFull: 0,
            timeToEmpty: 120,
            condition: .serviceRecommended
        )
        let registry = BatteryMonitor.RegistrySnapshot(
            cycleCount: 100,
            designCapacity: 5000,
            maxCapacity: 4500,
            temperature: 31.5,
            healthPercent: 90,
            adapterWattage: 96
        )

        let state = BatteryMonitor.makeBatteryState(
            powerSource: powerSource,
            registry: registry,
            maxCycleCount: 1000
        )

        XCTAssertEqual(state.chargePercent, 80)
        XCTAssertFalse(state.isCharging)
        XCTAssertTrue(state.isPluggedIn)
        XCTAssertEqual(state.healthPercent, 90)
        XCTAssertEqual(state.cycleCount, 100)
        XCTAssertEqual(state.condition, .serviceRecommended)
        XCTAssertEqual(state.temperature, 31.5)
        XCTAssertEqual(state.adapterWattage, 96)
        XCTAssertTrue(state.hasBattery)
    }

    // MARK: - firstPositiveIntValueForKeys

    func testFirstPositiveIntValue_findsIntegerValue() {
        let dict: [String: Any] = ["CycleCount": 312]
        let result = BatteryMonitor.firstPositiveIntValueForKeys(in: dict, keys: ["CycleCount"])
        XCTAssertEqual(result, 312)
    }

    func testFirstPositiveIntValue_findsNSNumberValue() {
        let dict: [String: Any] = ["CycleCount": NSNumber(value: 450)]
        let result = BatteryMonitor.firstPositiveIntValueForKeys(in: dict, keys: ["CycleCount"])
        XCTAssertEqual(result, 450)
    }

    func testFirstPositiveIntValue_returnsNilForMissingKey() {
        let dict: [String: Any] = ["OtherKey": 100]
        let result = BatteryMonitor.firstPositiveIntValueForKeys(in: dict, keys: ["CycleCount"])
        XCTAssertNil(result)
    }

    func testFirstPositiveIntValue_returnsNilForZeroValue() {
        let dict: [String: Any] = ["CycleCount": 0]
        let result = BatteryMonitor.firstPositiveIntValueForKeys(in: dict, keys: ["CycleCount"])
        XCTAssertNil(result)
    }

    func testFirstPositiveIntValue_returnsNilForNegativeValue() {
        let dict: [String: Any] = ["CycleCount": -5]
        let result = BatteryMonitor.firstPositiveIntValueForKeys(in: dict, keys: ["CycleCount"])
        XCTAssertNil(result)
    }

    func testFirstPositiveIntValue_returnsNilForEmptyDict() {
        let dict: [String: Any] = [:]
        let result = BatteryMonitor.firstPositiveIntValueForKeys(in: dict, keys: ["CycleCount"])
        XCTAssertNil(result)
    }

    func testFirstPositiveIntValue_returnsFirstMatchingKey() {
        let dict: [String: Any] = ["Key1": 0, "Key2": 42, "Key3": 99]
        let result = BatteryMonitor.firstPositiveIntValueForKeys(in: dict, keys: ["Key1", "Key2", "Key3"])
        XCTAssertEqual(result, 42)
    }

    func testFirstPositiveIntValue_returnsNilForStringValue() {
        let dict: [String: Any] = ["CycleCount": "not a number"]
        let result = BatteryMonitor.firstPositiveIntValueForKeys(in: dict, keys: ["CycleCount"])
        XCTAssertNil(result)
    }

    // MARK: - Cycle count parsing

    func testCycleCountParsedCorrectly() {
        let dict: [String: Any] = ["CycleCount": 312]
        let result = BatteryMonitor.firstPositiveIntValueForKeys(in: dict, keys: ["CycleCount"])
        XCTAssertEqual(result, 312)
    }

    func testCycleCountZero_returnsNil() {
        let dict: [String: Any] = ["CycleCount": 0]
        let result = BatteryMonitor.firstPositiveIntValueForKeys(in: dict, keys: ["CycleCount"])
        XCTAssertNil(result)
    }

    func testCycleCount_largeValue() {
        let dict: [String: Any] = ["CycleCount": 999]
        let result = BatteryMonitor.firstPositiveIntValueForKeys(in: dict, keys: ["CycleCount"])
        XCTAssertEqual(result, 999)
    }

    // MARK: - resolveHealthPercent

    func testResolveHealthPercent_usesMaximumCapacityPercent() {
        let dict: [String: Any] = ["MaximumCapacityPercent": 94]
        let result = BatteryMonitor.resolveHealthPercent(in: dict, designCapacity: 5103, maxCapacity: 4797)
        XCTAssertEqual(result, 94)
    }

    func testResolveHealthPercent_clampedTo100() {
        let dict: [String: Any] = ["MaximumCapacityPercent": 105]
        let result = BatteryMonitor.resolveHealthPercent(in: dict, designCapacity: 5103, maxCapacity: 5103)
        XCTAssertEqual(result, 100)
    }

    func testResolveHealthPercent_fallsBackToMaxCapacityAsPercentage() {
        // MaximumCapacityPercent not present, MaxCapacity is percentage-like (1-100)
        let dict: [String: Any] = ["MaxCapacity": 88]
        let result = BatteryMonitor.resolveHealthPercent(in: dict, designCapacity: 5103, maxCapacity: 4490)
        XCTAssertEqual(result, 88)
    }

    func testResolveHealthPercent_calculatesFromCapacities() {
        // Neither percentage key present
        let dict: [String: Any] = [:]
        let result = BatteryMonitor.resolveHealthPercent(in: dict, designCapacity: 5000, maxCapacity: 4500)
        XCTAssertEqual(result, 90) // 4500 / 5000 * 100 = 90
    }

    func testResolveHealthPercent_returns100WhenDesignCapacityZero() {
        let dict: [String: Any] = [:]
        let result = BatteryMonitor.resolveHealthPercent(in: dict, designCapacity: 0, maxCapacity: 0)
        XCTAssertEqual(result, 100)
    }

    func testResolveHealthPercent_returns100WhenMaxCapacityZero() {
        let dict: [String: Any] = [:]
        let result = BatteryMonitor.resolveHealthPercent(in: dict, designCapacity: 5000, maxCapacity: 0)
        XCTAssertEqual(result, 100)
    }

    func testResolveHealthPercent_clampsCalculatedTo100() {
        // maxCapacity > designCapacity → caps at 100
        let dict: [String: Any] = [:]
        let result = BatteryMonitor.resolveHealthPercent(in: dict, designCapacity: 4000, maxCapacity: 5000)
        XCTAssertEqual(result, 100)
    }

    // MARK: - resolveMaxCapacity

    func testResolveMaxCapacity_prefersAppleRawMaxCapacity() {
        let dict: [String: Any] = [
            "AppleRawMaxCapacity": 4797,
            "MaxCapacity": 4800,
            "NominalChargeCapacity": 4790,
        ]
        let result = BatteryMonitor.resolveMaxCapacity(in: dict, designCapacity: 5103)
        XCTAssertEqual(result, 4797)
    }

    func testResolveMaxCapacity_usesMaxCapacityWhenAbsolute() {
        let dict: [String: Any] = ["MaxCapacity": 4800]
        let result = BatteryMonitor.resolveMaxCapacity(in: dict, designCapacity: 5103)
        XCTAssertEqual(result, 4800)
    }

    func testResolveMaxCapacity_fallsBackToPercentageWithDesignCapacity() {
        // MaxCapacity = 94 (percentage-like, 1-100 range), filtered out as mAh
        // MaximumCapacityPercent provides the fallback
        let dict: [String: Any] = [
            "MaxCapacity": 94,
            "MaximumCapacityPercent": 94,
        ]
        let result = BatteryMonitor.resolveMaxCapacity(in: dict, designCapacity: 5000)
        XCTAssertEqual(result, Int((5000.0 * 94.0 / 100.0).rounded()))
    }

    func testResolveMaxCapacity_returnsZeroForEmptyDict() {
        let dict: [String: Any] = [:]
        let result = BatteryMonitor.resolveMaxCapacity(in: dict, designCapacity: 5103)
        XCTAssertEqual(result, 0)
    }

    func testResolveMaxCapacity_filtersOutUnreasonablyHighValues() {
        // Value is more than 2x design capacity
        let dict: [String: Any] = ["AppleRawMaxCapacity": 20000]
        let result = BatteryMonitor.resolveMaxCapacity(in: dict, designCapacity: 5000)
        XCTAssertEqual(result, 0)
    }

    func testResolveMaxCapacity_acceptsValueWhenDesignCapacityZero() {
        let dict: [String: Any] = ["AppleRawMaxCapacity": 4800]
        let result = BatteryMonitor.resolveMaxCapacity(in: dict, designCapacity: 0)
        XCTAssertEqual(result, 4800)
    }

    func testResolveMaxCapacity_usesNominalChargeCapacity() {
        let dict: [String: Any] = ["NominalChargeCapacity": 4500]
        let result = BatteryMonitor.resolveMaxCapacity(in: dict, designCapacity: 5000)
        XCTAssertEqual(result, 4500)
    }

    // MARK: - isPercentageValue

    func testIsPercentageValue_trueForValidPercentages() {
        XCTAssertTrue(BatteryMonitor.isPercentageValue(1))
        XCTAssertTrue(BatteryMonitor.isPercentageValue(50))
        XCTAssertTrue(BatteryMonitor.isPercentageValue(100))
    }

    func testIsPercentageValue_falseForOutOfRange() {
        XCTAssertFalse(BatteryMonitor.isPercentageValue(0))
        XCTAssertFalse(BatteryMonitor.isPercentageValue(101))
        XCTAssertFalse(BatteryMonitor.isPercentageValue(4800))
        XCTAssertFalse(BatteryMonitor.isPercentageValue(-1))
    }

    // MARK: - BatteryMonitor updateChargeMetadata

    func testUpdateChargeMetadata_updatesState() {
        let monitor = BatteryMonitor(startMonitoring: false)
        monitor.updateChargeMetadata(limit: 80, isChargeInhibited: true)

        XCTAssertEqual(monitor.activeChargeLimit, 80)
        XCTAssertTrue(monitor.isChargeInhibited)
        XCTAssertEqual(monitor.batteryState.chargeLimit, 80)
        XCTAssertTrue(monitor.batteryState.isChargeInhibited)
    }

    func testUpdateChargeMetadata_clearsLimit() {
        let monitor = BatteryMonitor(startMonitoring: false)
        monitor.updateChargeMetadata(limit: 80, isChargeInhibited: true)
        monitor.updateChargeMetadata(limit: nil, isChargeInhibited: false)

        XCTAssertNil(monitor.activeChargeLimit)
        XCTAssertFalse(monitor.isChargeInhibited)
    }

    // MARK: - BatteryMonitor updateSMCReadings

    func testUpdateSMCReadings_updatesBatteryRateAndTemperature() {
        let monitor = BatteryMonitor(startMonitoring: false)
        monitor.updateSMCReadings(batteryRate: 5000, temperature: 35.5)

        XCTAssertEqual(monitor.smcBatteryRate, 5000)
        XCTAssertEqual(monitor.smcBatteryTemperature, 35.5)
        XCTAssertEqual(monitor.batteryState.batteryRate, 5000)
        XCTAssertEqual(monitor.batteryState.temperature, 35.5)
    }

    func testUpdateSMCReadings_nilTemperatureKeepsExisting() {
        let monitor = BatteryMonitor(startMonitoring: false)
        let originalTemp = monitor.batteryState.temperature
        monitor.updateSMCReadings(batteryRate: nil, temperature: nil)

        // Temperature should not be overwritten with nil
        XCTAssertEqual(monitor.batteryState.temperature, originalTemp)
    }

    func testUpdateSMCReadings_nilBatteryRate() {
        let monitor = BatteryMonitor(startMonitoring: false)
        monitor.updateSMCReadings(batteryRate: 5000, temperature: nil)
        monitor.updateSMCReadings(batteryRate: nil, temperature: nil)

        XCTAssertNil(monitor.smcBatteryRate)
    }
}
