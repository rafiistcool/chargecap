import SwiftUI

@main
struct ChargeCapApp: App {
    @StateObject private var batteryMonitor = BatteryMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(batteryMonitor)
        } label: {
            HStack(spacing: 2) {
                let state = batteryMonitor.batteryState
                Image(systemName: state.batteryIconName)
                if state.hasBattery {
                    Text("\(state.chargePercent)%")
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
