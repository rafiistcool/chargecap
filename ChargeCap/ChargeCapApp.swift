import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var helperManager: PrivilegedHelperManager?

    private var isHandlingTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isHandlingTermination else { return .terminateNow }
        guard let helperManager else { return .terminateNow }

        isHandlingTermination = true

        Task { @MainActor in
            await helperManager.resetModifiedKeys()
            sender.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
}

@main
struct ChargeCapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var batteryMonitor = BatteryMonitor()
    @StateObject private var appSettings = AppSettings()
    @StateObject private var helperManager = PrivilegedHelperManager()
    @StateObject private var proManager = ProManager()
    @StateObject private var chargeController: ChargeController
    @StateObject private var hardwareMonitor: HardwareMonitor

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
        _hardwareMonitor = StateObject(
            wrappedValue: HardwareMonitor(helperManager: helperManager)
        )

        appDelegate.helperManager = helperManager
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(batteryMonitor)
                .environmentObject(chargeController)
                .environmentObject(proManager)
                .environmentObject(hardwareMonitor)
        } label: {
            HStack(spacing: 2) {
                let state = batteryMonitor.batteryState
                Image(systemName: menuBarIconName)
                if state.hasBattery && appSettings.showPercentInMenuBar {
                    Text("\(state.chargePercent)%")
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("ChargeCap", id: "mainWindow") {
            MainWindowView()
                .environmentObject(batteryMonitor)
                .environmentObject(appSettings)
                .environmentObject(helperManager)
                .environmentObject(proManager)
                .environmentObject(chargeController)
                .environmentObject(hardwareMonitor)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 900, height: 620)
        .defaultLaunchBehavior(.suppressed)

        Window("ChargeCap Settings", id: "settings") {
            SettingsView()
                .environmentObject(batteryMonitor)
                .environmentObject(appSettings)
                .environmentObject(helperManager)
                .environmentObject(proManager)
                .environmentObject(chargeController)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }

    private var menuBarIconName: String {
        let state = batteryMonitor.batteryState

        if chargeController.state.isLimiting {
            return chargeController.state.isSailing ? "sailboat.fill" : "bolt.slash.fill"
        }

        return state.batteryIconName
    }
}
