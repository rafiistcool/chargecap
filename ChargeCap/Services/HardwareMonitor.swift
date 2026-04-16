import Combine
import Darwin
import Foundation

/// Reads CPU usage, memory usage, and SMC sensor data (temperatures, fans) on a timer.
@MainActor
final class HardwareMonitor: ObservableObject {
    // MARK: - Published State

    @Published private(set) var cpuUsage: Double = 0.0
    @Published private(set) var cpuTemperature: Double = 0.0
    @Published private(set) var gpuTemperature: Double = 0.0
    @Published private(set) var fans: [FanInfo] = []
    @Published private(set) var memory: MemoryUsage = .zero
    @Published private(set) var sensors: [SensorReading] = []

    // MARK: - Dependencies

    private let helperManager: PrivilegedHelperManager

    // MARK: - Internal State

    private var timer: AnyCancellable?
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private static let refreshInterval: TimeInterval = 3

    // SMC sensor keys to query for temperatures
    private static let temperatureKeys: [(key: String, name: String)] = [
        ("TC0C", "CPU Die"),
        ("TC0P", "CPU Proximity"),
        ("GC0C", "GPU"),
        ("TB0T", "Battery"),
        ("Ts0P", "Palm Rest"),
        ("TM0P", "Memory"),
        ("TN0D", "NVMe/SSD"),
    ]

    init(helperManager: PrivilegedHelperManager) {
        self.helperManager = helperManager
        startTimer()
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

    private func refresh() async {
        // CPU usage and memory can be read in-process (no root needed)
        let cpuResult = readCPUUsage()
        let memoryResult = Self.readMemoryUsage()

        cpuUsage = cpuResult
        memory = memoryResult

        // SMC reads require the privileged helper
        guard helperManager.isInstalled else { return }

        // Read all SMC data concurrently
        async let temps = readTemperatures()
        async let fanData = readFans()

        let (tempReadings, fanReadings) = await (temps, fanData)

        sensors = tempReadings
        fans = fanReadings

        // Extract key temperatures for quick access
        if let cpuTemp = tempReadings.first(where: { $0.key == "TC0C" || $0.key == "TC0P" }) {
            cpuTemperature = cpuTemp.value
        }
        if let gpuTemp = tempReadings.first(where: { $0.key == "GC0C" }) {
            gpuTemperature = gpuTemp.value
        }
    }

    // MARK: - CPU Usage (Mach Kernel API)

    private func readCPUUsage() -> Double {
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

        guard let previous = previousCPUTicks else {
            previousCPUTicks = currentTicks
            return 0
        }

        let deltaUser = currentTicks.user - previous.user
        let deltaSystem = currentTicks.system - previous.system
        let deltaIdle = currentTicks.idle - previous.idle
        let deltaNice = currentTicks.nice - previous.nice
        let totalDelta = deltaUser + deltaSystem + deltaIdle + deltaNice

        previousCPUTicks = currentTicks

        guard totalDelta > 0 else { return 0 }

        let activeTime = Double(deltaUser + deltaSystem + deltaNice)
        return (activeTime / Double(totalDelta)) * 100.0
    }

    // MARK: - Memory Usage (Mach Kernel API)

    private static func readMemoryUsage() -> MemoryUsage {
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

    private func readTemperatures() async -> [SensorReading] {
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
                            unit: .celsius
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

    private func readFans() async -> [FanInfo] {
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

        for i in 0..<min(fanCount, 8) {
            let actualKey = "F\(i)Ac"
            let minKey = "F\(i)Mn"
            let maxKey = "F\(i)Mx"

            do {
                let rpm = try await helperManager.readSMCFloatValue(key: actualKey)
                let minRPM = (try? await helperManager.readSMCFloatValue(key: minKey)) ?? 0
                let maxRPM = (try? await helperManager.readSMCFloatValue(key: maxKey)) ?? 0

                let fan = FanInfo(
                    index: i,
                    rpm: Int(rpm.rounded()),
                    minRPM: Int(minRPM.rounded()),
                    maxRPM: Int(maxRPM.rounded())
                )
                fans.append(fan)
            } catch {
                // Fan key not readable, skip
                continue
            }
        }

        return fans
    }
}
