import SwiftUI

struct ProxyMenuBarLabel: View {
    let isRunning: Bool

    var body: some View {
        Image(systemName: isRunning ? "shield.lefthalf.filled" : "shield")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isRunning ? Color.green : Color.secondary)
            .accessibilityLabel(isRunning ? "Proxy running" : "Proxy stopped")
    }
}
