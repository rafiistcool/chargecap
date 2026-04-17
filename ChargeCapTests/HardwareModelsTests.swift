import XCTest
@testable import ChargeCap

final class HardwareModelsTests: XCTestCase {

    // MARK: - SensorReading Temperature Color Coding (<50 green, 50-80 yellow, >80 red)

    func testTemperatureColor_belowFifty_isNormal() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 30.0, unit: .celsius)
        XCTAssertEqual(reading.temperatureColor, .normal)
    }

    func testTemperatureColor_justBelowFifty_isNormal() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 49.9, unit: .celsius)
        XCTAssertEqual(reading.temperatureColor, .normal)
    }

    func testTemperatureColor_atFifty_isWarm() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 50.0, unit: .celsius)
        XCTAssertEqual(reading.temperatureColor, .warm)
    }

    func testTemperatureColor_seventyNine_isWarm() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 79.9, unit: .celsius)
        XCTAssertEqual(reading.temperatureColor, .warm)
    }

    func testTemperatureColor_atEighty_isHot() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 80.0, unit: .celsius)
        XCTAssertEqual(reading.temperatureColor, .hot)
    }

    func testTemperatureColor_aboveEighty_isHot() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 95.0, unit: .celsius)
        XCTAssertEqual(reading.temperatureColor, .hot)
    }

    func testTemperatureColor_nonCelsiusUnit_isAlwaysNormal() {
        let wattReading = SensorReading(key: "PSTR", name: "Power", value: 90.0, unit: .watts)
        XCTAssertEqual(wattReading.temperatureColor, .normal)

        let rpmReading = SensorReading(key: "F0Ac", name: "Fan", value: 5000.0, unit: .rpm)
        XCTAssertEqual(rpmReading.temperatureColor, .normal)
    }

    func testTemperatureColor_zeroTemp_isNormal() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 0.0, unit: .celsius)
        XCTAssertEqual(reading.temperatureColor, .normal)
    }

    // MARK: - SensorReading Formatted Value

    func testFormattedValue_celsius() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 45.3, unit: .celsius)
        XCTAssertEqual(reading.formattedValue, "45.3\u{00B0}C")
    }

    func testFormattedValue_watts() {
        let reading = SensorReading(key: "PSTR", name: "Power", value: 12.5, unit: .watts)
        XCTAssertEqual(reading.formattedValue, "12.5W")
    }

    func testFormattedValue_rpm() {
        let reading = SensorReading(key: "F0Ac", name: "Fan", value: 3456.0, unit: .rpm)
        XCTAssertEqual(reading.formattedValue, "3456 RPM")
    }

    // MARK: - SensorReading Correct Units

    func testSensorReading_celsiusUnit() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 45.0, unit: .celsius)
        XCTAssertEqual(reading.unit, .celsius)
    }

    func testSensorReading_wattsUnit() {
        let reading = SensorReading(key: "PSTR", name: "Power", value: 10.0, unit: .watts)
        XCTAssertEqual(reading.unit, .watts)
    }

    func testSensorReading_rpmUnit() {
        let reading = SensorReading(key: "F0Ac", name: "Fan", value: 3000.0, unit: .rpm)
        XCTAssertEqual(reading.unit, .rpm)
    }

    // MARK: - SensorReading Identity

    func testSensorReading_identityIsKey() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 45.0, unit: .celsius)
        XCTAssertEqual(reading.id, "TC0C")
    }

    // MARK: - SensorCategory

    func testSensorReading_defaultCategoryIsOther() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 45.0, unit: .celsius)
        XCTAssertEqual(reading.category, .other)
    }

    func testSensorReading_explicitCategory() {
        let reading = SensorReading(
            key: "Tp01",
            name: "Performance Core 1",
            value: 55.0,
            unit: .celsius,
            category: .performanceCores
        )
        XCTAssertEqual(reading.category, .performanceCores)
    }

    func testSensorCategory_sortOrderIsStable() {
        let sorted = SensorCategory.allCases.sorted { $0.sortOrder < $1.sortOrder }
        // Cores should come before GPU, which should come before battery, etc.
        let efficiencyIdx = sorted.firstIndex(of: .efficiencyCores)!
        let performanceIdx = sorted.firstIndex(of: .performanceCores)!
        let gpuIdx = sorted.firstIndex(of: .gpu)!
        let batteryIdx = sorted.firstIndex(of: .battery)!
        XCTAssertLessThan(efficiencyIdx, performanceIdx)
        XCTAssertLessThan(performanceIdx, gpuIdx)
        XCTAssertLessThan(gpuIdx, batteryIdx)
    }

    func testSensorCategory_sortOrdersAreUnique() {
        let orders = SensorCategory.allCases.map(\.sortOrder)
        XCTAssertEqual(orders.count, Set(orders).count, "Every SensorCategory must have a unique sortOrder")
    }

    func testSensorCategory_displayNamesMatchRawValues() {
        XCTAssertEqual(SensorCategory.performanceCores.rawValue, "Performance Cores")
        XCTAssertEqual(SensorCategory.efficiencyCores.rawValue, "Efficiency Cores")
        XCTAssertEqual(SensorCategory.battery.rawValue, "Battery")
    }

    // MARK: - CPU Temperature (SMC sensor key)

    func testCPUTemperature_sensorReading() {
        let reading = SensorReading(key: "TC0C", name: "CPU Die", value: 65.2, unit: .celsius)
        XCTAssertEqual(reading.value, 65.2, accuracy: 0.01)
        XCTAssertEqual(reading.unit, .celsius)
    }

    // MARK: - GPU Temperature

    func testGPUTemperature_sensorReading() {
        let reading = SensorReading(key: "GC0C", name: "GPU", value: 58.7, unit: .celsius)
        XCTAssertEqual(reading.value, 58.7, accuracy: 0.01)
        XCTAssertEqual(reading.unit, .celsius)
    }

    // MARK: - Missing Sensor (nil handling)

    func testMissingSensor_emptySensorArray() {
        let sensors: [SensorReading] = []
        let cpuTemp = sensors.first(where: { $0.key == "TC0C" })
        XCTAssertNil(cpuTemp, "Missing sensor should return nil")
    }

    func testMissingSensor_keyNotFound() {
        let sensors = [
            SensorReading(key: "TB0T", name: "Battery", value: 30.0, unit: .celsius)
        ]
        let cpuTemp = sensors.first(where: { $0.key == "TC0C" })
        XCTAssertNil(cpuTemp)
    }

    // MARK: - FanInfo

    func testFanInfo_properties() {
        let fan = FanInfo(index: 0, rpm: 3456, minRPM: 1200, maxRPM: 6200)
        XCTAssertEqual(fan.id, 0)
        XCTAssertEqual(fan.rpm, 3456)
        XCTAssertEqual(fan.minRPM, 1200)
        XCTAssertEqual(fan.maxRPM, 6200)
    }

    func testFanInfo_rpmFormatted() {
        let fan = FanInfo(index: 0, rpm: 3456, minRPM: 1200, maxRPM: 6200)
        XCTAssertFalse(fan.rpmFormatted.isEmpty)
    }

    func testFanInfo_multipleFansDetected() {
        let fans = [
            FanInfo(index: 0, rpm: 2100, minRPM: 1200, maxRPM: 5900),
            FanInfo(index: 1, rpm: 2200, minRPM: 1200, maxRPM: 5900),
        ]
        XCTAssertEqual(fans.count, 2)
        XCTAssertEqual(fans[0].index, 0)
        XCTAssertEqual(fans[1].index, 1)
    }

    func testFanInfo_zeroFans_macBookAir() {
        let fans: [FanInfo] = []
        XCTAssertTrue(fans.isEmpty)
    }

    func testFanInfo_zeroRPM() {
        let fan = FanInfo(index: 0, rpm: 0, minRPM: 0, maxRPM: 0)
        XCTAssertEqual(fan.rpm, 0)
    }

    // MARK: - Fan Speed Clamped (Float.safeInt)

    func testSafeInt_normalValue() {
        let value: Float = 3456.7
        XCTAssertEqual(value.safeInt(), 3457)
    }

    func testSafeInt_zeroValue() {
        let value: Float = 0.0
        XCTAssertEqual(value.safeInt(), 0)
    }

    func testSafeInt_nanValue_returnsFallback() {
        let value: Float = .nan
        XCTAssertEqual(value.safeInt(), 0)
    }

    func testSafeInt_infinityValue_returnsFallback() {
        let value: Float = .infinity
        XCTAssertEqual(value.safeInt(), 0)
    }

    func testSafeInt_negativeInfinityValue_returnsFallback() {
        let value: Float = -.infinity
        XCTAssertEqual(value.safeInt(), 0)
    }

    func testSafeInt_clampedToDefaultMax() {
        let value: Float = 200_000.0
        XCTAssertEqual(value.safeInt(), 100_000)
    }

    func testSafeInt_customRange() {
        let value: Float = 150.0
        XCTAssertEqual(value.safeInt(clampedTo: 0...100), 100)
    }

    func testSafeInt_negativeClampedToZero() {
        let value: Float = -50.0
        XCTAssertEqual(value.safeInt(), 0)
    }

    func testSafeInt_customFallback() {
        let value: Float = .nan
        XCTAssertEqual(value.safeInt(fallback: -1), -1)
    }

    // MARK: - MemoryUsage

    func testMemoryUsage_calculationsCorrect() {
        let oneGB: UInt64 = 1024 * 1024 * 1024
        let memory = MemoryUsage(used: 8 * oneGB, total: 16 * oneGB, swapUsed: oneGB, pressure: .nominal)

        XCTAssertEqual(memory.usedGB, 8.0, accuracy: 0.01)
        XCTAssertEqual(memory.totalGB, 16.0, accuracy: 0.01)
        XCTAssertEqual(memory.swapUsedGB, 1.0, accuracy: 0.01)
        XCTAssertEqual(memory.usagePercent, 50.0, accuracy: 0.01)
    }

    func testMemoryUsage_zeroTotal_usagePercentIsZero() {
        let memory = MemoryUsage(used: 0, total: 0, swapUsed: 0, pressure: .nominal)
        XCTAssertEqual(memory.usagePercent, 0)
    }

    func testMemoryUsage_zero() {
        let memory = MemoryUsage.zero
        XCTAssertEqual(memory.used, 0)
        XCTAssertEqual(memory.total, 0)
        XCTAssertEqual(memory.swapUsed, 0)
        XCTAssertEqual(memory.pressure, .nominal)
    }

    func testMemoryUsage_pressureLevels() {
        XCTAssertEqual(MemoryPressure.nominal.rawValue, "Normal")
        XCTAssertEqual(MemoryPressure.warning.rawValue, "Warning")
        XCTAssertEqual(MemoryPressure.critical.rawValue, "Critical")
    }

    func testMemoryUsage_highUsage() {
        let oneGB: UInt64 = 1024 * 1024 * 1024
        let memory = MemoryUsage(used: 15 * oneGB, total: 16 * oneGB, swapUsed: 2 * oneGB, pressure: .warning)
        XCTAssertEqual(memory.usagePercent, 93.75, accuracy: 0.01)
        XCTAssertEqual(memory.pressure, .warning)
    }

    // MARK: - Apple Silicon Sensor Keys

    func testTemperatureKeys_containsCPUDie() {
        let keys = HardwareMonitor.temperatureKeys
        XCTAssertTrue(keys.contains(where: { $0.key == "TC0C" && $0.name == "CPU Die" }))
    }

    func testTemperatureKeys_containsCPUProximity() {
        let keys = HardwareMonitor.temperatureKeys
        XCTAssertTrue(keys.contains(where: { $0.key == "TC0P" && $0.name == "CPU Proximity" }))
    }

    func testTemperatureKeys_containsGPU() {
        let keys = HardwareMonitor.temperatureKeys
        XCTAssertTrue(keys.contains(where: { $0.key == "GC0C" && $0.name == "GPU" }))
    }

    func testTemperatureKeys_containsBattery() {
        let keys = HardwareMonitor.temperatureKeys
        XCTAssertTrue(keys.contains(where: { $0.key == "TB0T" && $0.name == "Battery" }))
    }

    func testTemperatureKeys_allAppleSiliconKeysPresent() {
        let keys = HardwareMonitor.temperatureKeys
        let keyNames = keys.map { $0.key }

        XCTAssertTrue(keyNames.contains("TC0C"), "Should include CPU Die temperature key")
        XCTAssertTrue(keyNames.contains("TC0P"), "Should include CPU Proximity key")
        XCTAssertTrue(keyNames.contains("GC0C"), "Should include GPU temperature key")
        XCTAssertTrue(keyNames.contains("TB0T"), "Should include Battery temperature key")
        XCTAssertTrue(keyNames.contains("Ts0P"), "Should include Palm Rest temperature key")
        XCTAssertTrue(keyNames.contains("TM0P"), "Should include Memory temperature key")
        XCTAssertTrue(keyNames.contains("TN0D"), "Should include NVMe/SSD temperature key")
    }
}
