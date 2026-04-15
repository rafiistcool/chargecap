import Foundation

enum Constants {
    /// Minimum allowed charge limit (%).
    static let minChargeLimit = 20

    /// Maximum allowed charge limit (%).
    static let maxChargeLimit = 100

    /// Default charge limit for Pro users (%).
    static let defaultChargeLimit = 80

    /// Interval in seconds between battery state refreshes.
    static let refreshInterval: TimeInterval = 30

    enum Pro {
        static let price = "$4.99"
        static let productID = "com.chargecap.pro.lifetime"
    }
}
