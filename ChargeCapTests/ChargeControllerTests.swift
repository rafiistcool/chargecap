import XCTest
@testable import ChargeCap

final class ChargeControllerTests: XCTestCase {

    // MARK: - Helpers

    private func makeBatteryState(
        chargePercent: Int = 50,
        isCharging: Bool = true,
        isPluggedIn: Bool = true,
        temperature: Double = 30.0,
        timeToFull: Int = 60
    ) -> BatteryState {
        BatteryState(
            chargePercent: chargePercent,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            chargeLimit: nil,
            batteryRate: nil,
            timeToFull: timeToFull,
            timeToEmpty: 0,
            healthPercent: 100,
            condition: .normal,
            cycleCount: 100,
            maxCycleCount: 1000,
            temperature: temperature,
            designCapacity: 5103,
            maxCapacity: 5103,
            adapterWattage: 67,
            isChargeInhibited: false,
            hasBattery: true
        )
    }

    private func makeControlState(
        targetLimit: Int = 80,
        sailingRange: Int = 5,
        isEnabled: Bool = true,
        isSailingModeEnabled: Bool = true,
        isHeatProtectionEnabled: Bool = false,
        warmTemperatureThreshold: Int = 35,
        hotTemperatureThreshold: Int = 40
    ) -> ChargeControlState {
        ChargeControlState(
            targetLimit: targetLimit,
            sailingRange: sailingRange,
            warmTemperatureThreshold: warmTemperatureThreshold,
            hotTemperatureThreshold: hotTemperatureThreshold,
            isEnabled: isEnabled,
            isSailingModeEnabled: isSailingModeEnabled,
            isHeatProtectionEnabled: isHeatProtectionEnabled,
            command: .normal,
            status: .chargingToLimit,
            lastTransitionDate: nil,
            lastErrorDescription: nil,
            scheduledOverrideDate: nil
        )
    }

    // MARK: - currentCharge 78%, limit 80% -> keep charging

