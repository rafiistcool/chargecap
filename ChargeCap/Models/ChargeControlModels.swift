import Foundation

enum ChargeCommand: String, Equatable {
    case normal
    case inhibit
    case pause
}

enum FanControlMode: String, Codable, CaseIterable {
    case auto = "Auto"
    case performance = "Performance"
    case quiet = "Quiet"
}

enum ChargeLimitStatus: Equatable {
    case disabled
    case unavailable(String)
    case idle
    case chargingToLimit
    case limitReached
    case sailing
    case heatProtectionPaused
    case heatProtectionStopped
    case scheduledTopOff(Date)

    var description: String {
        switch self {
        case .disabled:
            return "Charge limiting off"
        case .unavailable(let reason):
            return reason
        case .idle:
            return "Monitoring charge limit"
        case .chargingToLimit:
            return "Charging to limit"
        case .limitReached:
            return "Charge limit active"
        case .sailing:
            return "Sailing mode active"
        case .heatProtectionPaused:
            return "Heat protection slowing charge"
        case .heatProtectionStopped:
            return "Heat protection stopped charging"
        case .scheduledTopOff(let date):
            return "Charging to 100% before \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    var isLimiting: Bool {
        switch self {
        case .limitReached, .sailing, .heatProtectionPaused, .heatProtectionStopped:
            return true
        case .disabled, .unavailable, .idle, .chargingToLimit, .scheduledTopOff:
            return false
        }
    }

    var isSailing: Bool {
        if case .sailing = self {
            return true
        }

        return false
    }
}

struct ChargeSchedule: Codable, Equatable {
    var weekday: Int
    var hour: Int
    var minute: Int
    var isEnabled: Bool

    static let `default` = ChargeSchedule(weekday: 2, hour: 8, minute: 0, isEnabled: false)

    func nextTriggerDate(from now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute

        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    var timeOnlyDate: Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? .now
    }

    mutating func update(from date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        hour = components.hour ?? hour
        minute = components.minute ?? minute
    }
}

struct ChargeControlState: Equatable {
    var targetLimit: Int
    var sailingRange: Int
    var warmTemperatureThreshold: Int
    var hotTemperatureThreshold: Int
    var isEnabled: Bool
    var isSailingModeEnabled: Bool
    var isHeatProtectionEnabled: Bool
    var command: ChargeCommand
    var status: ChargeLimitStatus
    var lastTransitionDate: Date?
    var lastErrorDescription: String?
    var scheduledOverrideDate: Date?

    static let `default` = ChargeControlState(
        targetLimit: Constants.defaultChargeLimit,
        sailingRange: Constants.defaultSailingRange,
        warmTemperatureThreshold: Constants.defaultWarmTemperatureThreshold,
        hotTemperatureThreshold: Constants.defaultHotTemperatureThreshold,
        isEnabled: false,
        isSailingModeEnabled: true,
        isHeatProtectionEnabled: false,
        command: .normal,
        status: .disabled,
        lastTransitionDate: nil,
        lastErrorDescription: nil,
        scheduledOverrideDate: nil
    )

    var resumeThreshold: Int {
        guard isSailingModeEnabled else { return targetLimit }
        return max(Constants.minChargeLimit, targetLimit - sailingRange)
    }

    var isLimiting: Bool {
        status.isLimiting
    }

    var isSailing: Bool {
        status.isSailing
    }
}
