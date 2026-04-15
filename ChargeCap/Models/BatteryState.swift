import Foundation

/// Data model representing the current state of the battery.
struct BatteryState {
    /// Current charge level as a percentage (0–100).
    var chargePercent: Int

    /// Whether the battery is currently charging.
    var isCharging: Bool

    /// Whether the MacBook is plugged in to AC power.
    var isPluggedIn: Bool

    /// Current charge limit set by ChargeCap (nil = no limit / Pro feature).
    var chargeLimit: Int?

    static let placeholder = BatteryState(
        chargePercent: 75,
        isCharging: false,
        isPluggedIn: false,
        chargeLimit: nil
    )
}
