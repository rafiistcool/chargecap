import Combine
import Foundation
import IOKit
import IOKit.ps

/// Reads battery information from IOKit and the IORegistry using a configurable refresh interval.
final class BatteryMonitor: ObservableObject {
    struct PowerSourceSnapshot: Equatable {
        let chargePercent: Int
        let isCharging: Bool
        let isPluggedIn: Bool
        let timeToFull: Int
        let timeToEmpty: Int
        let condition: BatteryCondition
    }

    struct RegistrySnapshot: Equatable {
        let cycleCount: Int
        let designCapacity: Int
        let maxCapacity: Int
        let temperature: Double
        let healthPercent: Int
        let adapterWattage: Int

        static let empty = RegistrySnapshot(
            cycleCount: 0,
            designCapacity: 0,
            maxCapacity: 0,
            temperature: 0,
            healthPercent: 100,
            adapterWattage: 0
        )
    }

    @Published private(set) var batteryState: BatteryState

    @Published private(set) var smcBatteryRate: Int?

    @Published private(set) var smcBatteryTemperature: Double?

    @Published private(set) var isChargeInhibited = false

    @Published private(set) var activeChargeLimit: Int?

    private var timer: AnyCancellable?
    private var refreshInterval: TimeInterval = Constants.defaultRefreshInterval
    private static let percentageRange = 1...100
    private static let maxReasonableCapacityMultiplier = 2

    init(startMonitoring: Bool = true) {
        batteryState = BatteryState.placeholder
        guard startMonitoring else { return }
        refresh()
        startTimer()
    }

    private func startTimer() {
        timer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func updateRefreshInterval(seconds: Int) {
        let clampedInterval = min(Constants.maxRefreshInterval, max(Constants.minRefreshInterval, TimeInterval(seconds)))
        guard refreshInterval != clampedInterval else { return }
        refreshInterval = clampedInterval
        timer?.cancel()
        startTimer()
    }

    /// Refresh battery state from the system on a background thread.
    func refresh() {
        let currentChargeLimit = activeChargeLimit
        let currentChargeInhibited = isChargeInhibited
        let currentSMCBatteryRate = smcBatteryRate
        let currentSMCBatteryTemperature = smcBatteryTemperature

        Task.detached(priority: .utility) { [weak self] in
            let state = Self.readBatteryState()
            await self?.applyRefreshedState(
                state,
                chargeLimit: currentChargeLimit,
                isChargeInhibited: currentChargeInhibited,
                smcBatteryRate: currentSMCBatteryRate,
                smcBatteryTemperature: currentSMCBatteryTemperature
            )
        }
    }

    func updateChargeMetadata(limit: Int?, isChargeInhibited: Bool) {
        if activeChargeLimit != limit {
            activeChargeLimit = limit
        }

        if self.isChargeInhibited != isChargeInhibited {
            self.isChargeInhibited = isChargeInhibited
        }

        var nextState = batteryState
        nextState.chargeLimit = limit
        nextState.isChargeInhibited = isChargeInhibited

        if nextState != batteryState {
            batteryState = nextState
        }
    }

    func updateSMCReadings(batteryRate: Int?, temperature: Double?) {
        if smcBatteryRate != batteryRate {
            smcBatteryRate = batteryRate
        }

        if smcBatteryTemperature != temperature {
            smcBatteryTemperature = temperature
        }

        var nextState = batteryState
        nextState.batteryRate = batteryRate

        if let temperature {
            nextState.temperature = temperature
        }

        if nextState != batteryState {
            batteryState = nextState
        }
    }

    // MARK: - Private reading logic

    private static func readBatteryState() -> BatteryState {
        // ── 1. IOKit Power Sources API ──────────────────────────────────────
        guard let rawInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .noBattery
        }
        guard let rawList = IOPSCopyPowerSourcesList(rawInfo)?.takeRetainedValue() else {
            return .noBattery
        }
        let sourcesList = rawList as [CFTypeRef]

        var powerSourceSnapshot: PowerSourceSnapshot?

        for source in sourcesList {
            guard
                let desc = IOPSGetPowerSourceDescription(rawInfo, source)?
                    .takeUnretainedValue() as? [String: Any],
                let parsedDescription = parsePowerSourceDescription(desc)
            else { continue }

            powerSourceSnapshot = parsedDescription
            break
        }

        guard let powerSourceSnapshot else { return .noBattery }

        // ── 2. IORegistry — AppleSmartBattery ────────────────────────────────
        var registrySnapshot = RegistrySnapshot.empty

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )

