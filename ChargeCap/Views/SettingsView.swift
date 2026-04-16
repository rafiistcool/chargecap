import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: ChargeController
    @EnvironmentObject private var helperManager: PrivilegedHelperManager
    @EnvironmentObject private var proManager: ProManager

    @State private var isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            chargeControlSection
            fanControlSection
            alertsSection
            batteryHealthSection
            schedulingSection
            generalSection
            aboutSection
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 430, height: 680)
    }

    // MARK: - Charge Control

    private var chargeControlSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Charge limit")
                    Spacer()
                    Text("\(controller.state.targetLimit)%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(controller.state.targetLimit) },
                        set: { controller.updateTargetLimit(Int($0.rounded())) }
                    ),
                    in: Double(Constants.minChargeLimit)...Double(Constants.maxChargeLimit),
                    step: 5
                )
                .disabled(!proManager.hasUnlockedPro)
            }

            proToggle(
                "Enable charge limiting",
                isOn: Binding(
                    get: { controller.state.isEnabled && proManager.hasUnlockedPro },
                    set: { controller.setChargeLimitingEnabled($0) }
                )
            )

            proToggle(
                "Sailing mode (±\(controller.state.sailingRange)%)",
                isOn: Binding(
                    get: { controller.state.isSailingModeEnabled },
                    set: { controller.updateSailingModeEnabled($0) }
                )
            )

            if controller.state.isSailingModeEnabled && proManager.hasUnlockedPro {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sailing range")
                        Spacer()
                        Text("\(controller.state.sailingRange)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(controller.state.sailingRange) },
                            set: { controller.updateSailingRange(Int($0.rounded())) }
                        ),
                        in: Double(Constants.minSailingRange)...Double(Constants.maxSailingRange),
                        step: 1
                    )
                }
            }

            proToggle(
                "Heat protection (>\(controller.state.warmTemperatureThreshold)°C)",
                isOn: Binding(
                    get: { controller.state.isHeatProtectionEnabled },
                    set: { controller.updateHeatProtectionEnabled($0) }
                )
            )

            if controller.state.isHeatProtectionEnabled && proManager.hasUnlockedPro {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Warm threshold")
                        Spacer()
                        Text("\(controller.state.warmTemperatureThreshold)°C")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(controller.state.warmTemperatureThreshold) },
                            set: { controller.updateWarmTemperatureThreshold(Int($0.rounded())) }
                        ),
                        in: Double(Constants.minWarmTemperatureThreshold)...Double(controller.state.hotTemperatureThreshold - 1),
                        step: 1
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hot threshold")
                        Spacer()
                        Text("\(controller.state.hotTemperatureThreshold)°C")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(controller.state.hotTemperatureThreshold) },
                            set: { controller.updateHotTemperatureThreshold(Int($0.rounded())) }
                        ),
                        in: Double(controller.state.warmTemperatureThreshold + 1)...Double(Constants.maxHotTemperatureThreshold),
                        step: 1
                    )
                }
            }

            statusRow(title: "Status", value: controller.state.status.description)
        } header: {
            Label("Charge Control", systemImage: "bolt.fill")
        }
    }

    // MARK: - Fan Control

    private var fanControlSection: some View {
        Section {
            Picker(
                "Mode",
                selection: Binding(
                    get: { settings.fanControlMode },
                    set: { settings.fanControlMode = $0 }
                )
            ) {
                ForEach(FanControlMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .disabled(!proManager.hasUnlockedPro)

            proToggle(
                "Manual fan curve",
                isOn: Binding(
                    get: { settings.isManualFanCurveEnabled },
                    set: { settings.isManualFanCurveEnabled = $0 }
                )
            )
        } header: {
            Label("Fan Control", systemImage: "fan.fill")
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        Section {
            Toggle("Notify at charge limit", isOn: Binding(
                get: { settings.notifyAtChargeLimit },
                set: { settings.notifyAtChargeLimit = $0 }
            ))

            Toggle("Notify on health drop", isOn: Binding(
                get: { settings.notifyOnHealthDrop },
                set: { settings.notifyOnHealthDrop = $0 }
            ))

            Toggle("Temperature alerts", isOn: Binding(
                get: { settings.notifyOnTemperatureAlert },
                set: { settings.notifyOnTemperatureAlert = $0 }
            ))
        } header: {
            Label("Alerts", systemImage: "bell.fill")
        }
    }

    // MARK: - Battery Health

    private var batteryHealthSection: some View {
        Section {
            let state = monitor.batteryState

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Health")
                    Spacer()
                    Text("\(state.healthPercent)%")
                        .fontWeight(.semibold)
                        .foregroundStyle(healthColor(for: state.healthPercent))
                }

                ProgressView(value: Double(state.healthPercent), total: 100)
                    .tint(healthColor(for: state.healthPercent))
            }

            statusRow(
                title: "Cycles",
                value: "\(state.cycleCount.formatted()) / \(state.maxCycleCount.formatted())"
            )

            statusRow(title: "Condition", value: state.condition.rawValue)
        } header: {
            Label("Battery Health", systemImage: "heart.fill")
        }
    }

    // MARK: - Charge Scheduling

    private var schedulingSection: some View {
        Section {
            proToggle(
                "Charge to 100% before schedule",
                isOn: Binding(
                    get: { controller.schedule.isEnabled },
                    set: { controller.updateScheduleEnabled($0) }
                )
            )

            Picker(
                "Day",
                selection: Binding(
                    get: { controller.schedule.weekday },
                    set: { controller.updateScheduleWeekday($0) }
                )
            ) {
                ForEach(1...7, id: \.self) { weekday in
                    Text(weekdayName(for: weekday)).tag(weekday)
                }
            }
            .disabled(!proManager.hasUnlockedPro)

            DatePicker(
                "Time",
                selection: Binding(
                    get: { controller.schedule.timeOnlyDate },
                    set: { controller.updateScheduleTime($0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .disabled(!proManager.hasUnlockedPro)
        } header: {
            Label("Charge Scheduling", systemImage: "calendar.badge.clock")
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section {
            Toggle("Launch at login", isOn: Binding(
                get: { isLaunchAtLoginEnabled },
                set: { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        isLaunchAtLoginEnabled = newValue
                        launchAtLoginError = nil
                    } catch {
                        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
                        launchAtLoginError = error.localizedDescription
                    }
                }
            ))

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Toggle("Show % in menu bar icon", isOn: Binding(
                get: { settings.showPercentInMenuBar },
                set: { settings.showPercentInMenuBar = $0 }
            ))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Text("\(settings.refreshIntervalSeconds)s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(settings.refreshIntervalSeconds) },
                        set: { settings.refreshIntervalSeconds = Int($0.rounded()) }
                    ),
                    in: Constants.minRefreshInterval...Constants.maxRefreshInterval,
                    step: 1
                )
            }

            statusRow(
                title: "Helper",
                value: helperManager.isInstalled ? "Installed" : "Not installed"
            )

            if let error = helperManager.lastErrorDescription, !helperManager.isInstalled {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(helperManager.isInstalled ? "Reinstall Helper" : "Install Helper") {
                Task {
                    await controller.installHelper(force: helperManager.isInstalled)
                }
            }
        } header: {
            Label("General", systemImage: "gear")
        }
    }

    // MARK: - About / Footer

    private var aboutSection: some View {
        Section {
            VStack(spacing: 8) {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                Text("ChargeCap v\(version)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Built by @rafiistcool 🚀")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if proManager.hasUnlockedPro {
                    Label("Pro Active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                } else {
                    Button {
                        Task {
                            await proManager.purchasePro()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(proButtonTitle)
                            Image(systemName: "arrow.right")
                        }
                    }
                    .disabled(proManager.isLoading)

                    Button("Restore Purchases") {
                        Task {
                            await proManager.restorePurchases()
                        }
                    }
                    .buttonStyle(.link)
                    .font(.footnote)
                }

                #if DEBUG
                Toggle("Debug unlock Pro", isOn: Binding(
                    get: { proManager.hasUnlockedPro },
                    set: { proManager.setDebugProOverride($0) }
                ))
                .font(.footnote)
                #endif

                if case .failed(let message) = proManager.purchaseState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func proToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Text(title)
                if !proManager.hasUnlockedPro {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!proManager.hasUnlockedPro)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func healthColor(for percent: Int) -> Color {
        if percent >= 80 { return .green }
        if percent >= 60 { return .yellow }
        return .red
    }

    private var proButtonTitle: String {
        if let price = proManager.productDisplayPrice {
            return "Upgrade to Pro \(price)"
        }
        return "Upgrade to Pro \(Constants.Pro.price)"
    }

    private func weekdayName(for weekday: Int) -> String {
        Calendar.current.weekdaySymbols[weekday - 1]
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

    SettingsView()
        .environmentObject(monitor)
        .environmentObject(settings)
        .environmentObject(helperManager)
        .environmentObject(proManager)
        .environmentObject(controller)
}