    func testCharging_78Percent_limit80_keepsCharging() {
        let battery = makeBatteryState(chargePercent: 78)
        let state = makeControlState(targetLimit: 80)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .chargingToLimit)
        XCTAssertEqual(result.command, .normal)
    }

    // MARK: - currentCharge 80%, limit 80% -> stop charging

    func testCharging_80Percent_limit80_stopsCharging() {
        let battery = makeBatteryState(chargePercent: 80)
        let state = makeControlState(targetLimit: 80)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .limitReached)
        XCTAssertEqual(result.command, .inhibit)
    }

    func testCharging_aboveLimit_inhibits() {
        let battery = makeBatteryState(chargePercent: 85)
        let state = makeControlState(targetLimit: 80)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .limitReached)
        XCTAssertEqual(result.command, .inhibit)
    }

    // MARK: - currentCharge 74%, sailing threshold 75% -> resume charging

    func testSailing_74Percent_threshold75_resumesCharging() {
        // targetLimit=80, sailingRange=5 -> resumeThreshold = 75
        let battery = makeBatteryState(chargePercent: 74)
        let state = makeControlState(targetLimit: 80, sailingRange: 5, isSailingModeEnabled: true)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .inhibit,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        // chargePercent 74 <= resumeThreshold 75 -> resume
        XCTAssertEqual(result.status, .chargingToLimit)
        XCTAssertEqual(result.command, .normal)
    }

    // MARK: - currentCharge 76%, sailing threshold 75% -> do NOT resume

    func testSailing_76Percent_threshold75_doesNotResume() {
        // targetLimit=80, sailingRange=5 -> resumeThreshold = 75
        let battery = makeBatteryState(chargePercent: 76)
        let state = makeControlState(targetLimit: 80, sailingRange: 5, isSailingModeEnabled: true)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .inhibit,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        // chargePercent 76 > resumeThreshold 75, sailing mode, was inhibiting
        XCTAssertEqual(result.status, .sailing)
        XCTAssertEqual(result.command, .inhibit)
    }

    // MARK: - Sailing mode was paused (not inhibited)

    func testSailing_76Percent_lastCommandPause_staysSailing() {
        let battery = makeBatteryState(chargePercent: 76)
        let state = makeControlState(targetLimit: 80, sailingRange: 5, isSailingModeEnabled: true)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .pause,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .sailing)
        XCTAssertEqual(result.command, .inhibit)
    }

    // MARK: - Sailing disabled -> no sailing

    func testSailingDisabled_aboveResumeThreshold_keepsCharging() {
        let battery = makeBatteryState(chargePercent: 76)
        let state = makeControlState(targetLimit: 80, sailingRange: 5, isSailingModeEnabled: false)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .inhibit,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        // Sailing disabled; resumeThreshold = targetLimit = 80; 76 <= 80 -> charging
        XCTAssertEqual(result.status, .chargingToLimit)
        XCTAssertEqual(result.command, .normal)
    }

    func testSailingDisabled_lastCommandPause_keepsCharging() {
        let battery = makeBatteryState(chargePercent: 76)
        let state = makeControlState(targetLimit: 80, sailingRange: 5, isSailingModeEnabled: false)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .pause,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .chargingToLimit)
        XCTAssertEqual(result.command, .normal)
    }

    // MARK: - Edge case: 100% limit (no limiting needed)

    func testCharging_100PercentLimit_belowLimit_keepsCharging() {
        let battery = makeBatteryState(chargePercent: 95)
        let state = makeControlState(targetLimit: 100)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .chargingToLimit)
        XCTAssertEqual(result.command, .normal)
    }

    func testCharging_100Percent_100Limit_stopsCharging() {
        let battery = makeBatteryState(chargePercent: 100)
        let state = makeControlState(targetLimit: 100)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .limitReached)
        XCTAssertEqual(result.command, .inhibit)
    }

    // MARK: - Heat protection: temp > 40C -> stop regardless of charge

    func testHeatProtection_hotTemperature_stopsCharging() {
        let battery = makeBatteryState(chargePercent: 50, temperature: 41.0)
        let state = makeControlState(
            isHeatProtectionEnabled: true,
            warmTemperatureThreshold: 35,
            hotTemperatureThreshold: 40
        )

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .heatProtectionStopped)
        XCTAssertEqual(result.command, .inhibit)
    }

    func testHeatProtection_warmTemperature_pausesCharging() {
        let battery = makeBatteryState(chargePercent: 50, temperature: 36.0)
        let state = makeControlState(
            isHeatProtectionEnabled: true,
            warmTemperatureThreshold: 35,
            hotTemperatureThreshold: 40
        )

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .heatProtectionPaused)
        XCTAssertEqual(result.command, .pause)
    }

    func testHeatProtection_atExactHotThreshold_stopsCharging() {
        let battery = makeBatteryState(chargePercent: 50, temperature: 40.0)
        let state = makeControlState(
            isHeatProtectionEnabled: true,
            warmTemperatureThreshold: 35,
            hotTemperatureThreshold: 40
        )

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .heatProtectionStopped)
        XCTAssertEqual(result.command, .inhibit)
    }

    func testHeatProtection_atExactWarmThreshold_pausesCharging() {
        let battery = makeBatteryState(chargePercent: 50, temperature: 35.0)
        let state = makeControlState(
            isHeatProtectionEnabled: true,
            warmTemperatureThreshold: 35,
            hotTemperatureThreshold: 40
        )

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .heatProtectionPaused)
        XCTAssertEqual(result.command, .pause)
    }

    // MARK: - Heat protection: temp drops -> resume

    func testHeatProtection_temperatureDrops_resumesCharging() {
        let battery = makeBatteryState(chargePercent: 50, temperature: 30.0)
        let state = makeControlState(
            isHeatProtectionEnabled: true,
            warmTemperatureThreshold: 35,
            hotTemperatureThreshold: 40
        )

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .inhibit,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        // Temp 30 < warm 35 -> no heat protection; 50 <= resumeThreshold(75) -> charge
        XCTAssertEqual(result.status, .chargingToLimit)
        XCTAssertEqual(result.command, .normal)
    }

    // MARK: - Heat protection disabled -> no heat action

    func testHeatProtectionDisabled_hotTemp_noAction() {
        let battery = makeBatteryState(chargePercent: 50, temperature: 45.0)
        let state = makeControlState(
            isHeatProtectionEnabled: false,
            warmTemperatureThreshold: 35,
            hotTemperatureThreshold: 40
        )

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .chargingToLimit)
        XCTAssertEqual(result.command, .normal)
    }

    // MARK: - Not plugged in -> idle

    func testNotPluggedIn_returnsIdle() {
        let battery = makeBatteryState(chargePercent: 50, isPluggedIn: false)
        let state = makeControlState(targetLimit: 80)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        XCTAssertEqual(result.status, .idle)
        XCTAssertEqual(result.command, .normal)
    }

    // MARK: - Scheduled top-off

    func testScheduledTopOff_overridesNormalLimiting() {
        let futureDate = Date.now.addingTimeInterval(3600)
        let battery = makeBatteryState(chargePercent: 78)
        let state = makeControlState(targetLimit: 80)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: true,
            nextSchedule: futureDate
        )

        XCTAssertEqual(result.command, .normal)
        if case .scheduledTopOff = result.status {
            // OK
        } else {
            XCTFail("Expected scheduledTopOff status, got \(result.status)")
        }
    }

    // MARK: - shouldChargeToFull

    func testShouldChargeToFull_noSchedule_returnsFalse() {
        let battery = makeBatteryState(chargePercent: 70, isPluggedIn: true)
        let result = ChargeController.shouldChargeToFull(batteryState: battery, nextSchedule: nil)
        XCTAssertFalse(result)
    }

    func testShouldChargeToFull_notPluggedIn_returnsFalse() {
        let battery = makeBatteryState(chargePercent: 70, isPluggedIn: false)
        let future = Date.now.addingTimeInterval(3600)
        let result = ChargeController.shouldChargeToFull(batteryState: battery, nextSchedule: future)
        XCTAssertFalse(result)
    }

    func testShouldChargeToFull_schedulePast_returnsFalse() {
        let battery = makeBatteryState(chargePercent: 70, isPluggedIn: true)
        let now = Date()
        let past = now.addingTimeInterval(-3600)
        let result = ChargeController.shouldChargeToFull(batteryState: battery, nextSchedule: past, now: now)
        XCTAssertFalse(result)
    }

    func testShouldChargeToFull_enoughTime_returnsTrue() {
        // Need 30% charge, at 3 min/% fallback -> 90 min needed
        // Schedule 60 min from now -> 60 <= 90 -> should charge
        let battery = makeBatteryState(chargePercent: 70, isCharging: false, isPluggedIn: true, timeToFull: 0)
        let now = Date()
        let future = now.addingTimeInterval(60 * 60)
        let result = ChargeController.shouldChargeToFull(batteryState: battery, nextSchedule: future, now: now)
        XCTAssertTrue(result)
    }

    func testShouldChargeToFull_tooFarAway_returnsFalse() {
        // Need 30% charge, at 3 min/% fallback -> 90 min needed
        // Schedule 120 min from now -> 120 > 90 -> don't charge yet
        let battery = makeBatteryState(chargePercent: 70, isCharging: false, isPluggedIn: true, timeToFull: 0)
        let now = Date()
        let future = now.addingTimeInterval(120 * 60)
        let result = ChargeController.shouldChargeToFull(batteryState: battery, nextSchedule: future, now: now)
        XCTAssertFalse(result)
    }

    func testShouldChargeToFull_alreadyFull_returnsFalse() {
        let battery = makeBatteryState(chargePercent: 100, isPluggedIn: true)
        let now = Date()
        let future = now.addingTimeInterval(30 * 60)
        let result = ChargeController.shouldChargeToFull(batteryState: battery, nextSchedule: future, now: now)
        XCTAssertFalse(result)
    }

    func testShouldChargeToFull_usesTimeToFull_whenCharging() {
        // Charging with timeToFull = 30 min, schedule in 25 min -> 25 <= 30 -> true
        let battery = makeBatteryState(chargePercent: 70, isCharging: true, isPluggedIn: true, timeToFull: 30)
        let now = Date()
        let future = now.addingTimeInterval(25 * 60)
        let result = ChargeController.shouldChargeToFull(batteryState: battery, nextSchedule: future, now: now)
        XCTAssertTrue(result)
    }

    // MARK: - Heat protection takes priority over plug state

    func testHeatProtection_unplugged_stillTriggered() {
        let battery = makeBatteryState(chargePercent: 50, isPluggedIn: false, temperature: 42.0)
        let state = makeControlState(
            isHeatProtectionEnabled: true,
            warmTemperatureThreshold: 35,
            hotTemperatureThreshold: 40
        )

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .normal,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        // Heat protection fires before plug check
        XCTAssertEqual(result.status, .heatProtectionStopped)
        XCTAssertEqual(result.command, .inhibit)
    }

    // MARK: - No last command -> charges normally in sailing zone

    func testSailing_noLastCommand_chargesNormally() {
        let battery = makeBatteryState(chargePercent: 76)
        let state = makeControlState(targetLimit: 80, sailingRange: 5, isSailingModeEnabled: true)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: nil,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        // No last command -> not sailing, still in range to charge
        XCTAssertEqual(result.status, .chargingToLimit)
        XCTAssertEqual(result.command, .normal)
    }

    // MARK: - Exactly at resume threshold

    func testSailing_exactlyAtResumeThreshold_resumesCharging() {
        // targetLimit=80, sailingRange=5 -> resumeThreshold = 75
        let battery = makeBatteryState(chargePercent: 75)
        let state = makeControlState(targetLimit: 80, sailingRange: 5, isSailingModeEnabled: true)

        let result = ChargeController.desiredState(
            for: battery,
            controlState: state,
            lastCommand: .inhibit,
            shouldTopOffToFull: false,
            nextSchedule: nil
        )

        // chargePercent 75 <= resumeThreshold 75 -> resume
        XCTAssertEqual(result.status, .chargingToLimit)
        XCTAssertEqual(result.command, .normal)
    }
}

