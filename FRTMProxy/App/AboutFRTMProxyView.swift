import SwiftUI

struct AboutFRTMProxyView: View {
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
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: DesignSystem.Metrics.scaled(320)), spacing: DesignSystem.Spacing.lg, alignment: .top)], spacing: DesignSystem.Spacing.lg) {
                    aboutCard
                    networkCard
                }
                Spacer(minLength: 0)
            }
            .padding(DesignSystem.Spacing.xl)
        }
        .frame(minWidth: DesignSystem.Metrics.scaled(520), minHeight: DesignSystem.Metrics.scaled(420))
        .background(colors.background)
        .onAppear(perform: refreshNetworkInfo)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("About FRTMProxy")
                .font(DesignSystem.Fonts.title)
                .foregroundStyle(colors.textPrimary)
            Text("All-in-one toolkit for debugging HTTPS traffic with mitmproxy, SwiftUI and plenty of quality-of-life utilities.")
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Application")
                .font(DesignSystem.Fonts.heading)
                .foregroundStyle(colors.textPrimary)
            Text(versionString)
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(colors.textSecondary)
            Divider()
                .overlay(colors.border.opacity(0.6))
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Shortcuts")
                    .font(DesignSystem.Fonts.label)
                    .foregroundStyle(colors.textSecondary)
                Text("• ⌘K to open the command palette\n• ⌘⌥K to clear captured flows\n• Manage → Device for QR pairing")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textPrimary)
            }
            Divider()
                .overlay(colors.border.opacity(0.6))
            Text("Made with ❤️ by the FRTM networking team.")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.lg)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.10)
        
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Network snapshot")
                        .font(DesignSystem.Fonts.heading)
                        .foregroundStyle(colors.textPrimary)
                    Text("Wifi + IP info used by device pairing and map-local tooling.")
                        .font(DesignSystem.Fonts.body)
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

            VStack(spacing: DesignSystem.Spacing.md) {
                networkRow(icon: "wifi", title: "Wi‑Fi SSID", value: wifiSSID)
                networkRow(icon: "dot.radiowaves.left.and.right", title: "Mac IP", value: ipAddress)
                networkRow(icon: "rectangle.connected.to.line.below", title: "Default proxy port", value: "\(settings.defaultPort)")
            }

            if let refreshedAt {
                Text("Updated \(formattedDate(refreshedAt))")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
            }

            Text("If Wi‑Fi is blank, grant Location permission in System Settings → Privacy & Security → Location Services.")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.lg)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.10)
    }

    private func networkRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .fill(colors.surfaceElevated)
                .frame(width: DesignSystem.Metrics.scaled(40), height: DesignSystem.Metrics.scaled(40))
                .overlay(
                    Image(systemName: icon)
                        .font(DesignSystem.Fonts.heading)
                        .foregroundStyle(colors.accent)
                )
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(LocalizedStringKey(title))
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
                Text(value.isEmpty ? "—" : value)
                    .font(DesignSystem.Fonts.monoBody)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(value)
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
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
