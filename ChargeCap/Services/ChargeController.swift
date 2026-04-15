import Combine
import Foundation
import OSLog

@MainActor
final class ChargeController: ObservableObject {
    @Published private(set) var state: ChargeControlState

    private let monitor: BatteryMonitor
    private let settings: AppSettings
    private let helperManager: PrivilegedHelperManager
    private let proManager: ProManager
    private let calendar: Calendar
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ChargeCap", category: "ChargeController")

    private var cancellables = Set<AnyCancellable>()
    private var lastCommand: ChargeCommand?
    private var isApplyingCommand = false
    private var lastTelemetryRefresh: Date?

    init(
        monitor: BatteryMonitor,
        settings: AppSettings,
        helperManager: PrivilegedHelperManager,
        proManager: ProManager,
        calendar: Calendar = .current
    ) {
        self.monitor = monitor
        self.settings = settings
        self.helperManager = helperManager
        self.proManager = proManager
        self.calendar = calendar
        self.state = Self.makeInitialState(settings: settings)

        bind()

        Task {
            await helperManager.refreshStatus()
            evaluate(using: monitor.batteryState)
        }
    }

    func installHelper() async {
        do {
            try await helperManager.installIfNeeded()
            state.lastErrorDescription = nil
            evaluate(using: monitor.batteryState)
        } catch {
            state.lastErrorDescription = error.localizedDescription
            if state.isEnabled {
                state.status = .unavailable(error.localizedDescription)
            }
        }
    }

    func setChargeLimitingEnabled(_ enabled: Bool) {
        guard proManager.hasUnlockedPro else {
            settings.isChargeLimitingEnabled = false
            state.status = .unavailable("Charge limiting requires Pro")
            return
        }

        settings.isChargeLimitingEnabled = enabled
    }

    func updateTargetLimit(_ value: Int) {
        settings.targetChargeLimit = value
    }

    func updateSailingRange(_ value: Int) {
        settings.sailingRange = value
    }

    func updateWarmTemperatureThreshold(_ value: Int) {
        settings.warmTemperatureThreshold = value
    }

    func updateHotTemperatureThreshold(_ value: Int) {
        settings.hotTemperatureThreshold = value
    }

    func updateScheduleEnabled(_ enabled: Bool) {
        var schedule = settings.chargeSchedule
        schedule.isEnabled = enabled
        settings.chargeSchedule = schedule
    }

    func updateScheduleWeekday(_ weekday: Int) {
        var schedule = settings.chargeSchedule
        schedule.weekday = weekday
        settings.chargeSchedule = schedule
    }

    func updateScheduleTime(_ date: Date) {
        var schedule = settings.chargeSchedule
        schedule.update(from: date, calendar: calendar)
        settings.chargeSchedule = schedule
    }

    var schedule: ChargeSchedule {
        settings.chargeSchedule
    }

    private func bind() {
        monitor.$batteryState
            .receive(on: RunLoop.main)
            .sink { [weak self] (batteryState: BatteryState) in
                self?.evaluate(using: batteryState)
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            settings.$isChargeLimitingEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$targetChargeLimit.map { _ in () }.eraseToAnyPublisher(),
            settings.$sailingRange.map { _ in () }.eraseToAnyPublisher(),
            settings.$warmTemperatureThreshold.map { _ in () }.eraseToAnyPublisher(),
            settings.$hotTemperatureThreshold.map { _ in () }.eraseToAnyPublisher(),
            settings.$chargeSchedule.map { _ in () }.eraseToAnyPublisher()
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] (_: Void) in
                guard let self else { return }
                self.state = Self.state(from: self.state, settings: self.settings)
                self.evaluate(using: self.monitor.batteryState)
            }
            .store(in: &cancellables)

