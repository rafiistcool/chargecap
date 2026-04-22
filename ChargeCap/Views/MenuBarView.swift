import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    @EnvironmentObject private var controller: ChargeController
    @EnvironmentObject private var proManager: ProManager
    @EnvironmentObject private var hardwareMonitor: HardwareMonitor
    @EnvironmentObject private var telemetryRefreshCoordinator: TelemetryRefreshCoordinator
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
                cpuMonitorSection
                Divider()
                gpuMonitorSection
                Divider()
                fanMonitorSection
                Divider()
                memoryMonitorSection
                Divider()
            } else {
                Label("No battery detected.", systemImage: "desktopcomputer")
                    .foregroundStyle(.secondary)
                    .padding()
                Divider()
            }
            settingsRow
        }
        .frame(width: 320)
        .onAppear {
            telemetryRefreshCoordinator.setMenuBarVisible(true)
        }
        .onDisappear {
            telemetryRefreshCoordinator.setMenuBarVisible(false)
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Image(systemName: batteryIconName(for: state, controlState: controlState))
                        .foregroundStyle(batteryIconColor(for: state))
                    Text("\(state.chargePercent)%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                Spacer()

                Text(chargingStatusText(state))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
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

            if let powerFlow = powerFlowSnapshot(for: state) {
                powerFlowCard(powerFlow)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
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
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "mainWindow")
            } label: {
                Label("Main Window", systemImage: "macwindow")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("0", modifiers: .command)

            Button {
                NSApp.activate(ignoringOtherApps: true)
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

    // MARK: - Hardware Monitoring Sections

    private var cpuMonitorSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(.blue)
                Text("CPU")
                    .fontWeight(.medium)
                Spacer()
            }

            HStack(spacing: 6) {
                Text("Usage:")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", hardwareMonitor.cpuUsage))
                    .monospacedDigit()
                Spacer()
                usageBar(percent: hardwareMonitor.cpuUsage)
            }
            .font(.subheadline)

            if hardwareMonitor.cpuTemperature > 0 {
                HStack {
                    Text("Temp:")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f\u{00B0}C", hardwareMonitor.cpuTemperature))
                        .monospacedDigit()
                        .foregroundStyle(temperatureColor(hardwareMonitor.cpuTemperature))
                    Spacer()
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var gpuMonitorSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.purple)
                Text("GPU")
                    .fontWeight(.medium)
                Spacer()
            }

            if hardwareMonitor.gpuTemperature > 0 {
                HStack {
                    Text("Temp:")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f\u{00B0}C", hardwareMonitor.gpuTemperature))
                        .monospacedDigit()
                        .foregroundStyle(temperatureColor(hardwareMonitor.gpuTemperature))
                    Spacer()
                }
                .font(.subheadline)
            } else {
                Text("Unified with CPU (Apple Silicon)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var fanMonitorSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "fan.fill")
                    .foregroundStyle(.cyan)
                Text("Fans")
                    .fontWeight(.medium)
                Spacer()
            }

            if hardwareMonitor.fans.isEmpty {
                Text("No fans detected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(hardwareMonitor.fans) { fan in
                    HStack {
                        Text("Fan \(fan.index):")
                            .foregroundStyle(.secondary)
                        Text("\(fan.rpmFormatted) RPM")
                            .monospacedDigit()
                        Spacer()
                        if fan.maxRPM > 0 {
                            usageBar(percent: Double(fan.rpm) / Double(fan.maxRPM) * 100)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var memoryMonitorSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "memorychip")
                    .foregroundStyle(.orange)
                Text("Memory")
                    .fontWeight(.medium)
                Spacer()
            }

            HStack {
                Text(String(format: "%.1f / %.0f GB used", hardwareMonitor.memory.usedGB, hardwareMonitor.memory.totalGB))
                    .font(.subheadline)
                    .monospacedDigit()
                Spacer()
                usageBar(percent: hardwareMonitor.memory.usagePercent)
            }

            if hardwareMonitor.memory.swapUsed > 0 {
                HStack {
                    Text("Swap:")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f GB", hardwareMonitor.memory.swapUsedGB))
                        .monospacedDigit()
                    Spacer()
                }
                .font(.subheadline)
            }

            HStack {
                Text("Pressure:")
                    .foregroundStyle(.secondary)
                Text(hardwareMonitor.memory.pressure.rawValue)
                    .foregroundStyle(memoryPressureColor(hardwareMonitor.memory.pressure))
                Spacer()
            }
            .font(.subheadline)
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

    private func powerFlowSnapshot(for state: BatteryState) -> PowerFlowSnapshot? {
        if let adapterInputWatts = state.adapterInputWatts {
            var segments: [PowerFlowSegment] = []

            if let systemLoadWatts = state.systemLoadWatts, systemLoadWatts > 0 {
                segments.append(
                    PowerFlowSegment(
                        id: "system",
                        label: "System",
                        systemImage: "laptopcomputer",
                        watts: systemLoadWatts,
                        tint: Color(red: 0.50, green: 0.78, blue: 0.96),
                        colors: [
                            Color(red: 0.16, green: 0.30, blue: 0.43),
                            Color(red: 0.31, green: 0.56, blue: 0.79),
                        ]
                    )
                )
            }

            if let batteryChargingWatts = state.resolvedBatteryChargingWatts, batteryChargingWatts > 0 {
                segments.append(
                    PowerFlowSegment(
                        id: "battery",
                        label: "Battery",
                        systemImage: "battery.100",
                        watts: batteryChargingWatts,
                        tint: Color(red: 0.95, green: 0.71, blue: 0.33),
                        colors: [
                            Color(red: 0.47, green: 0.34, blue: 0.16),
                            Color(red: 0.98, green: 0.74, blue: 0.32),
                        ]
                    )
                )
            }

            let accountedWatts = segments.reduce(0) { $0 + $1.watts }
            let unallocatedWatts = max(adapterInputWatts - accountedWatts, 0)

            if unallocatedWatts > 0.5 {
                segments.append(
                    PowerFlowSegment(
                        id: "overhead",
                        label: "Other",
                        systemImage: "ellipsis.circle",
                        watts: unallocatedWatts,
                        tint: Color.secondary,
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.22),
                        ]
                    )
                )
            }

            if !segments.isEmpty {
                return PowerFlowSnapshot(
                    title: "Adapter Input",
                    totalWatts: adapterInputWatts,
                    segments: segments
                )
            }
        }

        if let systemLoadWatts = state.systemLoadWatts {
            return PowerFlowSnapshot(
                title: "System Draw",
                totalWatts: systemLoadWatts,
                segments: [
                    PowerFlowSegment(
                        id: "system",
                        label: "System",
                        systemImage: "laptopcomputer",
                        watts: systemLoadWatts,
                        tint: Color(red: 0.50, green: 0.78, blue: 0.96),
                        colors: [
                            Color(red: 0.16, green: 0.30, blue: 0.43),
                            Color(red: 0.31, green: 0.56, blue: 0.79),
                        ]
                    ),
                ]
            )
        }

        if let batteryDischargingWatts = state.batteryDischargingWatts {
            return PowerFlowSnapshot(
                title: "System Draw",
                totalWatts: batteryDischargingWatts,
                segments: [
                    PowerFlowSegment(
                        id: "system",
                        label: "System",
                        systemImage: "laptopcomputer",
                        watts: batteryDischargingWatts,
                        tint: Color(red: 0.50, green: 0.78, blue: 0.96),
                        colors: [
                            Color(red: 0.16, green: 0.30, blue: 0.43),
                            Color(red: 0.31, green: 0.56, blue: 0.79),
                        ]
                    ),
                ]
            )
        }

        return nil
    }

    private func powerFlowCard(_ snapshot: PowerFlowSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label(snapshot.title, systemImage: "bolt.horizontal.circle")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(wattsText(snapshot.totalWatts))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }

            powerFlowBar(snapshot)

            HStack(spacing: 8) {
                ForEach(snapshot.segments) { segment in
                    powerFlowChip(segment)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
    }

    private func powerFlowBar(_ snapshot: PowerFlowSnapshot) -> some View {
        GeometryReader { geometry in
            let totalWatts = max(snapshot.totalWatts, 0.001)
            let totalSpacing = CGFloat(max(snapshot.segments.count - 1, 0)) * 4
            let availableWidth = max(geometry.size.width - 8 - totalSpacing, 0)

            HStack(spacing: 4) {
                ForEach(snapshot.segments) { segment in
                    let segmentWidth = availableWidth * CGFloat(segment.watts / totalWatts)

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: segment.colors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: segmentWidth)
                        .overlay(alignment: .center) {
                            if segmentWidth > 72 {
                                Text(wattsText(segment.watts))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.16))
            )
        }
        .frame(height: 28)
    }

    private func powerFlowChip(_ segment: PowerFlowSegment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: segment.systemImage)
                .foregroundStyle(segment.tint)

            Text(segment.label)
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            Text(wattsText(segment.watts))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func wattsText(_ watts: Double) -> String {
        String(format: "%.2f W", watts)
    }

    private func usageBar(percent: Double) -> some View {
        let clampedPercent = min(100, max(0, percent))
        let filledBlocks = Int((clampedPercent / 100) * 10)

        return HStack(spacing: 1) {
            ForEach(0..<10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < filledBlocks ? barColor(for: clampedPercent) : Color.gray.opacity(0.3))
                    .frame(width: 5, height: 8)
            }
        }
    }

    private func barColor(for percent: Double) -> Color {
        if percent < 50 { return .green }
        if percent < 80 { return .yellow }
        return .red
    }

    private func temperatureColor(_ celsius: Double) -> Color {
        if celsius < 50 { return .green }
        if celsius < 80 { return .yellow }
        return .red
    }

    private func memoryPressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .nominal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

private struct PowerFlowSnapshot {
    let title: String
    let totalWatts: Double
    let segments: [PowerFlowSegment]
}

private struct PowerFlowSegment: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let watts: Double
    let tint: Color
    let colors: [Color]
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

    MenuBarView()
        .environmentObject(monitor)
        .environmentObject(controller)
        .environmentObject(proManager)
        .environmentObject(hardwareMonitor)
        .environmentObject(
            TelemetryRefreshCoordinator(
                components: [monitor, hardwareMonitor, controller],
                backgroundRefreshIntervalSeconds: Int(Constants.defaultRefreshInterval)
            )
        )
}
