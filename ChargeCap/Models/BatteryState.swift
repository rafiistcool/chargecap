import Foundation

/// Battery health condition as reported by IOKit.
enum BatteryCondition: String, Equatable {
    case normal = "Normal"
    case serviceRecommended = "Service Recommended"
    case replaceSoon = "Replace Soon"
    case replaceNow = "Replace Now"
    case poor = "Poor"
    case unknown = "Unknown"

    /// Initialises from the raw string value returned by IOKit (kIOPSBatteryHealthConditionKey).
    init(ioKitString: String?) {
        switch ioKitString {
        case "Normal":               self = .normal
        case "Service Recommended":  self = .serviceRecommended
        case "Replace Soon":         self = .replaceSoon
        case "Replace Now":          self = .replaceNow
        case "Poor":                 self = .poor
        default:                     self = .unknown
        }
    }
}

/// Data model representing the current state of the battery.
struct BatteryState: Equatable {
    // MARK: - Basic status

    /// Current charge level as a percentage (0–100).
    var chargePercent: Int

    /// Whether the battery is currently charging.
    var isCharging: Bool

    /// Whether the MacBook is plugged in to AC power.
    var isPluggedIn: Bool

    /// Current charge limit set by ChargeCap (nil = no limit / Pro feature).
    var chargeLimit: Int?

    /// Instantaneous battery rate from SMC when available.
    var batteryRate: Int?

    /// Live system load from AppleSmartBattery power telemetry, in milliwatts.
    var systemLoadMilliwatts: Int?

    /// Live battery power from AppleSmartBattery power telemetry, in milliwatts.
    /// Positive values mean charging; negative values mean discharging.
    var batteryPowerMilliwatts: Int?

    // MARK: - Time estimates

    /// Minutes until fully charged (valid only when charging; 0 if unavailable).
    var timeToFull: Int

    /// Minutes until empty (valid only when on battery; 0 if unavailable).
    var timeToEmpty: Int

    // MARK: - Health

    /// Battery health as a percentage of original capacity (0–100).
    var healthPercent: Int

    /// Battery condition string reported by IOKit.
    var condition: BatteryCondition

    // MARK: - Cycle count

    /// Number of full charge cycles completed.
    var cycleCount: Int

    /// Maximum recommended cycle count for this Mac model.
    var maxCycleCount: Int

    // MARK: - Hardware details

    /// Battery temperature in degrees Celsius.
    var temperature: Double

    /// Design (original) capacity in mAh.
    var designCapacity: Int

    /// Current maximum (full-charge) capacity in mAh.
    var maxCapacity: Int

    /// AC adapter wattage (0 if not connected or unavailable).
    var adapterWattage: Int

    /// Whether charge limiting is currently inhibiting charging.
    var isChargeInhibited: Bool

    // MARK: - Availability

    /// True for MacBooks; false for desktop Macs that have no battery.
    var hasBattery: Bool

    // MARK: - Derived UI helpers

    /// SF Symbol name that best represents the current battery state.
    var batteryIconName: String {
        guard hasBattery else { return "desktopcomputer" }
        if isCharging { return "battery.100.bolt" }
        switch chargePercent {
        case 76...100: return "battery.100"
        case 51...75:  return "battery.75"
        case 26...50:  return "battery.50"
        case 1...25:   return "battery.25"
        default:       return "battery.0"
        }
    }

    /// The best available live battery power reading, preferring IORegistry telemetry
    /// and falling back to the SMC battery rate when telemetry is unavailable.
    var liveBatteryPowerMilliwatts: Int? {
        batteryPowerMilliwatts ?? batteryRate
    }

    /// The best available system load reading in milliwatts.
    /// When the Mac is discharging and only the battery power is known, use the
    /// battery draw as a practical fallback for system load.
    var liveSystemLoadMilliwatts: Int? {
        if let systemLoadMilliwatts, systemLoadMilliwatts > 0 {
            return systemLoadMilliwatts
        }

        guard !isPluggedIn, let liveBatteryPowerMilliwatts else { return nil }
        return abs(liveBatteryPowerMilliwatts)
    }

    var batteryChargingWatts: Double? {
        guard let liveBatteryPowerMilliwatts, liveBatteryPowerMilliwatts > 0 else { return nil }
        return Double(liveBatteryPowerMilliwatts) / 1000.0
    }

    var adapterInputWatts: Double? {
        guard isPluggedIn, adapterWattage > 0 else { return nil }
        return Double(adapterWattage)
    }