        proManager.$hasUnlockedPro
            .receive(on: RunLoop.main)
            .sink { [weak self] (_: Bool) in
                guard let self else { return }
                self.evaluate(using: self.monitor.batteryState)
            }
            .store(in: &cancellables)
    }

    private func evaluate(using batteryState: BatteryState) {
        state = Self.state(from: state, settings: settings)

        guard batteryState.hasBattery else {
            state.status = .unavailable("Charge limiting unavailable on this Mac")
            monitor.updateChargeMetadata(limit: nil, isChargeInhibited: false)
            enqueueCommand(.normal)
            return
        }

        guard proManager.hasUnlockedPro else {
            state.status = .unavailable("Charge limiting requires Pro")
            monitor.updateChargeMetadata(limit: nil, isChargeInhibited: false)
            enqueueCommand(.normal)
            return
        }

        guard state.isEnabled else {
            state.status = .disabled
            state.scheduledOverrideDate = nil
            monitor.updateChargeMetadata(limit: nil, isChargeInhibited: false)
            enqueueCommand(.normal)
            return
        }

        guard helperManager.isInstalled else {
            state.status = .unavailable(helperManager.lastErrorDescription ?? "Install helper to control charging")
            monitor.updateChargeMetadata(limit: state.targetLimit, isChargeInhibited: false)
            return
        }

        let nextSchedule = settings.chargeSchedule.nextTriggerDate(calendar: calendar)
        let shouldTopOff = shouldChargeToFull(batteryState: batteryState, nextSchedule: nextSchedule)

        if !shouldTopOff, let scheduledOverrideDate = state.scheduledOverrideDate, Date.now >= scheduledOverrideDate {
            state.scheduledOverrideDate = nil
        }

        if shouldTopOff {
            state.scheduledOverrideDate = nextSchedule
        } else if state.scheduledOverrideDate != nil {
            state.scheduledOverrideDate = nil
        }

        let statusAndCommand = desiredState(
            for: batteryState,
            shouldTopOffToFull: shouldTopOff,
            nextSchedule: nextSchedule
        )

        state.status = statusAndCommand.status
        monitor.updateChargeMetadata(
            limit: shouldTopOff ? 100 : state.targetLimit,
            isChargeInhibited: statusAndCommand.command != .normal
        )
        enqueueCommand(statusAndCommand.command)

        if shouldRefreshTelemetry {
            Task {
                await refreshSMCTelemetryIfAvailable()
            }
        }
    }

    private func desiredState(
        for batteryState: BatteryState,
        shouldTopOffToFull: Bool,
        nextSchedule: Date?
    ) -> (status: ChargeLimitStatus, command: ChargeCommand) {
        if let nextSchedule, shouldTopOffToFull {
            return (.scheduledTopOff(nextSchedule), .normal)
        }

        let roundedTemperature = Int(batteryState.temperature.rounded())

        if roundedTemperature >= state.hotTemperatureThreshold {
            return (.heatProtectionStopped, .inhibit)
        }

        if roundedTemperature >= state.warmTemperatureThreshold {
            return (.heatProtectionPaused, .pause)
        }

        if !batteryState.isPluggedIn {
            return (.idle, .normal)
        }

        if batteryState.chargePercent >= state.targetLimit {
            return (.limitReached, .inhibit)
        }

        if batteryState.chargePercent <= state.resumeThreshold {
            return (.chargingToLimit, .normal)
        }

        if lastCommand == .inhibit || lastCommand == .pause {
            return (.sailing, .inhibit)
        }

        return (.chargingToLimit, .normal)
    }

    private func shouldChargeToFull(batteryState: BatteryState, nextSchedule: Date?) -> Bool {
        guard let nextSchedule else { return false }
        guard batteryState.isPluggedIn else { return false }

        let now = Date.now
        guard nextSchedule > now else { return false }

        let minutesUntilSchedule = Int(nextSchedule.timeIntervalSince(now) / 60)
        let chargeNeeded = max(0, 100 - batteryState.chargePercent)

        let estimatedMinutesToFull: Int
        if batteryState.isCharging, batteryState.timeToFull > 0 {
            estimatedMinutesToFull = batteryState.timeToFull
        } else {
            estimatedMinutesToFull = chargeNeeded * Constants.scheduleFallbackMinutesPerPercent
        }

        return chargeNeeded > 0 && minutesUntilSchedule <= estimatedMinutesToFull
    }

    private func enqueueCommand(_ command: ChargeCommand) {
        guard lastCommand != command else { return }
        guard !isApplyingCommand else { return }

        isApplyingCommand = true
        Task {
            defer { isApplyingCommand = false }

            do {
                switch command {
                case .normal:
                    try await helperManager.enableCharging()
                case .inhibit:
                    try await helperManager.disableCharging()
                case .pause:
                    try await helperManager.pauseCharging()
                }

                lastCommand = command
                state.command = command
                state.lastTransitionDate = .now
                state.lastErrorDescription = nil
            } catch {
                logger.error("Failed to apply charge command: \(error.localizedDescription, privacy: .public)")
                state.lastErrorDescription = error.localizedDescription
                state.status = .unavailable(error.localizedDescription)
            }
        }
    }

    private func refreshSMCTelemetryIfAvailable() async {
        guard helperManager.isInstalled else {
            monitor.updateSMCReadings(batteryRate: nil, temperature: nil)
            return
        }

        async let batteryRate = try? helperManager.batteryRate()
        async let temperature = try? helperManager.batteryTemperatureFromSMC()

        let resolvedRate = await batteryRate.flatMap(Int.init)
        let resolvedTemperature = await temperature
        lastTelemetryRefresh = .now
        monitor.updateSMCReadings(batteryRate: resolvedRate, temperature: resolvedTemperature)
    }

    private var shouldRefreshTelemetry: Bool {
        guard let lastTelemetryRefresh else { return true }
        return Date.now.timeIntervalSince(lastTelemetryRefresh) >= Constants.refreshInterval
    }

    private static func makeInitialState(settings: AppSettings) -> ChargeControlState {
        Self.state(from: ChargeControlState.default, settings: settings)
    }

    private static func state(from state: ChargeControlState, settings: AppSettings) -> ChargeControlState {
        var nextState = state
        nextState.targetLimit = settings.targetChargeLimit
        nextState.sailingRange = settings.sailingRange
        nextState.warmTemperatureThreshold = settings.warmTemperatureThreshold
        nextState.hotTemperatureThreshold = settings.hotTemperatureThreshold
        nextState.isEnabled = settings.isChargeLimitingEnabled
        return nextState
    }
}
