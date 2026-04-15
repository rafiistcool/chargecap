import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: ChargeController
    @EnvironmentObject private var helperManager: PrivilegedHelperManager
    @EnvironmentObject private var proManager: ProManager

    var body: some View {
        Form {
            proSection
            chargeLimitingSection
            heatProtectionSection
            schedulingSection
            helperSection
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 430, height: 560)
    }

    private var proSection: some View {
        Section("ChargeCap Pro") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(proManager.hasUnlockedPro ? "Pro unlocked" : "Unlock Pro")
                        .font(.headline)
                    Text(proDescription)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if proManager.hasUnlockedPro {
                    Label("Active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(proButtonTitle) {
                        Task {
                            await proManager.purchasePro()
                        }
                    }
                    .disabled(proManager.isLoading)
                }
            }

            if !proManager.hasUnlockedPro {
                Button("Restore Purchases") {
                    Task {
                        await proManager.restorePurchases()
                    }
                }
                .buttonStyle(.link)
            }

            #if DEBUG
            Toggle("Debug unlock Pro", isOn: Binding(
                get: { proManager.hasUnlockedPro },
                set: { proManager.setDebugProOverride($0) }
            ))
            #endif

            if case .failed(let message) = proManager.purchaseState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var chargeLimitingSection: some View {
        Section("Charge Limiting") {
            Toggle(
                "Enable charge limiting",
                isOn: Binding(
                    get: { controller.state.isEnabled && proManager.hasUnlockedPro },
                    set: { controller.setChargeLimitingEnabled($0) }
                )
            )
            .disabled(!proManager.hasUnlockedPro)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Target limit")
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
                    step: 1
                )
                .disabled(!proManager.hasUnlockedPro)
            }

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
                .disabled(!proManager.hasUnlockedPro)
            }

            statusRow(title: "Status", value: controller.state.status.description)
            statusRow(title: "Resume at", value: "\(controller.state.resumeThreshold)%")
        }
    }

    private var heatProtectionSection: some View {
        Section("Heat Protection") {
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
                .disabled(!proManager.hasUnlockedPro)
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
                .disabled(!proManager.hasUnlockedPro)
            }
        }
    }

    private var schedulingSection: some View {
        Section("Charge Scheduling") {
            Toggle(
                "Charge to 100% before schedule",
                isOn: Binding(
                    get: { controller.schedule.isEnabled },
                    set: { controller.updateScheduleEnabled($0) }
                )
            )
            .disabled(!proManager.hasUnlockedPro)

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
        }
    }

    private var helperSection: some View {
        Section("Privileged Helper") {
            statusRow(title: "Helper", value: helperManager.isInstalled ? "Installed" : "Not installed")

            if let error = helperManager.lastErrorDescription, !helperManager.isInstalled {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(helperManager.isInstalled ? "Reinstall Helper" : "Install Helper") {
                Task {
                    await controller.installHelper()
                }
            }
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private var proDescription: String {
        if let product = proManager.product {
            return "Charge limiting, sailing mode, heat protection, and scheduling. \(product.displayPrice) one-time purchase."
        }

        return "Charge limiting, sailing mode, heat protection, and scheduling. \(Constants.Pro.price) one-time purchase."
    }

    private var proButtonTitle: String {
        if let product = proManager.product {
            return "Buy Pro \(product.displayPrice)"
        }

        return "Buy Pro \(Constants.Pro.price)"
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
