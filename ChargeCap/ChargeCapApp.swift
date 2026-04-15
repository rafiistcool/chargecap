import SwiftUI

@main
struct ChargeCapApp: App {
    @StateObject private var batteryMonitor = BatteryMonitor()
    @StateObject private var appSettings = AppSettings()
    @StateObject private var helperManager = PrivilegedHelperManager()
    @StateObject private var proManager = ProManager()
    @StateObject private var chargeController: ChargeController

    init() {
        let monitor = BatteryMonitor()
        let settings = AppSettings()
        let helperManager = PrivilegedHelperManager()
        let proManager = ProManager()

        _batteryMonitor = StateObject(wrappedValue: monitor)
        _appSettings = StateObject(wrappedValue: settings)
        _helperManager = StateObject(wrappedValue: helperManager)
        _proManager = StateObject(wrappedValue: proManager)
        _chargeController = StateObject(
            wrappedValue: ChargeController(
                monitor: monitor,
                settings: settings,
                helperManager: helperManager,
                proManager: proManager
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(batteryMonitor)
                .environmentObject(chargeController)
                .environmentObject(proManager)
        } label: {
            HStack(spacing: 2) {
                let state = batteryMonitor.batteryState
                Image(systemName: menuBarIconName)
                if state.hasBattery {
                    Text("\(state.chargePercent)%")
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(batteryMonitor)
                .environmentObject(appSettings)
                .environmentObject(helperManager)
                .environmentObject(proManager)
                .environmentObject(chargeController)
        }
    }

    private var menuBarIconName: String {
        let state = batteryMonitor.batteryState

        if chargeController.state.isLimiting {
            return chargeController.state.isSailing ? "sailboat.fill" : "bolt.slash.fill"
        }

        return state.batteryIconName
    }
}
