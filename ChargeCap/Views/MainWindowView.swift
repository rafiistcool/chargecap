import SwiftUI

/// Large main application window inspired by apps like TG Pro and AlDente.
///
/// Presents a sidebar with detailed sections (Overview, Battery, Temperatures,
/// Fans, System, Settings) and a rich detail pane. This complements the
/// compact menu-bar popover by giving users a full-sized surface for
/// inspecting data and changing settings.
struct MainWindowView: View {
    enum Section: String, CaseIterable, Hashable, Identifiable {
        case overview
        case battery
        case temperatures
        case fans
        case system
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview:     return "Overview"
            case .battery:      return "Battery"
            case .temperatures: return "Temperatures"
            case .fans:         return "Fans"
            case .system:       return "System"
            case .settings:     return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .overview:     return "gauge.with.dots.needle.67percent"
            case .battery:      return "battery.100"
            case .temperatures: return "thermometer.medium"
            case .fans:         return "fan.fill"
            case .system:       return "cpu"
            case .settings:     return "gear"
            }
        }
    }

    @State private var selection: Section? = .overview

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("ChargeCap")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detailView(for: selection ?? .overview)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    // MARK: - Detail

    @ViewBuilder
    private func detailView(for section: Section) -> some View {
        switch section {
        case .overview:     OverviewPane()
        case .battery:      BatteryPane()
        case .temperatures: TemperaturesPane()
        case .fans:         FansPane()
        case .system:       SystemPane()
        case .settings:     SettingsView()
        }
    }
}

// MARK: - Overview Pane

