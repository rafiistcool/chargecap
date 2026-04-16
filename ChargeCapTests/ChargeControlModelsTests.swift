import XCTest
@testable import ChargeCap

final class ChargeControlModelsTests: XCTestCase {

    // MARK: - ChargeControlState.resumeThreshold

    func testResumeThreshold_sailingEnabled() {
        let state = ChargeControlState(
            targetLimit: 80,
            sailingRange: 5,
            warmTemperatureThreshold: 35,
            hotTemperatureThreshold: 40,
            isEnabled: true,
            isSailingModeEnabled: true,
            isHeatProtectionEnabled: false,
            command: .normal,
            status: .chargingToLimit,
            lastTransitionDate: nil,
            lastErrorDescription: nil,
            scheduledOverrideDate: nil
        )
        XCTAssertEqual(state.resumeThreshold, 75) // 80 - 5
    }

    func testResumeThreshold_sailingDisabled() {
        let state = ChargeControlState(
            targetLimit: 80,
            sailingRange: 5,
            warmTemperatureThreshold: 35,
            hotTemperatureThreshold: 40,
            isEnabled: true,
            isSailingModeEnabled: false,
            isHeatProtectionEnabled: false,
            command: .normal,
            status: .chargingToLimit,
            lastTransitionDate: nil,
            lastErrorDescription: nil,
            scheduledOverrideDate: nil
        )
        XCTAssertEqual(state.resumeThreshold, 80) // Same as targetLimit
    }

    func testResumeThreshold_clampedToMinChargeLimit() {
        let state = ChargeControlState(
            targetLimit: 22,
            sailingRange: 5,
            warmTemperatureThreshold: 35,
            hotTemperatureThreshold: 40,
            isEnabled: true,
            isSailingModeEnabled: true,
            isHeatProtectionEnabled: false,
            command: .normal,
            status: .chargingToLimit,
            lastTransitionDate: nil,
            lastErrorDescription: nil,
            scheduledOverrideDate: nil
        )
        // 22 - 5 = 17, but min is Constants.minChargeLimit = 20
        XCTAssertEqual(state.resumeThreshold, 20)
    }

    func testResumeThreshold_largerSailingRange() {
        let state = ChargeControlState(
            targetLimit: 80,
            sailingRange: 10,
            warmTemperatureThreshold: 35,
            hotTemperatureThreshold: 40,
            isEnabled: true,
            isSailingModeEnabled: true,
            isHeatProtectionEnabled: false,
            command: .normal,
            status: .chargingToLimit,
            lastTransitionDate: nil,
            lastErrorDescription: nil,
            scheduledOverrideDate: nil
        )
        XCTAssertEqual(state.resumeThreshold, 70) // 80 - 10
    }

    // MARK: - ChargeControlState.default

    func testDefaultState() {
        let state = ChargeControlState.default
        XCTAssertEqual(state.targetLimit, Constants.defaultChargeLimit)
        XCTAssertEqual(state.sailingRange, Constants.defaultSailingRange)
        XCTAssertFalse(state.isEnabled)
        XCTAssertTrue(state.isSailingModeEnabled)
        XCTAssertFalse(state.isHeatProtectionEnabled)
        XCTAssertEqual(state.command, .normal)
        XCTAssertEqual(state.status, .disabled)
        XCTAssertNil(state.lastTransitionDate)
        XCTAssertNil(state.lastErrorDescription)
        XCTAssertNil(state.scheduledOverrideDate)
    }

    // MARK: - ChargeControlState.isLimiting

    func testIsLimiting_limitReached() {
        var state = ChargeControlState.default
        state.status = .limitReached
        XCTAssertTrue(state.isLimiting)
    }

    func testIsLimiting_sailing() {
        var state = ChargeControlState.default
        state.status = .sailing
        XCTAssertTrue(state.isLimiting)
    }

    func testIsLimiting_heatProtectionPaused() {
        var state = ChargeControlState.default
        state.status = .heatProtectionPaused
        XCTAssertTrue(state.isLimiting)
    }

