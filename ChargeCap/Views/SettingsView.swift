import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("General") {
                Text("Settings coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}

#Preview {
    SettingsView()
}
