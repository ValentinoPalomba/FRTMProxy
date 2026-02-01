import SwiftUI

struct ProxyMenuBarLabel: View {
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isRunning {
                Image(systemName: "figure.mind.and.body")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating)

                Text("Proxy")
                    .font(.system(size: 12, weight: .semibold))
            } else {
                Image(systemName: "figure.mixed.cardio")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .accessibilityLabel(isRunning ? "Proxy running" : "Proxy stopped")
    }
}

