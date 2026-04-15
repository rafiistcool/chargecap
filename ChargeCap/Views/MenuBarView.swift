import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var monitor: BatteryMonitor

    var body: some View {
        let state = monitor.batteryState
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            if state.hasBattery {
                chargeSection(state)
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
    private func chargeSection(_ state: BatteryState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: batteryIconName(for: state))
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
        HStack {
            Spacer()
            SettingsLink {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func batteryIconName(for state: BatteryState) -> String {
        if state.isCharging { return "battery.100.bolt" }
        switch state.chargePercent {
        case 76...100: return "battery.100"
        case 51...75:  return "battery.75"
        case 26...50:  return "battery.50"
        case 1...25:   return "battery.25"
        default:       return "battery.0"
        }
    }

    private func batteryIconColor(for state: BatteryState) -> Color {
        if state.isCharging { return .green }
        if state.chargePercent <= 20 { return .red }
        if state.chargePercent <= 40 { return .orange }
        return .primary
    }

    private func chargingStatusText(_ state: BatteryState) -> String {
        if state.chargePercent >= 100 { return "Full" }
        if state.isCharging { return "Charging" }
        if state.isPluggedIn { return "AC Power" }
        return "On Battery"
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
    MenuBarView()
        .environmentObject(BatteryMonitor())
}
