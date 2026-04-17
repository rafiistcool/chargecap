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
    let category: SensorCategory

    init(
        key: String,
        name: String,
        value: Double,
        unit: SensorUnit,
        category: SensorCategory = .other
    ) {
        self.key = key
        self.name = name
        self.value = value
        self.unit = unit
        self.category = category
    }

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

/// Logical grouping for a `SensorReading`, used to present readings under
/// collapsible / sectioned headings in the UI (e.g. "Performance Cores",
/// "GPU", "Battery", ...).
enum SensorCategory: String, CaseIterable {
    case efficiencyCores = "Efficiency Cores"
    case performanceCores = "Performance Cores"
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "Memory"
    case battery = "Battery"
    case storage = "Storage"
    case airflow = "Airflow"
    case chassis = "Chassis"
    case power = "Power"
    case proximity = "Proximity"
    case other = "Other"

    var systemImage: String {
        switch self {
        case .efficiencyCores: return "leaf.fill"
        case .performanceCores: return "bolt.fill"
        case .cpu:              return "cpu"
        case .gpu:              return "square.stack.3d.up.fill"
        case .memory:           return "memorychip"
        case .battery:          return "battery.100"
        case .storage:          return "internaldrive"
        case .airflow:          return "wind"
        case .chassis:          return "macbook"
        case .power:            return "bolt.fill"
        case .proximity:        return "dot.radiowaves.left.and.right"
        case .other:            return "thermometer.medium"
        }
    }

    /// Display order for sensor sections in the UI.
    var sortOrder: Int {
        switch self {
        case .efficiencyCores:  return 0
        case .performanceCores: return 1
        case .cpu:              return 2
        case .gpu:              return 3
        case .memory:           return 4
        case .storage:          return 5
        case .battery:          return 6
        case .airflow:          return 7
        case .chassis:          return 8
        case .proximity:        return 9
        case .power:            return 10
        case .other:            return 11
        }
    }
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
