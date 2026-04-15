import Combine
import Foundation
import IOKit
import IOKit.ps

/// Reads battery information from IOKit and the IORegistry, refreshing every 30 seconds.
final class BatteryMonitor: ObservableObject {
    @Published private(set) var batteryState: BatteryState

    private var timer: AnyCancellable?

    init() {
        batteryState = BatteryState.placeholder
        refresh()
        timer = Timer.publish(every: Constants.refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    /// Refresh battery state from the system on a background thread.
    func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            let state = Self.readBatteryState()
            await MainActor.run { self?.batteryState = state }
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

        var chargePercent = 0
        var isCharging    = false
        var isPluggedIn   = false
        var timeToFull    = 0
        var timeToEmpty   = 0
        var condition     = BatteryCondition.unknown
        var hasBattery    = false

        for source in sourcesList {
            guard
                let desc = IOPSGetPowerSourceDescription(rawInfo, source)?
                    .takeUnretainedValue() as? [String: Any],
                let type = desc[kIOPSTypeKey] as? String,
                type == kIOPSInternalBatteryType
            else { continue }

            hasBattery    = true
            chargePercent = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            isCharging    = desc[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn   = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            timeToFull    = desc[kIOPSTimeToFullChargeKey] as? Int ?? 0
            timeToEmpty   = desc[kIOPSTimeToEmptyKey] as? Int ?? 0
            condition     = BatteryCondition(ioKitString: desc[kIOPSBatteryHealthConditionKey] as? String)
            break
        }

        guard hasBattery else { return .noBattery }

        // ── 2. IORegistry — AppleSmartBattery ────────────────────────────────
        var cycleCount      = 0
        var designCapacity  = 0
        var maxCapacity     = 0
        var temperature     = 0.0
        var healthPercent   = 100
        var adapterWattage  = 0

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
                cycleCount     = intValue(in: dict, forKeys: ["CycleCount"]) ?? 0
                designCapacity = intValue(in: dict, forKeys: ["DesignCapacity"]) ?? 0
                maxCapacity    = resolvedMaxCapacity(in: dict, designCapacity: designCapacity)

                // Temperature is stored in centidegrees Celsius (e.g. 3800 → 38.00 °C)
                let tempRaw = intValue(in: dict, forKeys: ["Temperature"]) ?? 0
                temperature = Double(tempRaw) / 100.0

                healthPercent = resolvedHealthPercent(
                    in: dict,
                    designCapacity: designCapacity,
                    maxCapacity: maxCapacity
                )

                if let adapterDict = dict["AdapterDetails"] as? [String: Any],
                   let watts = intValue(in: adapterDict, forKeys: ["Watts"])
                {
                    adapterWattage = watts
                }
            }
        }

        // ── 3. Model-specific max cycle count ────────────────────────────────
        let maxCycleCount = modelMaxCycleCount()

        return BatteryState(
            chargePercent:  chargePercent,
            isCharging:     isCharging,
            isPluggedIn:    isPluggedIn,
            chargeLimit:    nil,
            // IOKit returns -1 for time values when the estimate is still calculating;
            // max(0, ...) converts that sentinel to 0 (meaning "unavailable").
            timeToFull:     max(0, timeToFull),
            timeToEmpty:    max(0, timeToEmpty),
            healthPercent:  healthPercent,
            condition:      condition,
            cycleCount:     cycleCount,
            maxCycleCount:  maxCycleCount,
            temperature:    temperature,
            designCapacity: designCapacity,
            maxCapacity:    maxCapacity,
            adapterWattage: adapterWattage,
            hasBattery:     true
        )
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

    private static func intValue(in dict: [String: Any], forKeys keys: [String]) -> Int? {
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

    private static func resolvedMaxCapacity(in dict: [String: Any], designCapacity: Int) -> Int {
        let reportedMaxCapacity = intValue(in: dict, forKeys: ["MaxCapacity"])
        let rawMaxCapacity = intValue(in: dict, forKeys: ["AppleRawMaxCapacity"])
        let nominalChargeCapacity = intValue(in: dict, forKeys: ["NominalChargeCapacity"])

        let candidates = [rawMaxCapacity, reportedMaxCapacity, nominalChargeCapacity]
            .compactMap { $0 }
            .filter { candidate in
                candidate > 100 && (designCapacity == 0 || candidate <= designCapacity * 2)
            }

        if let bestCandidate = candidates.first {
            return bestCandidate
        }

        let fallbackPercent =
            intValue(in: dict, forKeys: ["MaximumCapacityPercent"]) ??
            reportedMaxCapacity.flatMap { (1...100).contains($0) ? $0 : nil }

        guard designCapacity > 0, let fallbackPercent, fallbackPercent > 0 else { return 0 }
        return Int((Double(designCapacity) * Double(fallbackPercent) / 100.0).rounded())
    }

    private static func resolvedHealthPercent(
        in dict: [String: Any],
        designCapacity: Int,
        maxCapacity: Int
    ) -> Int {
        if let healthPercent = intValue(in: dict, forKeys: ["MaximumCapacityPercent"]) {
            return min(100, healthPercent)
        }

        if let reportedMaxCapacity = intValue(in: dict, forKeys: ["MaxCapacity"]),
           (1...100).contains(reportedMaxCapacity)
        {
            return reportedMaxCapacity
        }

        guard designCapacity > 0, maxCapacity > 0 else { return 100 }
        return min(100, Int((Double(maxCapacity) / Double(designCapacity) * 100.0).rounded()))
    }
}
