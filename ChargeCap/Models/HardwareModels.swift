import Foundation

struct FanInfo: Equatable, Identifiable {
    let index: Int
    let rpm: Int
    let minRPM: Int
    let maxRPM: Int

    var id: Int { index }

    var rpmFormatted: String {
        rpm.formatted(.number.grouping(.automatic))
    }
}

struct SensorReading: Equatable, Identifiable {
    let key: String
    let name: String
    let value: Double
    let unit: SensorUnit

    var id: String { key }

    var formattedValue: String {
        switch unit {
        case .celsius:
            return String(format: "%.1f\u{00B0}C", value)
        case .watts:
            return String(format: "%.1fW", value)
        case .rpm:
            return "\(Int(value)) RPM"
        }
    }

    var temperatureColor: TemperatureLevel {
        guard unit == .celsius else { return .normal }
        if value < 50 { return .normal }
        if value < 80 { return .warm }
        return .hot
    }
}

enum SensorUnit: String {
    case celsius
    case watts
    case rpm
}

enum TemperatureLevel {
    case normal  // Green, <50C
    case warm    // Yellow, 50-80C
    case hot     // Red, >80C
}

struct MemoryUsage: Equatable {
    let used: UInt64
    let total: UInt64
    let swapUsed: UInt64
    let pressure: MemoryPressure

    var usedGB: Double {
        Double(used) / (1024 * 1024 * 1024)
    }

    var totalGB: Double {
        Double(total) / (1024 * 1024 * 1024)
    }

    var swapUsedGB: Double {
        Double(swapUsed) / (1024 * 1024 * 1024)
    }

    var usagePercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total) * 100
    }

    static let zero = MemoryUsage(used: 0, total: 0, swapUsed: 0, pressure: .nominal)
}

enum MemoryPressure: String {
    case nominal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
}