    func testIsLimiting_heatProtectionStopped() {
        var state = ChargeControlState.default
        state.status = .heatProtectionStopped
        XCTAssertTrue(state.isLimiting)
    }

    func testIsLimiting_disabled() {
        var state = ChargeControlState.default
        state.status = .disabled
        XCTAssertFalse(state.isLimiting)
    }

    func testIsLimiting_chargingToLimit() {
        var state = ChargeControlState.default
        state.status = .chargingToLimit
        XCTAssertFalse(state.isLimiting)
    }

    func testIsLimiting_idle() {
        var state = ChargeControlState.default
        state.status = .idle
        XCTAssertFalse(state.isLimiting)
    }

    func testIsLimiting_unavailable() {
        var state = ChargeControlState.default
        state.status = .unavailable("No helper")
        XCTAssertFalse(state.isLimiting)
    }

    // MARK: - ChargeControlState.isSailing

    func testIsSailing_sailingStatus() {
        var state = ChargeControlState.default
        state.status = .sailing
        XCTAssertTrue(state.isSailing)
    }

    func testIsSailing_otherStatus() {
        var state = ChargeControlState.default
        state.status = .limitReached
        XCTAssertFalse(state.isSailing)
    }

    // MARK: - ChargeLimitStatus description

    func testStatusDescription_disabled() {
        XCTAssertEqual(ChargeLimitStatus.disabled.description, "Charge limiting off")
    }

    func testStatusDescription_unavailable() {
        XCTAssertEqual(ChargeLimitStatus.unavailable("No helper").description, "No helper")
    }

    func testStatusDescription_idle() {
        XCTAssertEqual(ChargeLimitStatus.idle.description, "Monitoring charge limit")
    }

    func testStatusDescription_chargingToLimit() {
        XCTAssertEqual(ChargeLimitStatus.chargingToLimit.description, "Charging to limit")
    }

    func testStatusDescription_limitReached() {
        XCTAssertEqual(ChargeLimitStatus.limitReached.description, "Charge limit active")
    }

    func testStatusDescription_sailing() {
        XCTAssertEqual(ChargeLimitStatus.sailing.description, "Sailing mode active")
    }

    func testStatusDescription_heatProtectionPaused() {
        XCTAssertEqual(ChargeLimitStatus.heatProtectionPaused.description, "Heat protection slowing charge")
    }

    func testStatusDescription_heatProtectionStopped() {
        XCTAssertEqual(ChargeLimitStatus.heatProtectionStopped.description, "Heat protection stopped charging")
    }

    // MARK: - ChargeLimitStatus isLimiting

    func testChargeLimitStatus_isLimiting() {
        XCTAssertTrue(ChargeLimitStatus.limitReached.isLimiting)
        XCTAssertTrue(ChargeLimitStatus.sailing.isLimiting)
        XCTAssertTrue(ChargeLimitStatus.heatProtectionPaused.isLimiting)
        XCTAssertTrue(ChargeLimitStatus.heatProtectionStopped.isLimiting)

        XCTAssertFalse(ChargeLimitStatus.disabled.isLimiting)
        XCTAssertFalse(ChargeLimitStatus.idle.isLimiting)
        XCTAssertFalse(ChargeLimitStatus.chargingToLimit.isLimiting)
        XCTAssertFalse(ChargeLimitStatus.unavailable("test").isLimiting)
    }

    // MARK: - ChargeLimitStatus isSailing

    func testChargeLimitStatus_isSailing() {
        XCTAssertTrue(ChargeLimitStatus.sailing.isSailing)
        XCTAssertFalse(ChargeLimitStatus.limitReached.isSailing)
        XCTAssertFalse(ChargeLimitStatus.disabled.isSailing)
    }

    // MARK: - ChargeSchedule

    func testChargeScheduleDefault() {
        let schedule = ChargeSchedule.default
        XCTAssertEqual(schedule.weekday, 2) // Monday
        XCTAssertEqual(schedule.hour, 8)
        XCTAssertEqual(schedule.minute, 0)
        XCTAssertFalse(schedule.isEnabled)
    }

