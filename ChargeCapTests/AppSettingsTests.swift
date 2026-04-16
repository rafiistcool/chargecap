import XCTest
@testable import ChargeCap

@MainActor
final class AppSettingsTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AppSettingsTests")!
        defaults.removePersistentDomain(forName: "AppSettingsTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "AppSettingsTests")
        defaults = nil
        super.tearDown()
    }

    // MARK: - Default values

    func testInit_noStoredValues_usesDefaults() {
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.isChargeLimitingEnabled)
        XCTAssertEqual(settings.targetChargeLimit, Constants.defaultChargeLimit) // 80
        XCTAssertEqual(settings.sailingRange, Constants.defaultSailingRange) // 5
        XCTAssertEqual(settings.warmTemperatureThreshold, Constants.defaultWarmTemperatureThreshold) // 35
        XCTAssertEqual(settings.hotTemperatureThreshold, Constants.defaultHotTemperatureThreshold) // 40
        XCTAssertTrue(settings.isSailingModeEnabled)
        XCTAssertFalse(settings.isHeatProtectionEnabled)
        XCTAssertEqual(settings.fanControlMode, .auto)
        XCTAssertFalse(settings.isManualFanCurveEnabled)
        XCTAssertTrue(settings.notifyAtChargeLimit)
        XCTAssertTrue(settings.notifyOnHealthDrop)
        XCTAssertFalse(settings.notifyOnTemperatureAlert)
        XCTAssertTrue(settings.showPercentInMenuBar)
        XCTAssertEqual(settings.refreshIntervalSeconds, Int(Constants.defaultRefreshInterval)) // 15
        XCTAssertEqual(settings.chargeSchedule, .default)
    }

    // MARK: - Stored values

    func testInit_withStoredValues_loadsCorrectly() {
        defaults.set(true, forKey: "chargeLimitingEnabled")
        defaults.set(70, forKey: "targetChargeLimit")
        defaults.set(7, forKey: "sailingRange")
        defaults.set(33, forKey: "warmTemperatureThreshold")
        defaults.set(42, forKey: "hotTemperatureThreshold")
        defaults.set(false, forKey: "sailingModeEnabled")
        defaults.set(true, forKey: "heatProtectionEnabled")
        defaults.set("Performance", forKey: "fanControlMode")
        defaults.set(true, forKey: "manualFanCurveEnabled")
        defaults.set(false, forKey: "notifyAtChargeLimit")
        defaults.set(false, forKey: "notifyOnHealthDrop")
        defaults.set(true, forKey: "notifyOnTemperatureAlert")
        defaults.set(false, forKey: "showPercentInMenuBar")
        defaults.set(30, forKey: "refreshIntervalSeconds")

        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.isChargeLimitingEnabled)
        XCTAssertEqual(settings.targetChargeLimit, 70)
        XCTAssertEqual(settings.sailingRange, 7)
        XCTAssertEqual(settings.warmTemperatureThreshold, 33)
        XCTAssertEqual(settings.hotTemperatureThreshold, 42)
        XCTAssertFalse(settings.isSailingModeEnabled)
        XCTAssertTrue(settings.isHeatProtectionEnabled)
        XCTAssertEqual(settings.fanControlMode, .performance)
        XCTAssertTrue(settings.isManualFanCurveEnabled)
        XCTAssertFalse(settings.notifyAtChargeLimit)
        XCTAssertFalse(settings.notifyOnHealthDrop)
        XCTAssertTrue(settings.notifyOnTemperatureAlert)
        XCTAssertFalse(settings.showPercentInMenuBar)
        XCTAssertEqual(settings.refreshIntervalSeconds, 30)
    }

    // MARK: - Charge limit clamping

    func testTargetChargeLimit_tooLow_clampedToMin() {
        defaults.set(5, forKey: "targetChargeLimit")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.targetChargeLimit, Constants.minChargeLimit) // 20
    }

    func testTargetChargeLimit_tooHigh_clampedToMax() {
        defaults.set(200, forKey: "targetChargeLimit")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.targetChargeLimit, Constants.maxChargeLimit) // 100
    }

    func testTargetChargeLimit_atMin_stays() {
        defaults.set(Constants.minChargeLimit, forKey: "targetChargeLimit")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.targetChargeLimit, Constants.minChargeLimit)
    }

    func testTargetChargeLimit_atMax_stays() {
        defaults.set(Constants.maxChargeLimit, forKey: "targetChargeLimit")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.targetChargeLimit, Constants.maxChargeLimit)
    }

    func testTargetChargeLimit_didSet_clampsAndPersists() {
        let settings = AppSettings(defaults: defaults)
        settings.targetChargeLimit = 50
        XCTAssertEqual(settings.targetChargeLimit, 50)
        XCTAssertEqual(defaults.integer(forKey: "targetChargeLimit"), 50)
    }

    func testTargetChargeLimit_didSet_tooLow_clamps() {
        let settings = AppSettings(defaults: defaults)
        settings.targetChargeLimit = 10
        XCTAssertEqual(settings.targetChargeLimit, Constants.minChargeLimit)
    }

    func testTargetChargeLimit_didSet_tooHigh_clamps() {
        let settings = AppSettings(defaults: defaults)
        settings.targetChargeLimit = 110
        XCTAssertEqual(settings.targetChargeLimit, Constants.maxChargeLimit)
    }

    // MARK: - Sailing range clamping

    func testSailingRange_tooLow_clampedToMin() {
        defaults.set(1, forKey: "sailingRange")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.sailingRange, Constants.minSailingRange) // 3
    }

    func testSailingRange_tooHigh_clampedToMax() {
        defaults.set(20, forKey: "sailingRange")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.sailingRange, Constants.maxSailingRange) // 10
    }

    func testSailingRange_didSet_clampsAndPersists() {
        let settings = AppSettings(defaults: defaults)
        settings.sailingRange = 8
        XCTAssertEqual(settings.sailingRange, 8)
        XCTAssertEqual(defaults.integer(forKey: "sailingRange"), 8)
    }

    func testSailingRange_didSet_tooLow_clamps() {
        let settings = AppSettings(defaults: defaults)
        settings.sailingRange = 0
        XCTAssertEqual(settings.sailingRange, Constants.minSailingRange)
    }

    func testSailingRange_didSet_tooHigh_clamps() {
        let settings = AppSettings(defaults: defaults)
        settings.sailingRange = 50
        XCTAssertEqual(settings.sailingRange, Constants.maxSailingRange)
    }

    // MARK: - Warm/hot temperature threshold clamping

    func testWarmThreshold_tooLow_clampedToMin() {
        defaults.set(20, forKey: "warmTemperatureThreshold")
        defaults.set(40, forKey: "hotTemperatureThreshold")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.warmTemperatureThreshold, Constants.minWarmTemperatureThreshold) // 30
    }

    func testWarmThreshold_aboveHotMinusOne_clamped() {
        defaults.set(42, forKey: "warmTemperatureThreshold")
        defaults.set(40, forKey: "hotTemperatureThreshold")
        let settings = AppSettings(defaults: defaults)
        // warm must be < hot; clampWarmThreshold upper = min(44, 39) = 39
        XCTAssertEqual(settings.warmTemperatureThreshold, 39)
    }

    func testHotThreshold_tooHigh_clampedToMax() {
        defaults.set(35, forKey: "warmTemperatureThreshold")
        defaults.set(99, forKey: "hotTemperatureThreshold")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.hotTemperatureThreshold, Constants.maxHotTemperatureThreshold) // 45
    }

    func testHotThreshold_belowWarmPlusOne_clampedUp() {
        defaults.set(35, forKey: "warmTemperatureThreshold")
        defaults.set(34, forKey: "hotTemperatureThreshold")
        let settings = AppSettings(defaults: defaults)
        // warm is clamped first: clampWarm(35, hot=34) -> upperBound=min(44,33)=33 -> warm=33
        // then hot: clampHot(34, warm=33) -> minimum=max(31,34)=34 -> hot=34
        XCTAssertEqual(settings.warmTemperatureThreshold, 33)
        XCTAssertEqual(settings.hotTemperatureThreshold, 34)
    }

    func testWarmThreshold_didSet_clampsAndPersists() {
        let settings = AppSettings(defaults: defaults)
        // hot default = 40, so warm can go up to 39
        settings.warmTemperatureThreshold = 37
        XCTAssertEqual(settings.warmTemperatureThreshold, 37)
        XCTAssertEqual(defaults.integer(forKey: "warmTemperatureThreshold"), 37)
    }

    func testWarmThreshold_didSet_tooLow_clamps() {
        let settings = AppSettings(defaults: defaults)
        settings.warmTemperatureThreshold = 10
        XCTAssertEqual(settings.warmTemperatureThreshold, Constants.minWarmTemperatureThreshold)
    }

    func testHotThreshold_didSet_clampsAndPersists() {
        let settings = AppSettings(defaults: defaults)
        // warm default = 35, so hot must be >= 36
        settings.hotTemperatureThreshold = 42
        XCTAssertEqual(settings.hotTemperatureThreshold, 42)
        XCTAssertEqual(defaults.integer(forKey: "hotTemperatureThreshold"), 42)
    }

    func testHotThreshold_didSet_tooLow_clamps() {
        let settings = AppSettings(defaults: defaults)
        // warm default = 35, minimum hot = 36
        settings.hotTemperatureThreshold = 33
        XCTAssertEqual(settings.hotTemperatureThreshold, 36)
    }

    // MARK: - Refresh interval clamping

    func testRefreshInterval_tooLow_clampedToMin() {
        defaults.set(0, forKey: "refreshIntervalSeconds")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.refreshIntervalSeconds, Int(Constants.minRefreshInterval)) // 1
    }

    func testRefreshInterval_tooHigh_clampedToMax() {
        defaults.set(999, forKey: "refreshIntervalSeconds")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.refreshIntervalSeconds, Int(Constants.maxRefreshInterval)) // 60
    }

    func testRefreshInterval_didSet_clampsAndPersists() {
        let settings = AppSettings(defaults: defaults)
        settings.refreshIntervalSeconds = 30
        XCTAssertEqual(settings.refreshIntervalSeconds, 30)
        XCTAssertEqual(defaults.integer(forKey: "refreshIntervalSeconds"), 30)
    }

    func testRefreshInterval_didSet_tooLow_clamps() {
        let settings = AppSettings(defaults: defaults)
        settings.refreshIntervalSeconds = -5
        XCTAssertEqual(settings.refreshIntervalSeconds, Int(Constants.minRefreshInterval))
    }

    func testRefreshInterval_didSet_tooHigh_clamps() {
        let settings = AppSettings(defaults: defaults)
        settings.refreshIntervalSeconds = 1000
        XCTAssertEqual(settings.refreshIntervalSeconds, Int(Constants.maxRefreshInterval))
    }

    // MARK: - Boolean property persistence

    func testIsChargeLimitingEnabled_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.isChargeLimitingEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "chargeLimitingEnabled"))

        settings.isChargeLimitingEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "chargeLimitingEnabled"))
    }

    func testIsSailingModeEnabled_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.isSailingModeEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "sailingModeEnabled"))

        settings.isSailingModeEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "sailingModeEnabled"))
    }

    func testIsHeatProtectionEnabled_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.isHeatProtectionEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "heatProtectionEnabled"))
    }

    func testNotifyAtChargeLimit_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.notifyAtChargeLimit = false
        XCTAssertFalse(defaults.bool(forKey: "notifyAtChargeLimit"))
    }

    func testNotifyOnHealthDrop_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.notifyOnHealthDrop = false
        XCTAssertFalse(defaults.bool(forKey: "notifyOnHealthDrop"))
    }

    func testNotifyOnTemperatureAlert_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.notifyOnTemperatureAlert = true
        XCTAssertTrue(defaults.bool(forKey: "notifyOnTemperatureAlert"))
    }

    func testShowPercentInMenuBar_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.showPercentInMenuBar = false
        XCTAssertFalse(defaults.bool(forKey: "showPercentInMenuBar"))
    }

    func testIsManualFanCurveEnabled_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.isManualFanCurveEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "manualFanCurveEnabled"))
    }

    // MARK: - FanControlMode persistence and parsing

    func testFanControlMode_auto_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.fanControlMode = .auto
        XCTAssertEqual(defaults.string(forKey: "fanControlMode"), "Auto")
    }

    func testFanControlMode_performance_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.fanControlMode = .performance
        XCTAssertEqual(defaults.string(forKey: "fanControlMode"), "Performance")
    }

    func testFanControlMode_quiet_persists() {
        let settings = AppSettings(defaults: defaults)
        settings.fanControlMode = .quiet
        XCTAssertEqual(defaults.string(forKey: "fanControlMode"), "Quiet")
    }

    func testFanControlMode_manualMigration_loadsAsPerformance() {
        defaults.set("Manual", forKey: "fanControlMode")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.fanControlMode, .performance)
    }

    func testFanControlMode_invalidString_defaultsToAuto() {
        defaults.set("InvalidMode", forKey: "fanControlMode")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.fanControlMode, .auto)
    }

    func testFanControlMode_noStoredValue_defaultsToAuto() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.fanControlMode, .auto)
    }

    // MARK: - ChargeSchedule persistence

    func testChargeSchedule_encodesAndDecodes() {
        let settings = AppSettings(defaults: defaults)
        let schedule = ChargeSchedule(weekday: 3, hour: 14, minute: 30, isEnabled: true)
        settings.chargeSchedule = schedule
        XCTAssertEqual(settings.chargeSchedule, schedule)

        // Verify it persists by creating a new AppSettings from same defaults
        let settings2 = AppSettings(defaults: defaults)
        XCTAssertEqual(settings2.chargeSchedule, schedule)
    }

    func testChargeSchedule_sanitizesOutOfRangeValues() {
        let settings = AppSettings(defaults: defaults)
        // weekday out of range (> 7) -> clamped to 7
        settings.chargeSchedule = ChargeSchedule(weekday: 10, hour: 25, minute: 70, isEnabled: true)
        XCTAssertEqual(settings.chargeSchedule.weekday, 7)
        XCTAssertEqual(settings.chargeSchedule.hour, 23)
        XCTAssertEqual(settings.chargeSchedule.minute, 59)
        XCTAssertTrue(settings.chargeSchedule.isEnabled)
    }

    func testChargeSchedule_sanitizesNegativeValues() {
        let settings = AppSettings(defaults: defaults)
        settings.chargeSchedule = ChargeSchedule(weekday: 0, hour: -1, minute: -5, isEnabled: false)
        XCTAssertEqual(settings.chargeSchedule.weekday, 1)
        XCTAssertEqual(settings.chargeSchedule.hour, 0)
        XCTAssertEqual(settings.chargeSchedule.minute, 0)
    }

    func testChargeSchedule_validValues_noChange() {
        let settings = AppSettings(defaults: defaults)
        let schedule = ChargeSchedule(weekday: 4, hour: 12, minute: 30, isEnabled: true)
        settings.chargeSchedule = schedule
        XCTAssertEqual(settings.chargeSchedule, schedule)
    }

    func testChargeSchedule_invalidStoredData_usesDefault() {
        defaults.set(Data("garbage".utf8), forKey: "chargeSchedule")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.chargeSchedule, .default)
    }

    func testChargeSchedule_noStoredData_usesDefault() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.chargeSchedule, .default)
    }

    // MARK: - Multiple settings interact correctly

    func testWarmHotThresholds_interactCorrectly() {
        let settings = AppSettings(defaults: defaults)
        // Set warm = 38, hot stays at default 40
        settings.warmTemperatureThreshold = 38
        XCTAssertEqual(settings.warmTemperatureThreshold, 38)
        XCTAssertEqual(settings.hotTemperatureThreshold, 40)

        // Try to set hot = 38 (must be > warm, so clamped to 39)
        settings.hotTemperatureThreshold = 38
        XCTAssertEqual(settings.hotTemperatureThreshold, 39)
    }

    func testSettings_reloadFromDefaults() {
        let settings1 = AppSettings(defaults: defaults)
        settings1.targetChargeLimit = 65
        settings1.sailingRange = 8
        settings1.refreshIntervalSeconds = 45
        settings1.isChargeLimitingEnabled = true

        let settings2 = AppSettings(defaults: defaults)
        XCTAssertEqual(settings2.targetChargeLimit, 65)
        XCTAssertEqual(settings2.sailingRange, 8)
        XCTAssertEqual(settings2.refreshIntervalSeconds, 45)
        XCTAssertTrue(settings2.isChargeLimitingEnabled)
    }
}