private struct OverviewPane: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    @EnvironmentObject private var controller: ChargeController
    @EnvironmentObject private var hardwareMonitor: HardwareMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                paneHeader(title: "Overview", systemImage: "gauge.with.dots.needle.67percent")

                let state = monitor.batteryState
                let controlState = controller.state

                HStack(alignment: .top, spacing: 16) {
                    InfoCard(title: "Charge", systemImage: "bolt.fill", tint: .green) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(state.chargePercent)%")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(chargingStatusText(state))
                                .foregroundStyle(.secondary)
                            if state.adapterWattage > 0, state.isPluggedIn {
                                Label("\(state.adapterWattage) W adapter", systemImage: "powerplug.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    InfoCard(title: "Battery Health", systemImage: "heart.fill", tint: healthColor(for: state.healthPercent)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(state.healthPercent)%")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(state.condition.rawValue)
                                .foregroundStyle(.secondary)
                            Text("\(state.cycleCount) / \(state.maxCycleCount) cycles")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    InfoCard(title: "Charge Control", systemImage: controlState.isSailing ? "sailboat.fill" : "bolt.badge.clock.fill", tint: controlState.isLimiting ? .orange : .secondary) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(controlState.isEnabled ? "On" : "Off")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(controlState.isEnabled ? .green : .secondary)
                            Text(controlState.status.description)
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                            if controlState.isEnabled {
                                Text("Limit \(controlState.targetLimit)% · Resume \(controlState.resumeThreshold)%")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    InfoCard(title: "CPU", systemImage: "cpu", tint: .blue) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%.0f%% usage", hardwareMonitor.cpuUsage))
                                .monospacedDigit()
                            if hardwareMonitor.cpuTemperature > 0 {
                                Text(String(format: "%.0f°C", hardwareMonitor.cpuTemperature))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    InfoCard(title: "Memory", systemImage: "memorychip", tint: .orange) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%.1f / %.0f GB", hardwareMonitor.memory.usedGB, hardwareMonitor.memory.totalGB))
                                .monospacedDigit()
                            Text("Pressure: \(hardwareMonitor.memory.pressure.rawValue)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    InfoCard(title: "Fans", systemImage: "fan.fill", tint: .cyan) {
                        VStack(alignment: .leading, spacing: 4) {
                            if hardwareMonitor.fans.isEmpty {
                                Text("No fans")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(hardwareMonitor.fans) { fan in
                                    Text("Fan \(fan.index): \(fan.rpmFormatted) RPM")
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private func chargingStatusText(_ state: BatteryState) -> String {
        if !state.hasBattery { return "No battery" }
        if state.chargePercent >= 100 { return "Full" }
        if state.isChargeInhibited { return "Not Charging" }
        if state.isCharging { return "Charging" }
        if state.isPluggedIn { return "AC Power" }
        return "On Battery"
    }

    private func healthColor(for percent: Int) -> Color {
        if percent >= 80 { return .green }
        if percent >= 60 { return .yellow }
        return .red
    }
}

// MARK: - Battery Pane

private struct BatteryPane: View {
    @EnvironmentObject private var monitor: BatteryMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                paneHeader(title: "Battery", systemImage: "battery.100")

                let state = monitor.batteryState

                if !state.hasBattery {
                    Label("No battery detected.", systemImage: "desktopcomputer")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    GroupBox("Status") {
                        DetailGrid(rows: [
                            ("Charge", "\(state.chargePercent)%"),
                            ("Charging", state.isCharging ? "Yes" : "No"),
                            ("Plugged in", state.isPluggedIn ? "Yes" : "No"),
                            ("Adapter", state.isPluggedIn ? (state.adapterWattage > 0 ? "\(state.adapterWattage) W" : "Connected") : "Not connected"),
                            ("Time to full", state.timeToFull > 0 ? formatMinutes(state.timeToFull) : "—"),
                            ("Time to empty", state.timeToEmpty > 0 ? formatMinutes(state.timeToEmpty) : "—"),
                        ])
                    }

                    GroupBox("Health") {
                        DetailGrid(rows: [
                            ("Health", "\(state.healthPercent)%"),
                            ("Condition", state.condition.rawValue),
                            ("Cycles", "\(state.cycleCount) / \(state.maxCycleCount)"),
                            ("Design capacity", "\(state.designCapacity) mAh"),
                            ("Max capacity", "\(state.maxCapacity) mAh"),
                            ("Temperature", String(format: "%.1f°C", state.temperature)),
                        ])
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Temperatures Pane

private struct TemperaturesPane: View {
    @EnvironmentObject private var hardwareMonitor: HardwareMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                paneHeader(title: "Temperatures", systemImage: "thermometer.medium")

                if hardwareMonitor.sensors.isEmpty {
                    Label("No temperature sensors available. Install the helper to enable SMC readings.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    GroupBox {
                        VStack(spacing: 0) {
                            ForEach(Array(hardwareMonitor.sensors.enumerated()), id: \.element.id) { index, reading in
                                HStack {
                                    Text(reading.name)
                                    Spacer()
                                    Image(systemName: icon(for: reading.temperatureColor))
                                        .foregroundStyle(color(for: reading.temperatureColor))
                                        .accessibilityHidden(true)
                                    Text(reading.formattedValue)
                                        .monospacedDigit()
                                        .foregroundStyle(color(for: reading.temperatureColor))
                                        .fontWeight(.semibold)
                                }
                                .padding(.vertical, 6)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(reading.name), \(reading.formattedValue), \(severityLabel(for: reading.temperatureColor))")
                                if index < hardwareMonitor.sensors.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private func color(for level: TemperatureLevel) -> Color {
        switch level {
        case .normal: return .green
        case .warm:   return .yellow
        case .hot:    return .red
        }
    }

    private func icon(for level: TemperatureLevel) -> String {
        switch level {
        case .normal: return "checkmark.circle.fill"
        case .warm:   return "exclamationmark.triangle.fill"
        case .hot:    return "flame.fill"
        }
    }

    private func severityLabel(for level: TemperatureLevel) -> String {
        switch level {
        case .normal: return "Normal"
        case .warm:   return "Warm"
        case .hot:    return "Hot"
        }
    }
}

// MARK: - Fans Pane

private struct FansPane: View {
    @EnvironmentObject private var hardwareMonitor: HardwareMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                paneHeader(title: "Fans", systemImage: "fan.fill")

                if hardwareMonitor.fans.isEmpty {
                    Label("No fans detected (Apple Silicon Macs without active cooling have none).", systemImage: "fan")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(hardwareMonitor.fans) { fan in
                        GroupBox("Fan \(fan.index)") {
                            DetailGrid(rows: [
                                ("Current", "\(fan.rpmFormatted) RPM"),
                                ("Minimum", "\(fan.minRPM) RPM"),
                                ("Maximum", "\(fan.maxRPM) RPM"),
                            ])
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }
}

// MARK: - System Pane

private struct SystemPane: View {
    @EnvironmentObject private var hardwareMonitor: HardwareMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                paneHeader(title: "System", systemImage: "cpu")

                GroupBox("CPU") {
                    DetailGrid(rows: [
                        ("Usage", String(format: "%.1f%%", hardwareMonitor.cpuUsage)),
                        ("Temperature", hardwareMonitor.cpuTemperature > 0
                            ? String(format: "%.1f°C", hardwareMonitor.cpuTemperature)
                            : "—"),
                    ])
                }

                GroupBox("GPU") {
                    DetailGrid(rows: [
                        ("Temperature", hardwareMonitor.gpuTemperature > 0
                            ? String(format: "%.1f°C", hardwareMonitor.gpuTemperature)
                            : "Unified with CPU (Apple Silicon)"),
                    ])
                }

                GroupBox("Memory") {
                    DetailGrid(rows: [
                        ("Used", String(format: "%.2f GB", hardwareMonitor.memory.usedGB)),
                        ("Total", String(format: "%.0f GB", hardwareMonitor.memory.totalGB)),
                        ("Usage", String(format: "%.0f%%", hardwareMonitor.memory.usagePercent)),
                        ("Swap", String(format: "%.2f GB", hardwareMonitor.memory.swapUsedGB)),
                        ("Pressure", hardwareMonitor.memory.pressure.rawValue),
                    ])
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }
}

// MARK: - Shared helpers

@ViewBuilder
private func paneHeader(title: String, systemImage: String) -> some View {
    HStack(spacing: 10) {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(.tint)
        Text(title)
            .font(.largeTitle)
            .fontWeight(.semibold)
        Spacer()
    }
}

private struct InfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct DetailGrid: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1)
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
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
    let hardwareMonitor = HardwareMonitor(helperManager: helperManager)

    MainWindowView()
        .environmentObject(monitor)
        .environmentObject(settings)
        .environmentObject(helperManager)
        .environmentObject(proManager)
        .environmentObject(controller)
        .environmentObject(hardwareMonitor)
}
