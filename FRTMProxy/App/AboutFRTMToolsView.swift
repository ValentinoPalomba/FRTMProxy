import SwiftUI

struct AboutFRTMToolsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var wifiSSID: String = "—"
    @State private var ipAddress: String = "—"
    @State private var refreshedAt: Date?

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 20, alignment: .top)], spacing: 20) {
                    aboutCard
                    networkCard
                }
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(colors.background)
        .onAppear(perform: refreshNetworkInfo)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About FRTMTools")
                .font(DesignSystem.Fonts.mono(22, weight: .bold))
                .foregroundStyle(colors.textPrimary)
            Text("All-in-one toolkit for debugging HTTPS traffic with mitmproxy, SwiftUI and plenty of quality-of-life utilities.")
                .font(DesignSystem.Fonts.sans(13, weight: .medium))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Application")
                .font(DesignSystem.Fonts.mono(16, weight: .bold))
                .foregroundStyle(colors.textPrimary)
            Text(versionString)
                .font(DesignSystem.Fonts.sans(12, weight: .medium))
                .foregroundStyle(colors.textSecondary)
            Divider()
                .overlay(colors.border.opacity(0.6))
            VStack(alignment: .leading, spacing: 6) {
                Text("Shortcuts")
                    .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                Text("• ⌘⇧K to clear captured flows\n• Manage → Device for QR pairing\n• Manage → Traffic profiles for throttling presets")
                    .font(DesignSystem.Fonts.sans(11, weight: .medium))
                    .foregroundStyle(colors.textPrimary)
            }
            Divider()
                .overlay(colors.border.opacity(0.6))
            Text("Made with ❤️ by the FRTM networking team.")
                .font(DesignSystem.Fonts.sans(11, weight: .medium))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(20)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.10)
        
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network snapshot")
                        .font(DesignSystem.Fonts.mono(16, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Text("Wifi + IP info used by device pairing and map-local tooling.")
                        .font(DesignSystem.Fonts.sans(12, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                ControlButton(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    style: .ghost(colors)
                ) {
                    refreshNetworkInfo()
                }
            }

            VStack(spacing: 12) {
                networkRow(icon: "wifi", title: "Wi‑Fi SSID", value: wifiSSID)
                networkRow(icon: "dot.radiowaves.left.and.right", title: "Mac IP", value: ipAddress)
                networkRow(icon: "rectangle.connected.to.line.below", title: "Default proxy port", value: "\(settings.defaultPort)")
            }

            if let refreshedAt {
                Text("Updated \(formattedDate(refreshedAt))")
                    .font(DesignSystem.Fonts.sans(11, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }

            Text("If Wi‑Fi is blank, grant Location permission in System Settings → Privacy & Security → Location Services.")
                .font(DesignSystem.Fonts.sans(11, weight: .medium))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(20)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.10)
    }

    private func networkRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colors.surfaceElevated)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.accent)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Fonts.sans(11, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                Text(value.isEmpty ? "—" : value)
                    .font(DesignSystem.Fonts.mono(13, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }

    private func refreshNetworkInfo() {
        wifiSSID = LocalNetworkInfo.currentWiFiSSID() ?? "—"
        ipAddress = LocalNetworkInfo.primaryIPv4Address() ?? "—"
        refreshedAt = Date()
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
