import XCTest
@testable import ChargeCap

// MARK: - Mock SMC Reader

@MainActor
final class MockSMCReader: SMCReadable {
    var isInstalled: Bool = true
    var floatValues: [String: Float] = [:]
    var byteValues: [String: UInt8] = [:]
    var temperatureValues: [String: Double] = [:]
    var shouldThrowForKeys: Set<String> = []

    enum MockError: Error {
        case readFailed
    }

    func readSMCFloatValue(key: String) async throws -> Float {
        if shouldThrowForKeys.contains(key) { throw MockError.readFailed }
        return floatValues[key] ?? 0
    }

    func readSMCByteValue(key: String) async throws -> UInt8 {
        if shouldThrowForKeys.contains(key) { throw MockError.readFailed }
        return byteValues[key] ?? 0
    }

    func readSMCTemperatureValue(key: String) async throws -> Double {
        if shouldThrowForKeys.contains(key) { throw MockError.readFailed }
        return temperatureValues[key] ?? 0
    }
}

// MARK: - Tests

@MainActor
final class HardwareMonitorTests: XCTestCase {

    private var mockReader: MockSMCReader!
    private var monitor: HardwareMonitor!

    override func setUp() {
        super.setUp()
        mockReader = MockSMCReader()
        monitor = HardwareMonitor(helperManager: mockReader, startMonitoring: false)
    }

    override func tearDown() {
        monitor = nil
        mockReader = nil
        super.tearDown()
    }

    // MARK: - Float.safeInt

    func testSafeInt_normalValue_convertsCorrectly() {
        XCTAssertEqual(Float(42.4).safeInt(), 42)
        XCTAssertEqual(Float(42.5).safeInt(), 43) // .rounded() uses .toNearestOrAwayFromZero
        XCTAssertEqual(Float(42.6).safeInt(), 43)
        XCTAssertEqual(Float(0).safeInt(), 0)
    }

    func testSafeInt_nan_returnsFallback() {
        XCTAssertEqual(Float.nan.safeInt(), 0)
        XCTAssertEqual(Float.nan.safeInt(fallback: -1), -1)
    }

    func testSafeInt_infinity_returnsFallback() {
        XCTAssertEqual(Float.infinity.safeInt(), 0)
        XCTAssertEqual((-Float.infinity).safeInt(), 0)
    }

    func testSafeInt_veryLargeValue_clampedToUpperBound() {
        XCTAssertEqual(Float(999_999).safeInt(), 100_000)
    }

    func testSafeInt_negativeValue_clampedToLowerBound() {
        XCTAssertEqual(Float(-100).safeInt(), 0)
    }

    func testSafeInt_customRange() {
        XCTAssertEqual(Float(50).safeInt(clampedTo: 0...200), 50)
        XCTAssertEqual(Float(300).safeInt(clampedTo: 0...200), 200)
        XCTAssertEqual(Float(-10).safeInt(clampedTo: -5...100), -5)
    }

    // MARK: - Temperature keys

    func testTemperatureKeys_containsExpectedSensors() {
        let keys = HardwareMonitor.temperatureKeys.map { $0.key }
        XCTAssertTrue(keys.contains("TC0C"))
        XCTAssertTrue(keys.contains("GC0C"))
        XCTAssertTrue(keys.contains("TB0T"))
        // Apple Silicon core / cluster sensors were added alongside the
        // detailed temperatures view; make sure the list keeps covering
        // at least the basic Intel Mac sensors plus key Apple Silicon ones.
        XCTAssertTrue(keys.contains("Tp01"), "Should include first Apple Silicon performance core")
        XCTAssertTrue(keys.contains("Tg05"), "Should include first Apple Silicon GPU cluster")
        XCTAssertGreaterThanOrEqual(HardwareMonitor.temperatureKeys.count, 30)
    }

    // MARK: - Refresh with helper not installed

    func testRefresh_helperNotInstalled_zerosSMCData() async {
        mockReader.isInstalled = false
        await monitor.refresh()

        XCTAssertEqual(monitor.cpuTemperature, 0.0)
        XCTAssertEqual(monitor.gpuTemperature, 0.0)
        XCTAssertTrue(monitor.fans.isEmpty)
        XCTAssertTrue(monitor.sensors.isEmpty)
    }

    func testRefresh_helperNotInstalled_stillReadsCPUAndMemory() async {
        mockReader.isInstalled = false
        await monitor.refresh()

        // CPU usage and memory are read from the kernel, not SMC
        // After a fresh init (first call), CPU usage returns 0 because there's no previous baseline
        XCTAssertEqual(monitor.cpuUsage, 0.0)
        XCTAssertTrue(monitor.memory.total > 0, "Should read real physical memory")
    }