// MARK: - ChargeController state-building tests

@MainActor
final class ChargeControllerStateTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ChargeControllerStateTests")!
        defaults.removePersistentDomain(forName: "ChargeControllerStateTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ChargeControllerStateTests")
        defaults = nil
        super.tearDown()
    }

    // MARK: - makeInitialState

    func testMakeInitialState_usesSettingsValues() {
        let settings = AppSettings(defaults: defaults)
        settings.targetChargeLimit = 70
        settings.sailingRange = 8
        settings.warmTemperatureThreshold = 33
        settings.hotTemperatureThreshold = 42
        settings.isChargeLimitingEnabled = true
        settings.isSailingModeEnabled = false
        settings.isHeatProtectionEnabled = true

        let state = ChargeController.makeInitialState(settings: settings)

        XCTAssertEqual(state.targetLimit, 70)
        XCTAssertEqual(state.sailingRange, 8)
        XCTAssertEqual(state.warmTemperatureThreshold, 33)
        XCTAssertEqual(state.hotTemperatureThreshold, 42)
        XCTAssertTrue(state.isEnabled)
        XCTAssertFalse(state.isSailingModeEnabled)
        XCTAssertTrue(state.isHeatProtectionEnabled)
    }

    func testMakeInitialState_defaultSettings() {
        let settings = AppSettings(defaults: defaults)
        let state = ChargeController.makeInitialState(settings: settings)

        XCTAssertEqual(state.targetLimit, Constants.defaultChargeLimit)
        XCTAssertEqual(state.sailingRange, Constants.defaultSailingRange)
        XCTAssertEqual(state.warmTemperatureThreshold, Constants.defaultWarmTemperatureThreshold)
        XCTAssertEqual(state.hotTemperatureThreshold, Constants.defaultHotTemperatureThreshold)
        XCTAssertFalse(state.isEnabled)
        XCTAssertTrue(state.isSailingModeEnabled)
        XCTAssertFalse(state.isHeatProtectionEnabled)
    }

    // MARK: - state(from:settings:)

    func testStateFromSettings_updatesAllFields() {
        let settings = AppSettings(defaults: defaults)
        settings.targetChargeLimit = 65
        settings.sailingRange = 9
        settings.isChargeLimitingEnabled = true

        let original = ChargeControlState.default
        let updated = ChargeController.state(from: original, settings: settings)

        XCTAssertEqual(updated.targetLimit, 65)
        XCTAssertEqual(updated.sailingRange, 9)
        XCTAssertTrue(updated.isEnabled)
    }

    func testStateFromSettings_preservesNonSettingsFields() {
        let settings = AppSettings(defaults: defaults)
        var original = ChargeControlState.default
        original.command = .inhibit
        original.status = .limitReached
        original.lastTransitionDate = Date(timeIntervalSince1970: 1000)
        original.lastErrorDescription = "test error"
        original.scheduledOverrideDate = Date(timeIntervalSince1970: 2000)

        let updated = ChargeController.state(from: original, settings: settings)

        // These should be preserved from the original
        XCTAssertEqual(updated.command, .inhibit)
        XCTAssertEqual(updated.status, .limitReached)
        XCTAssertEqual(updated.lastTransitionDate, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(updated.lastErrorDescription, "test error")
        XCTAssertEqual(updated.scheduledOverrideDate, Date(timeIntervalSince1970: 2000))
    }

    func testStateFromSettings_resumeThreshold_withSailing() {
        let settings = AppSettings(defaults: defaults)
        settings.targetChargeLimit = 80
        settings.sailingRange = 5
        settings.isSailingModeEnabled = true

        let state = ChargeController.makeInitialState(settings: settings)

        XCTAssertEqual(state.resumeThreshold, 75) // 80 - 5
    }

    func testStateFromSettings_resumeThreshold_withoutSailing() {
        let settings = AppSettings(defaults: defaults)
        settings.targetChargeLimit = 80
        settings.isSailingModeEnabled = false

        let state = ChargeController.makeInitialState(settings: settings)

        XCTAssertEqual(state.resumeThreshold, 80) // same as target when sailing disabled
    }
}
