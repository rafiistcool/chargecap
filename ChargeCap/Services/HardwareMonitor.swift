import Combine
import Darwin
import Foundation

// MARK: - Safe Float → Int conversion

extension Float {
    /// Converts to `Int`, returning `fallback` if the value is NaN, infinite,
    /// or outside the representable range. Prevents fatal traps on garbage SMC data.
    func safeInt(clampedTo range: ClosedRange<Int> = 0...100_000, fallback: Int = 0) -> Int {
        guard isFinite else { return fallback }
        let clamped = Swift.max(Float(range.lowerBound), Swift.min(Float(range.upperBound), self))
        return Int(clamped.rounded())
    }
}

// MARK: - SMC Reader Protocol

/// Protocol for reading SMC sensor data, enabling dependency injection and testability.
@MainActor
protocol SMCReadable: AnyObject, Sendable {
    var isInstalled: Bool { get }
    func readSMCFloatValue(key: String) async throws -> Float
    func readSMCByteValue(key: String) async throws -> UInt8
    func readSMCTemperatureValue(key: String) async throws -> Double
}

/// Reads CPU usage, memory usage, and SMC sensor data (temperatures, fans) on a timer.
@MainActor
final class HardwareMonitor: ObservableObject {
    typealias CPUTicks = (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)

    // MARK: - Published State

    @Published private(set) var cpuUsage: Double = 0.0
    @Published private(set) var cpuTemperature: Double = 0.0
    @Published private(set) var gpuTemperature: Double = 0.0
    @Published private(set) var fans: [FanInfo] = []
    @Published private(set) var memory: MemoryUsage = .zero
    @Published private(set) var sensors: [SensorReading] = []

    // MARK: - Dependencies

    private let helperManager: any SMCReadable

    // MARK: - Internal State

    private var timer: AnyCancellable?
    private var previousCPUTicks: CPUTicks?
    private static let refreshInterval: TimeInterval = 3

    // SMC sensor keys to query for temperatures.
    //
    // This list is a superset of keys seen across Intel and Apple Silicon
    // Macs (M1 / M1 Pro / M1 Max / M2 / M3 families). Keys that do not
    // exist on a given machine simply throw when read and are discarded by
    // `readTemperatures()`, so enumerating extra keys here is safe.
    //
    // Names and categories are chosen to mirror what apps like TG Pro
    // present to the user so that the Temperatures view can show detailed
    // per-component readings grouped by subsystem.
    static let temperatureKeys: [(key: String, name: String, category: SensorCategory)] = [
        // Intel-era / generic CPU + GPU die sensors
        ("TC0C", "CPU Die",           .cpu),
        ("TC0P", "CPU Proximity",     .cpu),
        ("GC0C", "GPU",               .gpu),

        // Apple Silicon efficiency cores
        ("Tp09", "Efficiency Core 1", .efficiencyCores),
        ("Tp0T", "Efficiency Core 2", .efficiencyCores),
        ("Tp0Y", "Efficiency Core 3", .efficiencyCores),
        ("Tp0Z", "Efficiency Core 4", .efficiencyCores),

        // Apple Silicon performance cores (up to M1 Max-class: 8 cores)
        ("Tp01", "Performance Core 1",  .performanceCores),
        ("Tp05", "Performance Core 2",  .performanceCores),
        ("Tp0D", "Performance Core 3",  .performanceCores),
        ("Tp0H", "Performance Core 4",  .performanceCores),
        ("Tp0L", "Performance Core 5",  .performanceCores),
        ("Tp0P", "Performance Core 6",  .performanceCores),
        ("Tp0X", "Performance Core 7",  .performanceCores),
        ("Tp0b", "Performance Core 8",  .performanceCores),
        ("Tp0f", "Performance Core 9",  .performanceCores),
        ("Tp0j", "Performance Core 10", .performanceCores),

        // Apple Silicon GPU clusters
        ("Tg05", "GPU Cluster 1", .gpu),
        ("Tg0D", "GPU Cluster 2", .gpu),
        ("Tg0L", "GPU Cluster 3", .gpu),
        ("Tg0T", "GPU Cluster 4", .gpu),

        // Memory
        ("TM0P", "Memory", .memory),

        // Battery
        ("TB0T", "Battery",                 .battery),
        ("TB1T", "Battery Gas Gauge",       .battery),
        ("TB2T", "Battery Management Unit", .battery),
        ("TB0P", "Battery Proximity",       .battery),

        // Storage
        ("TN0D", "NVMe/SSD",     .storage),
        ("TH0a", "SSD",          .storage),
        ("TH0x", "SSD (NAND I/O)", .storage),

        // Airflow
        ("TaLP", "Airflow Left",  .airflow),
        ("TaRP", "Airflow Right", .airflow),

        // Chassis / surface
        ("Ts0P", "Palm Rest",         .chassis),
        ("Ts0S", "Trackpad",          .chassis),
        ("Ts1S", "Trackpad Actuator", .chassis),

        // Power / charger
        ("TCGC", "Charger Proximity",     .power),
        ("TPCD", "Power Supply Proximity", .power),

        // Proximity (ports / wireless)
        ("TTLD", "Left Thunderbolt Ports Proximity",  .proximity),
        ("TTRD", "Right Thunderbolt Ports Proximity", .proximity),
        ("TW0P", "Wireless Proximity",                .proximity),
    ]

