import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("ChargeCap ⚡")
                .font(.headline)

            Text("Hello")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 200)
    }
}

#Preview {
    MenuBarView()
}
