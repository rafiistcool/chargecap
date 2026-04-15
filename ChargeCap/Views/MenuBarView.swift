import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    @EnvironmentObject private var controller: ChargeController
    @EnvironmentObject private var proManager: ProManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let state = monitor.batteryState
        let chargeControlState = controller.state
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            if state.hasBattery {
                chargeSection(state, controlState: chargeControlState)
                Divider()
                chargeLimitSection(state, controlState: chargeControlState)
                Divider()
                healthSection(state)
                Divider()
                cyclesAndTempSection(state)
                Divider()
                hardwareSection(state)
                Divider()
            } else {
                Label("No battery detected.", systemImage: "desktopcomputer")
                    .foregroundStyle(.secondary)
                    .padding()
                Divider()
            }
            settingsRow
        }
        .frame(width: 270)
    }

    // MARK: - Sections

    private var headerRow: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.yellow)
            Text("ChargeCap")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func chargeSection(_ state: BatteryState, controlState: ChargeControlState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: batteryIconName(for: state, controlState: controlState))
                    .foregroundStyle(batteryIconColor(for: state))
                Text("\(state.chargePercent)% — \(chargingStatusText(state))")
                    .font(.body)
                Spacer()
            }
            if let timeStr = timeRemainingString(state) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(timeStr)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func chargeLimitSection(_ state: BatteryState, controlState: ChargeControlState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: controlState.status.isSailing ? "sailboat.fill" : "bolt.badge.clock.fill")
                    .foregroundStyle(controlState.isLimiting ? .orange : .secondary)
                Text("Charge Limiting")
                Spacer()
                if proManager.hasUnlockedPro {
                    Text(controlState.isEnabled ? "On" : "Off")
                        .foregroundStyle(controlState.isEnabled ? .green : .secondary)
                } else {
                    Text("Pro")
                        .foregroundStyle(.secondary)
                }
            }

            Text(controlState.status.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let chargeLimit = state.chargeLimit {
                Text("Limit \(chargeLimit)% • Resume \(controlState.resumeThreshold)%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func healthSection(_ state: BatteryState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(healthColor(for: state.healthPercent))
                Text("Battery Health")
                Spacer()
                Text("\(state.healthPercent)%")
                    .foregroundStyle(healthColor(for: state.healthPercent))
                    .fontWeight(.semibold)
            }
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.secondary)
                Text("Condition: \(state.condition.rawValue)")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func cyclesAndTempSection(_ state: BatteryState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
                Text("Cycles")
                Spacer()
                Text("\(state.cycleCount, format: .number) / \(state.maxCycleCount, format: .number)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(.secondary)
                Text("Temperature")
                Spacer()
                Text(String(format: "%.1f°C", state.temperature))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func hardwareSection(_ state: BatteryState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.secondary)
                Text("Adapter")
                Spacer()
                Text(adapterText(state))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "square.stack")
                    .foregroundStyle(.secondary)
                Text("Design capacity")
                Spacer()
                Text("\(state.designCapacity, format: .number) mAh")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "square.stack.fill")
                    .foregroundStyle(.secondary)
                Text("Max capacity")
                Spacer()
                Text("\(state.maxCapacity, format: .number) mAh")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var settingsRow: some View {
        HStack(spacing: 12) {
            Button {
                NSApp.activate()
                openWindow(id: "settings")
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func batteryIconColor(for state: BatteryState) -> Color {
        if state.isCharging { return .green }
        if state.chargePercent <= 20 { return .red }
        if state.chargePercent <= 40 { return .orange }
        return .green
    }

    private func chargingStatusText(_ state: BatteryState) -> String {
        if state.chargePercent >= 100 { return "Full" }
        if state.isChargeInhibited { return "Not Charging" }
        if state.isCharging { return "Charging" }
        if state.isPluggedIn { return "AC Power" }
        return "On Battery"
    }

    private func batteryIconName(for state: BatteryState, controlState: ChargeControlState) -> String {
        if controlState.isLimiting {
            return controlState.isSailing ? "battery.100.bolt.rtl" : "bolt.slash.fill"
        }

        return state.batteryIconName
    }

    private func timeRemainingString(_ state: BatteryState) -> String? {
        let minutes: Int
        let suffix: String

        if state.isCharging, state.timeToFull > 0 {
            minutes = state.timeToFull
            suffix  = "until full"
        } else if !state.isPluggedIn, state.timeToEmpty > 0 {
            minutes = state.timeToEmpty
            suffix  = "remaining"
        } else {
            return nil
        }

        let h = minutes / 60
        let m = minutes % 60
        let timeStr = h > 0 ? "\(h):\(String(format: "%02d", m))" : "\(m)m"
        return "~\(timeStr) \(suffix)"
    }

    private func healthColor(for percent: Int) -> Color {
        if percent >= 80 { return .green }
        if percent >= 60 { return .yellow }
        return .red
    }

    private func adapterText(_ state: BatteryState) -> String {
        guard state.isPluggedIn else { return "Not connected" }
        guard state.adapterWattage > 0 else { return "Connected" }
        return "\(state.adapterWattage)W USB-C"
    }
}

#Preview {
    let monitor = BatteryMonitor()
    let settings = AppSettings()
    let helperManager = PrivilegedHelperManager()
    let proManager = ProManager()
    let controller = ChargeController(
        monitor: monitor,
        settings: settings,
        helperManager: helperManager,
        proManager: proManager
    )

    MenuBarView()
        .environmentObject(monitor)
        .environmentObject(controller)
        .environmentObject(proManager)
}