        if service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }

            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(
                service, &props, kCFAllocatorDefault, 0
            ) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any]
            {
                registrySnapshot = parseRegistryProperties(dict)
            }
        }

        // ── 3. Model-specific max cycle count ────────────────────────────────
        return makeBatteryState(
            powerSource: powerSourceSnapshot,
            registry: registrySnapshot,
            maxCycleCount: modelMaxCycleCount()
        )
    }

    @MainActor
    private func applyRefreshedState(
        _ state: BatteryState,
        chargeLimit: Int?,
        isChargeInhibited: Bool,
        smcBatteryRate: Int?,
        smcBatteryTemperature: Double?
    ) {
        var mergedState = state
        mergedState.chargeLimit = chargeLimit
        mergedState.isChargeInhibited = isChargeInhibited
        mergedState.batteryRate = smcBatteryRate

        if let smcBatteryTemperature {
            mergedState.temperature = smcBatteryTemperature
        }

        if batteryState != mergedState {
            batteryState = mergedState
        }
    }

    /// Returns the maximum recommended battery cycle count for the current Mac model.
    /// Reference: https://support.apple.com/en-us/HT201585
    private static func modelMaxCycleCount() -> Int {
        let maxCycles: [String: Int] = [
            // Intel MacBook Pro (2019–2020)
            "MacBookPro16,1": 1000, "MacBookPro16,2": 1000,
            "MacBookPro16,3": 1000, "MacBookPro16,4": 1000,
            // Intel MacBook Pro (2018)
            "MacBookPro15,1": 1000, "MacBookPro15,2": 1000,
            "MacBookPro15,3": 1000, "MacBookPro15,4": 1000,
            // Intel MacBook Pro (2016–2017)
            "MacBookPro14,1": 1000, "MacBookPro14,2": 1000, "MacBookPro14,3": 1000,
            "MacBookPro13,1": 1000, "MacBookPro13,2": 1000, "MacBookPro13,3": 1000,
            // Intel MacBook Pro (2015)
            "MacBookPro12,1": 1000,
            "MacBookPro11,1": 1000, "MacBookPro11,2": 1000,
            "MacBookPro11,3": 1000, "MacBookPro11,4": 1000, "MacBookPro11,5": 1000,
            // M1 MacBook Pro
            "MacBookPro17,1": 1000,
            "MacBookPro18,1": 1000, "MacBookPro18,2": 1000,
            "MacBookPro18,3": 1000, "MacBookPro18,4": 1000,
            // M2 MacBook Pro
            "Mac14,5": 1000, "Mac14,6": 1000, "Mac14,7": 1000,
            "Mac14,9": 1000, "Mac14,10": 1000,
            // M3 MacBook Pro
            "Mac15,3": 1000,
            "Mac15,6": 1000, "Mac15,7": 1000,
            "Mac15,8": 1000, "Mac15,9": 1000,
            "Mac15,10": 1000, "Mac15,11": 1000,
            // MacBook Air — M1
            "MacBookAir10,1": 1000,
            // MacBook Air — M2
            "Mac14,2": 1000, "Mac14,15": 1000,
            // MacBook Air — M3
            "Mac15,12": 1000, "Mac15,13": 1000,
            // Intel MacBook Air (2018–2020)
            "MacBookAir9,1": 1000, "MacBookAir8,1": 1000, "MacBookAir8,2": 1000,
            // Intel MacBook Air (2015–2017)
            "MacBookAir7,1": 1000, "MacBookAir7,2": 1000,
            // MacBook (12-inch, 2015–2019)
            "MacBook10,1": 300, "MacBook9,1": 300, "MacBook8,1": 300,
        ]

        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return 1000 }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(cString: model)

        return maxCycles[modelString] ?? 1000
    }

    static func parsePowerSourceDescription(_ desc: [String: Any]) -> PowerSourceSnapshot? {
        guard let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType else {
            return nil
        }

        return PowerSourceSnapshot(
            chargePercent: min(100, max(0, desc[kIOPSCurrentCapacityKey] as? Int ?? 0)),
            isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false,
            isPluggedIn: (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
            // IOKit returns -1 while estimates are still calculating; treat that as unavailable.
            timeToFull: max(0, desc[kIOPSTimeToFullChargeKey] as? Int ?? 0),
            timeToEmpty: max(0, desc[kIOPSTimeToEmptyKey] as? Int ?? 0),
            condition: BatteryCondition(ioKitString: desc[kIOPSBatteryHealthConditionKey] as? String)
        )
    }

    static func parseRegistryProperties(_ dict: [String: Any]) -> RegistrySnapshot {
        let cycleCount = firstPositiveIntValueForKeys(in: dict, keys: ["CycleCount"]) ?? 0
        let designCapacity = firstPositiveIntValueForKeys(in: dict, keys: ["DesignCapacity"]) ?? 0
        let maxCapacity = resolveMaxCapacity(in: dict, designCapacity: designCapacity)

        // Temperature from AppleSmartBattery is in decikelvin (e.g. 2984 -> 298.4K -> 25.25C).
        let tempRaw = firstPositiveIntValueForKeys(in: dict, keys: ["Temperature"]) ?? 0
        let temperature = tempRaw > 0 ? Double(tempRaw) / 10.0 - 273.15 : 0

        let healthPercent = resolveHealthPercent(
            in: dict,
            designCapacity: designCapacity,
            maxCapacity: maxCapacity
        )

        let adapterWattage: Int
        if let adapterDict = dict["AdapterDetails"] as? [String: Any],
           let watts = firstPositiveIntValueForKeys(in: adapterDict, keys: ["Watts"])
        {
            adapterWattage = watts
        } else {
            adapterWattage = 0
        }

        return RegistrySnapshot(
            cycleCount: cycleCount,
            designCapacity: designCapacity,
            maxCapacity: maxCapacity,
            temperature: temperature,
            healthPercent: healthPercent,
            adapterWattage: adapterWattage
        )
    }

    static func makeBatteryState(
        powerSource: PowerSourceSnapshot,
        registry: RegistrySnapshot = .empty,
        maxCycleCount: Int
    ) -> BatteryState {
        BatteryState(
            chargePercent: powerSource.chargePercent,
            isCharging: powerSource.isCharging,
            isPluggedIn: powerSource.isPluggedIn,
            chargeLimit: nil,
            batteryRate: nil,
            timeToFull: powerSource.timeToFull,
            timeToEmpty: powerSource.timeToEmpty,
            healthPercent: registry.healthPercent,
            condition: powerSource.condition,
            cycleCount: registry.cycleCount,
            maxCycleCount: maxCycleCount,
            temperature: registry.temperature,
            designCapacity: registry.designCapacity,
            maxCapacity: registry.maxCapacity,
            adapterWattage: registry.adapterWattage,
            isChargeInhibited: false,
            hasBattery: true
        )
    }

    static func firstPositiveIntValueForKeys(in dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dict[key] as? Int, value > 0 {
                return value
            }

            if let value = dict[key] as? NSNumber, value.intValue > 0 {
                return value.intValue
            }
        }

        return nil
    }

    static func resolveMaxCapacity(in dict: [String: Any], designCapacity: Int) -> Int {
        let reportedMaxCapacity = firstPositiveIntValueForKeys(in: dict, keys: ["MaxCapacity"])
        let rawMaxCapacity = firstPositiveIntValueForKeys(in: dict, keys: ["AppleRawMaxCapacity"])
        let nominalChargeCapacity = firstPositiveIntValueForKeys(in: dict, keys: ["NominalChargeCapacity"])

        let candidates = [rawMaxCapacity, reportedMaxCapacity, nominalChargeCapacity]
            .compactMap { $0 }
            .filter { candidate in
                // Real full-charge capacities are reported in mAh and should be comfortably above 100,
                // while percentage-style fallback values sit in 1...100. The upper bound keeps clearly
                // bogus readings from being shown if the IORegistry returns an unexpected unit.
                candidate > Self.percentageRange.upperBound &&
                    (designCapacity == 0 ||
                        candidate <= designCapacity * Self.maxReasonableCapacityMultiplier)
            }

        if let bestCandidate = candidates.first {
            return bestCandidate
        }

        let fallbackPercent =
            firstPositiveIntValueForKeys(in: dict, keys: ["MaximumCapacityPercent"]) ??
            reportedMaxCapacity.flatMap { isPercentageValue($0) ? $0 : nil }

        guard designCapacity > 0, let fallbackPercent, fallbackPercent > 0 else { return 0 }
        return Int((Double(designCapacity) * Double(fallbackPercent) / 100.0).rounded())
    }

    static func resolveHealthPercent(
        in dict: [String: Any],
        designCapacity: Int,
        maxCapacity: Int
    ) -> Int {
        if let healthPercent = firstPositiveIntValueForKeys(in: dict, keys: ["MaximumCapacityPercent"]) {
            return min(100, healthPercent)
        }

        if let reportedMaxCapacity = firstPositiveIntValueForKeys(in: dict, keys: ["MaxCapacity"]),
           isPercentageValue(reportedMaxCapacity)
        {
            return reportedMaxCapacity
        }

        guard designCapacity > 0, maxCapacity > 0 else { return 100 }
        return min(100, Int((Double(maxCapacity) / Double(designCapacity) * 100.0).rounded()))
    }

    static func isPercentageValue(_ value: Int) -> Bool {
        percentageRange.contains(value)
    }
}
