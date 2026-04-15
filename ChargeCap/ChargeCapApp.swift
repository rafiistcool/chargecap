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
                Image(systemName: batteryIconName(for: batteryMonitor.batteryState))
                Text("\(batteryMonitor.batteryState.chargePercent)%")
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    // MARK: - Helpers

    private func batteryIconName(for state: BatteryState) -> String {
        guard state.hasBattery else { return "desktopcomputer" }
        if state.isCharging { return "battery.100.bolt" }
        switch state.chargePercent {
        case 76...100: return "battery.100"
        case 51...75:  return "battery.75"
        case 26...50:  return "battery.50"
        case 1...25:   return "battery.25"
        default:       return "battery.0"
        }
    }
}