    init(helperManager: any SMCReadable, startMonitoring: Bool = true) {
        self.helperManager = helperManager
        if startMonitoring {
            startTimer()
        }
    }

    deinit {
        timer?.cancel()
    }

    private func startTimer() {
        // Do an initial read immediately
        Task { await refresh() }

        timer = Timer.publish(every: Self.refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refresh()
                }
            }
    }

    // MARK: - Refresh

    func refresh() async {
        // CPU usage and memory can be read in-process (no root needed)
        let cpuResult = readCPUUsage()
        let memoryResult = Self.readMemoryUsage()

        cpuUsage = cpuResult
        memory = memoryResult

        // SMC reads require the privileged helper
        guard helperManager.isInstalled else {
            cpuTemperature = 0.0
            gpuTemperature = 0.0
            fans = []
            sensors = []
            return
        }

        // Read all SMC data concurrently
        async let temps = readTemperatures()
        async let fanData = readFans()

        let (tempReadings, fanReadings) = await (temps, fanData)

        sensors = tempReadings
        fans = fanReadings

        // Extract key temperatures for quick access. On Intel Macs these
        // map to the CPU die / GPU die sensors; on Apple Silicon, the die
        // sensors don't exist, so we fall back to the hottest performance
        // core and the hottest GPU cluster respectively.
        cpuTemperature = Self.representativeCPUTemperature(from: tempReadings)
        gpuTemperature = Self.representativeGPUTemperature(from: tempReadings)
    }

    /// Returns a single representative CPU temperature from a set of
    /// sensor readings. Prefers Intel CPU die/proximity sensors when
    /// available, otherwise uses the hottest reading from the CPU /
    /// performance-core / efficiency-core categories.
    static func representativeCPUTemperature(from readings: [SensorReading]) -> Double {
        if let intelDie = readings.first(where: { $0.key == "TC0C" || $0.key == "TC0P" }) {
            return intelDie.value
        }
        let cpuReadings = readings.filter {
            $0.category == .performanceCores ||
            $0.category == .efficiencyCores ||
            $0.category == .cpu
        }
        return cpuReadings.map(\.value).max() ?? 0.0
    }

    /// Returns a single representative GPU temperature from a set of
    /// sensor readings. Prefers the Intel GPU die sensor when present,
    /// otherwise uses the hottest Apple Silicon GPU cluster.
    static func representativeGPUTemperature(from readings: [SensorReading]) -> Double {
        if let intelDie = readings.first(where: { $0.key == "GC0C" }) {
            return intelDie.value
        }
        let gpuReadings = readings.filter { $0.category == .gpu }
        return gpuReadings.map(\.value).max() ?? 0.0
    }

    // MARK: - CPU Usage (Mach Kernel API)

    func readCPUUsage() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo else { return 0 }

        defer {
            let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<Int32>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            totalSystem += UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle += UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            totalNice += UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
        }

        let currentTicks = (user: totalUser, system: totalSystem, idle: totalIdle, nice: totalNice)
        let usage = Self.calculateCPUUsage(previous: previousCPUTicks, current: currentTicks)
        previousCPUTicks = currentTicks
        return usage
    }

    static func calculateCPUUsage(previous: CPUTicks?, current: CPUTicks) -> Double {
        guard let previous else { return 0 }

        let deltaUser = current.user - previous.user
        let deltaSystem = current.system - previous.system
        let deltaIdle = current.idle - previous.idle
        let deltaNice = current.nice - previous.nice
        let totalDelta = deltaUser + deltaSystem + deltaIdle + deltaNice

        guard totalDelta > 0 else { return 0 }

        let activeTime = Double(deltaUser + deltaSystem + deltaNice)
        return (activeTime / Double(totalDelta)) * 100.0
    }

    // MARK: - Memory Usage (Mach Kernel API)

    static func readMemoryUsage() -> MemoryUsage {
        let totalRAM = ProcessInfo.processInfo.physicalMemory

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<Int32>.stride)

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryUsage(used: 0, total: totalRAM, swapUsed: 0, pressure: .nominal)
        }

        let pageSize = UInt64(vm_kernel_page_size)

        // "Used" = active + wired + compressed (matches Activity Monitor)
        let active = UInt64(vmStats.active_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let used = active + wired + compressed

        // Swap usage
        var swapInfo = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapResult = sysctlbyname("vm.swapusage", &swapInfo, &swapSize, nil, 0)
        let swapUsed: UInt64 = swapResult == 0 ? swapInfo.xsu_used : 0

        // Read actual memory pressure from the kernel instead of guessing
        let pressure: MemoryPressure = {
            var level: Int32 = 0
            var size = MemoryLayout<Int32>.size
            let rc = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
            guard rc == 0 else { return .nominal }
            // Kernel levels: 1 = normal, 2 = warning, 4 = critical
            switch level {
            case 4: return .critical
            case 2: return .warning
            default: return .nominal
            }
        }()

        return MemoryUsage(
            used: used,
            total: totalRAM,
            swapUsed: swapUsed,
            pressure: pressure
        )
    }

    // MARK: - SMC Temperature Sensors

    func readTemperatures() async -> [SensorReading] {
        var readings: [SensorReading] = []

        await withTaskGroup(of: SensorReading?.self) { group in
            for sensor in Self.temperatureKeys {
                group.addTask { [helperManager] in
                    do {
                        let temp = try await helperManager.readSMCTemperatureValue(key: sensor.key)
                        // Filter out invalid readings (0 or extreme values)
                        guard temp > -40 && temp < 150 && temp != 0 else { return nil }
                        return SensorReading(
                            key: sensor.key,
                            name: sensor.name,
                            value: temp,
                            unit: .celsius,
                            category: sensor.category
                        )
                    } catch {
                        return nil
                    }
                }
            }

            for await reading in group {
                if let reading {
                    readings.append(reading)
                }
            }
        }

        // Sort by the order defined in temperatureKeys
        let keyOrder = Dictionary(uniqueKeysWithValues: Self.temperatureKeys.enumerated().map { ($1.key, $0) })
        readings.sort { (keyOrder[$0.key] ?? 99) < (keyOrder[$1.key] ?? 99) }

        return readings
    }

    // MARK: - Fan Monitoring

    func readFans() async -> [FanInfo] {
        // First, get number of fans
        let fanCount: Int
        do {
            let count = try await helperManager.readSMCByteValue(key: "FNum")
            fanCount = Int(count)
        } catch {
            return []
        }

        guard fanCount > 0 else { return [] }

        var fans: [FanInfo] = []

        for i in 0..<fanCount {
            let actualKey = "F\(i)Ac"
            let minKey = "F\(i)Mn"
            let maxKey = "F\(i)Mx"

            do {
                let rpm = try await helperManager.readSMCFloatValue(key: actualKey)
                let minRPM = (try? await helperManager.readSMCFloatValue(key: minKey)) ?? 0
                let maxRPM = (try? await helperManager.readSMCFloatValue(key: maxKey)) ?? 0
                let minRPMValue = minRPM.safeInt()
                let maxRPMValue = maxRPM.safeInt()

                let fan = FanInfo(
                    index: i,
                    rpm: Self.clampedFanRPM(actual: rpm, minRPM: minRPM, maxRPM: maxRPM),
                    minRPM: minRPMValue,
                    maxRPM: maxRPMValue
                )
                fans.append(fan)
            } catch {
                // Fan key not readable, skip
                continue
            }
        }

        return fans
    }

    static func clampedFanRPM(actual: Float, minRPM: Float, maxRPM: Float) -> Int {
        let actualValue = actual.safeInt()
        guard actual.isFinite else { return actualValue }

        let minValue = minRPM.safeInt()
        let maxValue = maxRPM.safeInt()
        guard maxValue > 0, maxValue >= minValue else { return actualValue }

        return min(max(actualValue, minValue), maxValue)
    }
}