    var batteryDischargingWatts: Double? {
        guard let liveBatteryPowerMilliwatts, liveBatteryPowerMilliwatts < 0 else { return nil }
        return Double(abs(liveBatteryPowerMilliwatts)) / 1000.0
    }

    var systemLoadWatts: Double? {
        guard let liveSystemLoadMilliwatts, liveSystemLoadMilliwatts > 0 else { return nil }
        return Double(liveSystemLoadMilliwatts) / 1000.0
    }

    /// A safer charging-power estimate for UI.
    ///
    /// On some Macs, the "BatteryPower" telemetry can mirror the adapter's full
    /// input power instead of net battery charging power. When that happens,
    /// derive battery charging power from the remaining adapter budget after the
    /// current system load.
    var resolvedBatteryChargingWatts: Double? {
        let measuredBatteryChargingWatts = batteryChargingWatts

        guard isPluggedIn else {
            return measuredBatteryChargingWatts
        }

        if let adapterInputWatts, let systemLoadWatts {
            let remainingAdapterWatts = max(adapterInputWatts - systemLoadWatts, 0)

            if let measuredBatteryChargingWatts {
                let exceedsAdapterBudget = measuredBatteryChargingWatts + systemLoadWatts > adapterInputWatts * 1.05
                let suspiciouslyMatchesAdapter = measuredBatteryChargingWatts >= adapterInputWatts * 0.95

                if exceedsAdapterBudget || suspiciouslyMatchesAdapter {
                    return remainingAdapterWatts
                }
            }

            return measuredBatteryChargingWatts ?? remainingAdapterWatts
        }

        if let measuredBatteryChargingWatts, let adapterInputWatts,
           measuredBatteryChargingWatts >= adapterInputWatts * 0.95 {
            return nil
        }

        return measuredBatteryChargingWatts
    }

    init(
        chargePercent: Int,
        isCharging: Bool,
        isPluggedIn: Bool,
        chargeLimit: Int?,
        batteryRate: Int?,
        systemLoadMilliwatts: Int? = nil,
        batteryPowerMilliwatts: Int? = nil,
        timeToFull: Int,
        timeToEmpty: Int,
        healthPercent: Int,
        condition: BatteryCondition,
        cycleCount: Int,
        maxCycleCount: Int,
        temperature: Double,
        designCapacity: Int,
        maxCapacity: Int,
        adapterWattage: Int,
        isChargeInhibited: Bool,
        hasBattery: Bool
    ) {
        self.chargePercent = chargePercent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.chargeLimit = chargeLimit
        self.batteryRate = batteryRate
        self.systemLoadMilliwatts = systemLoadMilliwatts
        self.batteryPowerMilliwatts = batteryPowerMilliwatts
        self.timeToFull = timeToFull
        self.timeToEmpty = timeToEmpty
        self.healthPercent = healthPercent
        self.condition = condition
        self.cycleCount = cycleCount
        self.maxCycleCount = maxCycleCount
        self.temperature = temperature
        self.designCapacity = designCapacity
        self.maxCapacity = maxCapacity
        self.adapterWattage = adapterWattage
        self.isChargeInhibited = isChargeInhibited
        self.hasBattery = hasBattery
    }

    // MARK: - Static instances

    static let placeholder = BatteryState(
        chargePercent: 75,
        isCharging: true,
        isPluggedIn: true,
        chargeLimit: nil,
        batteryRate: 0,
        systemLoadMilliwatts: 12_700,
        batteryPowerMilliwatts: 4_100,
        timeToFull: 65,
        timeToEmpty: 0,
        healthPercent: 94,
        condition: .normal,
        cycleCount: 312,
        maxCycleCount: 1000,
        temperature: 38.0,
        designCapacity: 5103,
        maxCapacity: 4797,
        adapterWattage: 61,
        isChargeInhibited: false,
        hasBattery: true
    )

    static let noBattery = BatteryState(
        chargePercent: 0,
        isCharging: false,
        isPluggedIn: true,
        chargeLimit: nil,
        batteryRate: nil,
        systemLoadMilliwatts: nil,
        batteryPowerMilliwatts: nil,
        timeToFull: 0,
        timeToEmpty: 0,
        healthPercent: 0,
        condition: .unknown,
        cycleCount: 0,
        maxCycleCount: 0,
        temperature: 0,
        designCapacity: 0,
        maxCapacity: 0,
        adapterWattage: 0,
        isChargeInhibited: false,
        hasBattery: false
    )
}