    // MARK: - Refresh with helper installed

    func testRefresh_helperInstalled_readsTemperatures() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = [
            "TC0C": 55.5,
            "GC0C": 48.2,
            "TB0T": 32.0,
        ]

        await monitor.refresh()

        XCTAssertEqual(monitor.cpuTemperature, 55.5)
        XCTAssertEqual(monitor.gpuTemperature, 48.2)
        XCTAssertFalse(monitor.sensors.isEmpty)
    }

    func testRefresh_cpuTempFromTC0P_whenTC0CNotAvailable() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = [
            "TC0P": 60.0,
        ]

        await monitor.refresh()

        XCTAssertEqual(monitor.cpuTemperature, 60.0)
    }

    func testRefresh_noGPUTemp_defaultsToZero() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = [
            "TC0C": 50.0,
        ]

        await monitor.refresh()

        XCTAssertEqual(monitor.gpuTemperature, 0.0)
    }

    // MARK: - Read temperatures

    func testReadTemperatures_filtersInvalidValues() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = [
            "TC0C": 0,       // filtered (== 0)
            "TC0P": -50,     // filtered (< -40)
            "GC0C": 200,     // filtered (>= 150)
            "TB0T": 35.0,    // valid
        ]

        let readings = await monitor.readTemperatures()

        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings[0].key, "TB0T")
        XCTAssertEqual(readings[0].value, 35.0)
        XCTAssertEqual(readings[0].unit, .celsius)
    }

    func testReadTemperatures_sortsByDefinedOrder() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = [
            "TB0T": 33.0,    // index 3
            "TC0C": 55.0,    // index 0
            "GC0C": 45.0,    // index 2
        ]

        let readings = await monitor.readTemperatures()

        XCTAssertEqual(readings.count, 3)
        XCTAssertEqual(readings[0].key, "TC0C")
        XCTAssertEqual(readings[1].key, "GC0C")
        XCTAssertEqual(readings[2].key, "TB0T")
    }

    func testReadTemperatures_errorForKey_skipped() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = [
            "TC0C": 55.0,
            "GC0C": 45.0,
        ]
        mockReader.shouldThrowForKeys = ["GC0C"]

        let readings = await monitor.readTemperatures()

        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings[0].key, "TC0C")
    }

    func testReadTemperatures_allErrors_returnsEmpty() async {
        mockReader.isInstalled = true
        mockReader.shouldThrowForKeys = Set(HardwareMonitor.temperatureKeys.map { $0.key })

        let readings = await monitor.readTemperatures()

        XCTAssertTrue(readings.isEmpty)
    }

    func testReadTemperatures_setsCorrectName() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = ["TC0C": 50.0]

        let readings = await monitor.readTemperatures()

        XCTAssertEqual(readings.first?.name, "CPU Die")
    }

    func testReadTemperatures_setsCategoryFromKey() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = [
            "Tp01": 50.0, // Performance core
            "Tp09": 45.0, // Efficiency core
            "Tg05": 55.0, // GPU cluster
            "TB0T": 32.0, // Battery
        ]

        let readings = await monitor.readTemperatures()
        let byKey = Dictionary(uniqueKeysWithValues: readings.map { ($0.key, $0) })

        XCTAssertEqual(byKey["Tp01"]?.category, .performanceCores)
        XCTAssertEqual(byKey["Tp09"]?.category, .efficiencyCores)
        XCTAssertEqual(byKey["Tg05"]?.category, .gpu)
        XCTAssertEqual(byKey["TB0T"]?.category, .battery)
    }

    func testReadTemperatures_boundaryValues() async {
        mockReader.isInstalled = true
        // Just above -40 and just below 150 should be valid
        mockReader.temperatureValues = [
            "TC0C": -39.0,
            "GC0C": 149.0,
        ]

        let readings = await monitor.readTemperatures()
        let keys = readings.map { $0.key }
        XCTAssertTrue(keys.contains("TC0C"))
        XCTAssertTrue(keys.contains("GC0C"))
    }

    // MARK: - Read fans

    func testReadFans_zeroFans_returnsEmpty() async {
        mockReader.byteValues = ["FNum": 0]

        let fans = await monitor.readFans()

        XCTAssertTrue(fans.isEmpty)
    }

    func testReadFans_oneFan_returnsData() async {
        mockReader.byteValues = ["FNum": 1]
        mockReader.floatValues = [
            "F0Ac": 2500.0,
            "F0Mn": 1200.0,
            "F0Mx": 6000.0,
        ]

        let fans = await monitor.readFans()

        XCTAssertEqual(fans.count, 1)
        XCTAssertEqual(fans[0].index, 0)
        XCTAssertEqual(fans[0].rpm, 2500)
        XCTAssertEqual(fans[0].minRPM, 1200)
        XCTAssertEqual(fans[0].maxRPM, 6000)
    }

    func testReadFans_multipleFans() async {
        mockReader.byteValues = ["FNum": 2]
        mockReader.floatValues = [
            "F0Ac": 2000.0, "F0Mn": 1000.0, "F0Mx": 5000.0,
            "F1Ac": 3000.0, "F1Mn": 1500.0, "F1Mx": 6000.0,
        ]

        let fans = await monitor.readFans()

        XCTAssertEqual(fans.count, 2)
        XCTAssertEqual(fans[0].rpm, 2000)
        XCTAssertEqual(fans[1].rpm, 3000)
    }

    func testReadFans_fanCountError_returnsEmpty() async {
        mockReader.shouldThrowForKeys = ["FNum"]

        let fans = await monitor.readFans()

        XCTAssertTrue(fans.isEmpty)
    }

    func testReadFans_actualRPMError_skippedFan() async {
        mockReader.byteValues = ["FNum": 1]
        mockReader.shouldThrowForKeys = ["F0Ac"]

        let fans = await monitor.readFans()

        XCTAssertTrue(fans.isEmpty)
    }

    func testReadFans_minMaxMissing_defaultsToZero() async {
        mockReader.byteValues = ["FNum": 1]
        mockReader.floatValues = ["F0Ac": 1800.0]
        // F0Mn and F0Mx not set -> default 0

        let fans = await monitor.readFans()

        XCTAssertEqual(fans.count, 1)
        XCTAssertEqual(fans[0].rpm, 1800)
        XCTAssertEqual(fans[0].minRPM, 0)
        XCTAssertEqual(fans[0].maxRPM, 0)
    }

    func testReadFans_rpmBelowMinimum_clampsUp() async {
        mockReader.byteValues = ["FNum": 1]
        mockReader.floatValues = [
            "F0Ac": 500.0,
            "F0Mn": 1200.0,
            "F0Mx": 6000.0,
        ]

        let fans = await monitor.readFans()

        XCTAssertEqual(fans.count, 1)
        XCTAssertEqual(fans[0].rpm, 1200)
    }

    func testReadFans_rpmAboveMaximum_clampsDown() async {
        mockReader.byteValues = ["FNum": 1]
        mockReader.floatValues = [
            "F0Ac": 6500.0,
            "F0Mn": 1200.0,
            "F0Mx": 6000.0,
        ]

        let fans = await monitor.readFans()

        XCTAssertEqual(fans.count, 1)
        XCTAssertEqual(fans[0].rpm, 6000)
    }

    func testReadFans_safeIntClampsNaN() async {
        mockReader.byteValues = ["FNum": 1]
        mockReader.floatValues = [
            "F0Ac": Float.nan,
            "F0Mn": 1000.0,
            "F0Mx": 5000.0,
        ]

        // readSMCFloatValue returns NaN which is not an error - safeInt handles it
        // But the flow: readSMCFloatValue returns NaN, safeInt returns fallback 0
        let fans = await monitor.readFans()
        XCTAssertEqual(fans.count, 1)
        XCTAssertEqual(fans[0].rpm, 0) // NaN -> fallback
    }

    // MARK: - CPU Usage

    func testReadCPUUsage_firstCall_returnsZero() {
        // First call has no previous ticks, so it returns 0
        let usage = monitor.readCPUUsage()
        XCTAssertEqual(usage, 0.0)
    }

    func testCalculateCPUUsage_mockedZeroPercent() {
        let previous: HardwareMonitor.CPUTicks = (user: 10, system: 10, idle: 10, nice: 0)
        let current: HardwareMonitor.CPUTicks = (user: 10, system: 10, idle: 110, nice: 0)

        XCTAssertEqual(HardwareMonitor.calculateCPUUsage(previous: previous, current: current), 0.0)
    }

    func testCalculateCPUUsage_mockedFiftyPercent() {
        let previous: HardwareMonitor.CPUTicks = (user: 0, system: 0, idle: 0, nice: 0)
        let current: HardwareMonitor.CPUTicks = (user: 25, system: 25, idle: 50, nice: 0)

        XCTAssertEqual(HardwareMonitor.calculateCPUUsage(previous: previous, current: current), 50.0)
    }

    func testCalculateCPUUsage_mockedHundredPercent() {
        let previous: HardwareMonitor.CPUTicks = (user: 0, system: 0, idle: 0, nice: 0)
        let current: HardwareMonitor.CPUTicks = (user: 40, system: 60, idle: 0, nice: 0)

        XCTAssertEqual(HardwareMonitor.calculateCPUUsage(previous: previous, current: current), 100.0)
    }

    func testCalculateCPUUsage_withoutBaseline_returnsZero() {
        let current: HardwareMonitor.CPUTicks = (user: 40, system: 60, idle: 0, nice: 0)

        XCTAssertEqual(HardwareMonitor.calculateCPUUsage(previous: nil, current: current), 0.0)
    }

    func testReadCPUUsage_secondCall_returnsNonNegative() {
        _ = monitor.readCPUUsage() // establish baseline
        let usage = monitor.readCPUUsage()
        XCTAssertGreaterThanOrEqual(usage, 0.0)
        XCTAssertLessThanOrEqual(usage, 100.0)
    }

    // MARK: - Memory Usage

    func testReadMemoryUsage_returnsValidData() {
        let memory = HardwareMonitor.readMemoryUsage()
        XCTAssertTrue(memory.total > 0, "Total memory should be positive")
        XCTAssertTrue(memory.used > 0, "Used memory should be positive")
        XCTAssertTrue(memory.used <= memory.total, "Used should not exceed total")
    }

    func testReadMemoryUsage_pressureIsValid() {
        let memory = HardwareMonitor.readMemoryUsage()
        // Should be one of the valid states
        let validPressures: [MemoryPressure] = [.nominal, .warning, .critical]
        XCTAssertTrue(validPressures.contains(memory.pressure))
    }

    // MARK: - Full refresh cycle

    func testRefresh_fullCycle_populatesAllFields() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = [
            "TC0C": 55.0,
            "GC0C": 45.0,
        ]
        mockReader.byteValues = ["FNum": 1]
        mockReader.floatValues = [
            "F0Ac": 2000.0,
            "F0Mn": 1000.0,
            "F0Mx": 5000.0,
        ]

        await monitor.refresh()

        XCTAssertEqual(monitor.cpuTemperature, 55.0)
        XCTAssertEqual(monitor.gpuTemperature, 45.0)
        XCTAssertEqual(monitor.fans.count, 1)
        XCTAssertTrue(monitor.memory.total > 0)
    }

    func testRefresh_consecutiveCalls_updateValues() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = ["TC0C": 50.0]
        await monitor.refresh()
        XCTAssertEqual(monitor.cpuTemperature, 50.0)

        mockReader.temperatureValues = ["TC0C": 65.0]
        await monitor.refresh()
        XCTAssertEqual(monitor.cpuTemperature, 65.0)
    }

    // MARK: - Readable-key caching

    func testReadTemperatures_cachesReadableKeysAfterFirstProbe() async {
        mockReader.isInstalled = true
        // Only TC0C returns a valid reading on the first probe.
        mockReader.temperatureValues = ["TC0C": 55.0]
        let first = await monitor.readTemperatures()
        XCTAssertEqual(first.map(\.key), ["TC0C"])

        // Add a new sensor *after* the probe. Because only previously
        // readable keys are polled now, the new sensor should be ignored
        // until the cache is reset (helper reinstall).
        mockReader.temperatureValues = ["TC0C": 55.0, "GC0C": 60.0]
        let second = await monitor.readTemperatures()
        XCTAssertEqual(second.map(\.key), ["TC0C"])
    }

    func testRefresh_helperReinstallAfterUninstall_reprobesSensors() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = ["TC0C": 55.0]
        await monitor.refresh()
        XCTAssertEqual(monitor.sensors.map(\.key), ["TC0C"])

        // Helper goes away: sensors cleared and cache invalidated.
        mockReader.isInstalled = false
        await monitor.refresh()
        XCTAssertTrue(monitor.sensors.isEmpty)

        // Helper comes back with a different set of sensors: the monitor
        // should re-probe and pick up the new key.
        mockReader.isInstalled = true
        mockReader.temperatureValues = ["GC0C": 62.0]
        await monitor.refresh()
        XCTAssertEqual(monitor.sensors.map(\.key), ["GC0C"])
    }

    // MARK: - Representative temperatures (Apple Silicon fallbacks)

    func testRepresentativeCPUTemperature_prefersIntelDie() {
        let readings = [
            SensorReading(key: "TC0C", name: "CPU Die", value: 60.0, unit: .celsius, category: .cpu),
            SensorReading(key: "Tp01", name: "Performance Core 1", value: 85.0, unit: .celsius, category: .performanceCores),
        ]
        XCTAssertEqual(HardwareMonitor.representativeCPUTemperature(from: readings), 60.0)
    }

    func testRepresentativeCPUTemperature_fallsBackToHottestCore() {
        let readings = [
            SensorReading(key: "Tp01", name: "Performance Core 1", value: 55.0, unit: .celsius, category: .performanceCores),
            SensorReading(key: "Tp05", name: "Performance Core 2", value: 72.0, unit: .celsius, category: .performanceCores),
            SensorReading(key: "Tp09", name: "Efficiency Core 1", value: 48.0, unit: .celsius, category: .efficiencyCores),
        ]
        XCTAssertEqual(HardwareMonitor.representativeCPUTemperature(from: readings), 72.0)
    }

    func testRepresentativeCPUTemperature_noCPUReadings_returnsZero() {
        let readings = [
            SensorReading(key: "TB0T", name: "Battery", value: 30.0, unit: .celsius, category: .battery),
        ]
        XCTAssertEqual(HardwareMonitor.representativeCPUTemperature(from: readings), 0.0)
    }

    func testRepresentativeCPUTemperature_noPerformanceCores_fallsBackToEfficiencyCores() {
        // Simulates a machine that only exposes efficiency-core sensors.
        let readings = [
            SensorReading(key: "Tp09", name: "Efficiency Core 1", value: 48.0, unit: .celsius, category: .efficiencyCores),
            SensorReading(key: "Tp0T", name: "Efficiency Core 2", value: 65.0, unit: .celsius, category: .efficiencyCores),
        ]
        XCTAssertEqual(HardwareMonitor.representativeCPUTemperature(from: readings), 65.0)
    }

    func testRepresentativeCPUTemperature_prefersPerformanceOverEfficiencyCores() {
        // Even if an efficiency core is hotter, we should report the
        // hottest *performance* core as the representative CPU value.
        let readings = [
            SensorReading(key: "Tp09", name: "Efficiency Core 1", value: 90.0, unit: .celsius, category: .efficiencyCores),
            SensorReading(key: "Tp01", name: "Performance Core 1", value: 60.0, unit: .celsius, category: .performanceCores),
        ]
        XCTAssertEqual(HardwareMonitor.representativeCPUTemperature(from: readings), 60.0)
    }

    func testRepresentativeGPUTemperature_prefersIntelDie() {
        let readings = [
            SensorReading(key: "GC0C", name: "GPU", value: 50.0, unit: .celsius, category: .gpu),
            SensorReading(key: "Tg05", name: "GPU Cluster 1", value: 80.0, unit: .celsius, category: .gpu),
        ]
        XCTAssertEqual(HardwareMonitor.representativeGPUTemperature(from: readings), 50.0)
    }

    func testRepresentativeGPUTemperature_fallsBackToHottestCluster() {
        let readings = [
            SensorReading(key: "Tg05", name: "GPU Cluster 1", value: 55.0, unit: .celsius, category: .gpu),
            SensorReading(key: "Tg0D", name: "GPU Cluster 2", value: 68.0, unit: .celsius, category: .gpu),
        ]
        XCTAssertEqual(HardwareMonitor.representativeGPUTemperature(from: readings), 68.0)
    }

    func testRepresentativeGPUTemperature_noGPUReadings_returnsZero() {
        let readings = [
            SensorReading(key: "TC0C", name: "CPU Die", value: 50.0, unit: .celsius, category: .cpu),
        ]
        XCTAssertEqual(HardwareMonitor.representativeGPUTemperature(from: readings), 0.0)
    }

    func testRefresh_appleSilicon_populatesCPUFromPerformanceCores() async {
        mockReader.isInstalled = true
        mockReader.temperatureValues = [
            // Simulate Apple Silicon: no TC0C/TC0P, but per-core sensors exist
            "Tp01": 60.0,
            "Tp05": 82.0,
            "Tg05": 58.0,
        ]

        await monitor.refresh()

        XCTAssertEqual(monitor.cpuTemperature, 82.0, "CPU temp should come from hottest performance core")
        XCTAssertEqual(monitor.gpuTemperature, 58.0, "GPU temp should come from hottest GPU cluster")
    }
}
