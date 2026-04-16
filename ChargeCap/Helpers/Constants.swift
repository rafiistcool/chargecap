import Foundation

enum Constants {
    /// Minimum allowed charge limit (%).
    static let minChargeLimit = 20

    /// Maximum allowed charge limit (%).
    static let maxChargeLimit = 100

    /// Default charge limit for Pro users (%).
    static let defaultChargeLimit = 80

    /// Minimum allowed sailing range (%).
    static let minSailingRange = 3

    /// Maximum allowed sailing range (%).
    static let maxSailingRange = 10

    /// Default sailing range (%).
    static let defaultSailingRange = 5

    /// Default temperature threshold that pauses charging (°C).
    static let defaultWarmTemperatureThreshold = 35

    /// Default temperature threshold that fully stops charging (°C).
    static let defaultHotTemperatureThreshold = 40

    /// Minimum warm threshold users can set (°C).
    static let minWarmTemperatureThreshold = 30

    /// Maximum hot threshold users can set (°C).
    static let maxHotTemperatureThreshold = 45

    /// Fallback schedule estimate when macOS cannot provide time-to-full.
    static let scheduleFallbackMinutesPerPercent = 3

    /// Minimum interval in seconds between battery state refreshes.
    static let minRefreshInterval: TimeInterval = 1

    /// Maximum interval in seconds between battery state refreshes.
    static let maxRefreshInterval: TimeInterval = 60

    /// Default interval in seconds between battery state refreshes.
    static let defaultRefreshInterval: TimeInterval = 15

    enum Pro {
        static let price = "$4.99"
        static let productID = "com.chargecap.pro.lifetime"
    }
}