    func testChargeSchedule_nextTriggerDate_disabled_returnsNil() {
        let schedule = ChargeSchedule(weekday: 2, hour: 8, minute: 0, isEnabled: false)
        XCTAssertNil(schedule.nextTriggerDate())
    }

    func testChargeSchedule_nextTriggerDate_enabled_returnsFutureDate() {
        let schedule = ChargeSchedule(weekday: 2, hour: 8, minute: 0, isEnabled: true)
        let trigger = schedule.nextTriggerDate()
        XCTAssertNotNil(trigger)
        if let trigger {
            XCTAssertTrue(trigger > Date.now)
        }
    }

    func testChargeSchedule_update() {
        var schedule = ChargeSchedule.default
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = 14
        components.minute = 30
        guard let date = calendar.date(from: components) else {
            XCTFail("Could not create date from components")
            return
        }

        schedule.update(from: date, calendar: calendar)
        XCTAssertEqual(schedule.hour, 14)
        XCTAssertEqual(schedule.minute, 30)
    }

    func testChargeSchedule_equatable() {
        let a = ChargeSchedule(weekday: 2, hour: 8, minute: 0, isEnabled: true)
        let b = ChargeSchedule(weekday: 2, hour: 8, minute: 0, isEnabled: true)
        XCTAssertEqual(a, b)
    }

    func testChargeSchedule_notEqual() {
        let a = ChargeSchedule(weekday: 2, hour: 8, minute: 0, isEnabled: true)
        let b = ChargeSchedule(weekday: 3, hour: 8, minute: 0, isEnabled: true)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - ChargeCommand

    func testChargeCommand_rawValues() {
        XCTAssertEqual(ChargeCommand.normal.rawValue, "normal")
        XCTAssertEqual(ChargeCommand.inhibit.rawValue, "inhibit")
        XCTAssertEqual(ChargeCommand.pause.rawValue, "pause")
    }

    // MARK: - FanControlMode

    func testFanControlMode_rawValues() {
        XCTAssertEqual(FanControlMode.auto.rawValue, "Auto")
        XCTAssertEqual(FanControlMode.performance.rawValue, "Performance")
        XCTAssertEqual(FanControlMode.quiet.rawValue, "Quiet")
    }

    func testFanControlMode_fromStoredString() {
        XCTAssertEqual(FanControlMode(fromStoredString: "Auto"), .auto)
        XCTAssertEqual(FanControlMode(fromStoredString: "Performance"), .performance)
        XCTAssertEqual(FanControlMode(fromStoredString: "Quiet"), .quiet)
        XCTAssertEqual(FanControlMode(fromStoredString: "Manual"), .performance) // Legacy mapping
        XCTAssertNil(FanControlMode(fromStoredString: "Invalid"))
    }

    func testFanControlMode_allCases() {
        XCTAssertEqual(FanControlMode.allCases, [.auto, .performance, .quiet])
    }

    // MARK: - Constants validation

    func testConstants_chargeLimitRange() {
        XCTAssertEqual(Constants.minChargeLimit, 20)
        XCTAssertEqual(Constants.maxChargeLimit, 100)
        XCTAssertTrue(Constants.minChargeLimit < Constants.maxChargeLimit)
    }

    func testConstants_sailingRange() {
        XCTAssertEqual(Constants.minSailingRange, 3)
        XCTAssertEqual(Constants.maxSailingRange, 10)
        XCTAssertTrue(Constants.minSailingRange < Constants.maxSailingRange)
    }

    func testConstants_temperatureThresholds() {
        XCTAssertTrue(Constants.defaultWarmTemperatureThreshold < Constants.defaultHotTemperatureThreshold)
        XCTAssertTrue(Constants.minWarmTemperatureThreshold < Constants.maxHotTemperatureThreshold)
    }

    func testConstants_refreshInterval() {
        XCTAssertTrue(Constants.minRefreshInterval < Constants.maxRefreshInterval)
        XCTAssertTrue(Constants.defaultRefreshInterval >= Constants.minRefreshInterval)
        XCTAssertTrue(Constants.defaultRefreshInterval <= Constants.maxRefreshInterval)
    }
}
