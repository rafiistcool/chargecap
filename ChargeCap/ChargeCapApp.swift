import SwiftUI

@main
struct ChargeCapApp: App {
    var body: some Scene {
        MenuBarExtra("ChargeCap", systemImage: "battery.75") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
