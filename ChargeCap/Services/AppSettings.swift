import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var isChargeLimitingEnabled: Bool {
        didSet {
            defaults.set(isChargeLimitingEnabled, forKey: Keys.isChargeLimitingEnabled)
        }
    }

    @Published var targetChargeLimit: Int {
        didSet {
            let clamped = Self.clampLimit(targetChargeLimit)
            if targetChargeLimit != clamped {
                targetChargeLimit = clamped
                return
            }

            defaults.set(targetChargeLimit, forKey: Keys.targetChargeLimit)
        }
    }

    @Published var sailingRange: Int {
        didSet {
            let clamped = Self.clampSailingRange(sailingRange)
            if sailingRange != clamped {
                sailingRange = clamped
                return
            }

            defaults.set(sailingRange, forKey: Keys.sailingRange)
        }
    }

    @Published var warmTemperatureThreshold: Int {
        didSet {
            let clamped = Self.clampWarmThreshold(warmTemperatureThreshold, hotThreshold: hotTemperatureThreshold)
            if warmTemperatureThreshold != clamped {
                warmTemperatureThreshold = clamped
                return
            }

            defaults.set(warmTemperatureThreshold, forKey: Keys.warmTemperatureThreshold)
        }
    }

    @Published var hotTemperatureThreshold: Int {
        didSet {
            let clamped = Self.clampHotThreshold(hotTemperatureThreshold, warmThreshold: warmTemperatureThreshold)
            if hotTemperatureThreshold != clamped {
                hotTemperatureThreshold = clamped
                return
            }

            defaults.set(hotTemperatureThreshold, forKey: Keys.hotTemperatureThreshold)
        }
    }

    @Published var chargeSchedule: ChargeSchedule {
        didSet {
            let sanitized = Self.sanitizeSchedule(chargeSchedule)
            if chargeSchedule != sanitized {
                chargeSchedule = sanitized
                return
            }

            if let data = try? JSONEncoder().encode(chargeSchedule) {
                defaults.set(data, forKey: Keys.chargeSchedule)
            }
        }
    }

    @Published var isSailingModeEnabled: Bool {
        didSet { defaults.set(isSailingModeEnabled, forKey: Keys.isSailingModeEnabled) }
    }

    @Published var isHeatProtectionEnabled: Bool {
        didSet { defaults.set(isHeatProtectionEnabled, forKey: Keys.isHeatProtectionEnabled) }
    }

    @Published var fanControlMode: FanControlMode {
        didSet { defaults.set(fanControlMode.rawValue, forKey: Keys.fanControlMode) }
    }

    @Published var isManualFanCurveEnabled: Bool {
        didSet { defaults.set(isManualFanCurveEnabled, forKey: Keys.isManualFanCurveEnabled) }
    }

    @Published var notifyAtChargeLimit: Bool {
        didSet { defaults.set(notifyAtChargeLimit, forKey: Keys.notifyAtChargeLimit) }
    }

    @Published var notifyOnHealthDrop: Bool {
        didSet { defaults.set(notifyOnHealthDrop, forKey: Keys.notifyOnHealthDrop) }
    }

    @Published var notifyOnTemperatureAlert: Bool {
        didSet { defaults.set(notifyOnTemperatureAlert, forKey: Keys.notifyOnTemperatureAlert) }
    }

    @Published var showPercentInMenuBar: Bool {
        didSet { defaults.set(showPercentInMenuBar, forKey: Keys.showPercentInMenuBar) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        isChargeLimitingEnabled = defaults.object(forKey: Keys.isChargeLimitingEnabled) as? Bool ?? false

        let storedLimit = defaults.object(forKey: Keys.targetChargeLimit) as? Int ?? Constants.defaultChargeLimit
        targetChargeLimit = Self.clampLimit(storedLimit)

        let storedSailingRange = defaults.object(forKey: Keys.sailingRange) as? Int ?? Constants.defaultSailingRange
        sailingRange = Self.clampSailingRange(storedSailingRange)

        let storedWarmThreshold = defaults.object(forKey: Keys.warmTemperatureThreshold) as? Int ?? Constants.defaultWarmTemperatureThreshold
        let storedHotThreshold = defaults.object(forKey: Keys.hotTemperatureThreshold) as? Int ?? Constants.defaultHotTemperatureThreshold
        let normalizedWarmThreshold = Self.clampWarmThreshold(storedWarmThreshold, hotThreshold: storedHotThreshold)
        let normalizedHotThreshold = Self.clampHotThreshold(storedHotThreshold, warmThreshold: normalizedWarmThreshold)
        warmTemperatureThreshold = normalizedWarmThreshold
        hotTemperatureThreshold = normalizedHotThreshold

        if let data = defaults.data(forKey: Keys.chargeSchedule),
           let decoded = try? JSONDecoder().decode(ChargeSchedule.self, from: data)
        {
            chargeSchedule = Self.sanitizeSchedule(decoded)
        } else {
            chargeSchedule = .default
        }

        isSailingModeEnabled = defaults.object(forKey: Keys.isSailingModeEnabled) as? Bool ?? true
        isHeatProtectionEnabled = defaults.object(forKey: Keys.isHeatProtectionEnabled) as? Bool ?? false

        if let modeRaw = defaults.string(forKey: Keys.fanControlMode),
           let mode = FanControlMode(rawValue: modeRaw)
        {
            fanControlMode = mode
        } else {
            fanControlMode = .auto
        }
        isManualFanCurveEnabled = defaults.object(forKey: Keys.isManualFanCurveEnabled) as? Bool ?? false

        notifyAtChargeLimit = defaults.object(forKey: Keys.notifyAtChargeLimit) as? Bool ?? true
        notifyOnHealthDrop = defaults.object(forKey: Keys.notifyOnHealthDrop) as? Bool ?? true
        notifyOnTemperatureAlert = defaults.object(forKey: Keys.notifyOnTemperatureAlert) as? Bool ?? false
        showPercentInMenuBar = defaults.object(forKey: Keys.showPercentInMenuBar) as? Bool ?? true
    }

    private enum Keys {
        static let isChargeLimitingEnabled = "chargeLimitingEnabled"
        static let targetChargeLimit = "targetChargeLimit"
        static let sailingRange = "sailingRange"
        static let warmTemperatureThreshold = "warmTemperatureThreshold"
        static let hotTemperatureThreshold = "hotTemperatureThreshold"
        static let chargeSchedule = "chargeSchedule"
        static let isSailingModeEnabled = "sailingModeEnabled"
        static let isHeatProtectionEnabled = "heatProtectionEnabled"
        static let fanControlMode = "fanControlMode"
        static let isManualFanCurveEnabled = "manualFanCurveEnabled"
        static let notifyAtChargeLimit = "notifyAtChargeLimit"
        static let notifyOnHealthDrop = "notifyOnHealthDrop"
        static let notifyOnTemperatureAlert = "notifyOnTemperatureAlert"
        static let showPercentInMenuBar = "showPercentInMenuBar"
    }

    private static func clampLimit(_ value: Int) -> Int {
        min(Constants.maxChargeLimit, max(Constants.minChargeLimit, value))
    }

    private static func clampSailingRange(_ value: Int) -> Int {
        min(Constants.maxSailingRange, max(Constants.minSailingRange, value))
    }

    private static func clampWarmThreshold(_ value: Int, hotThreshold: Int) -> Int {
        let upperBound = min(Constants.maxHotTemperatureThreshold - 1, hotThreshold - 1)
        return min(max(Constants.minWarmTemperatureThreshold, value), max(Constants.minWarmTemperatureThreshold, upperBound))
    }

    private static func clampHotThreshold(_ value: Int, warmThreshold: Int) -> Int {
        let minimum = max(Constants.minWarmTemperatureThreshold + 1, warmThreshold + 1)
        return min(Constants.maxHotTemperatureThreshold, max(minimum, value))
    }

    private static func sanitizeSchedule(_ schedule: ChargeSchedule) -> ChargeSchedule {
        ChargeSchedule(
            weekday: min(7, max(1, schedule.weekday)),
            hour: min(23, max(0, schedule.hour)),
            minute: min(59, max(0, schedule.minute)),
            isEnabled: schedule.isEnabled
        )
    }
}
