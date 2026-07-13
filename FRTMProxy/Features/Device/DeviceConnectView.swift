import SwiftUI
import AppKit

@MainActor
final class DeviceConnectViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var connectionURL: URL?
    @Published private(set) var ipAddress: String = "—"
    @Published private(set) var detectedWiFiSSID: String = ""
    @Published var ssidOverride: String = ""
    @Published private(set) var errorMessage: String?

    private let server = DevicePairingHTTPServer()
    private let certificateLoader = MitmproxyCertificateLoader()
    private var proxyPort: Int = 8080
    private var rootCADER: Data?
    private var refreshTask: Task<Void, Never>?

    init() {
        server.onStarted = { [weak self] info in
            Task { @MainActor in
                self?.isRunning = true
                self?.connectionURL = info.landingURL
                self?.ipAddress = info.ipAddress
                self?.detectedWiFiSSID = (info.wifiSSID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                self?.pushConfigToServer()
                self?.errorMessage = nil
            }
        }
        server.onStopped = { [weak self] in
            Task { @MainActor in
                self?.isRunning = false
            }
        }
        server.onError = { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func setProxyPort(_ port: Int) {
        proxyPort = port
        pushConfigToServer()
    }

    func start() {
        do {
            rootCADER = try certificateLoader.loadRootCADER()
            refreshWiFiSSID()
            pushConfigToServer()
            errorMessage = nil
            server.start()
            startRefreshingSSID()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        server.stop()
        stopRefreshingSSID()
        isRunning = false
        connectionURL = nil
    }

    func copyConnectionURLToClipboard() {
        guard let url = connectionURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    func refreshWiFiSSID() {
        detectedWiFiSSID = (LocalNetworkInfo.currentWiFiSSID() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setSSIDOverride(_ ssid: String) {
        ssidOverride = ssid
        pushConfigToServer()
    }

    private func pushConfigToServer() {
        server.updateConfig(
            proxyPort: proxyPort,
            rootCADER: rootCADER ?? Data(),
            wifiSSID: effectiveSSID()
        )
    }

    private func effectiveSSID() -> String? {
        let override = ssidOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        let detected = detectedWiFiSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        return detected.isEmpty ? nil : detected
    }

    private func startRefreshingSSID() {
        stopRefreshingSSID()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.refreshWiFiSSID()
                    self?.pushConfigToServer()
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopRefreshingSSID() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}

struct DeviceConnectView: View {
    let proxyPort: Int
    let proxyIsRunning: Bool

    private enum ConnectTab: String, CaseIterable, Identifiable {
        case device
        case simulator

        var id: String { rawValue }
        var title: String {
            switch self {
            case .device: return "Device"
            case .simulator: return "Simulator"
            }
        }

        var iconName: String {
            switch self {
            case .device: return "iphone.radiowaves.left.and.right"
            case .simulator: return "macwindow"
            }
        }

        var subtitle: String {
            switch self {
            case .device: return "QR profile"
            case .simulator: return "Certificate install"
            }
        }
    }

    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = DeviceConnectViewModel()
    @StateObject private var locationPermission = LocationPermissionManager.shared
    @State private var selectedTab: ConnectTab = .device

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            header
            tabPicker
            Divider()
                .overlay(colors.border)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    if selectedTab == .device {
                        pairingSection
                    } else {
                        simulatorTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DesignSystem.Spacing.sm)
            }
        }
        .frame(width: 760)
        .background(colors.background)
        .onAppear {
            locationPermission.requestWhenInUseIfNeeded()
            model.setProxyPort(proxyPort)
            model.start()
        }
        .onDisappear {
            model.stop()
        }
        .onChange(of: proxyPort) { _, newValue in
            model.setProxyPort(newValue)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Pair devices over your Wi‑Fi")
                        .font(DesignSystem.Fonts.mono(19, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Text("Generate a proxy + CA configuration profile and share it instantly via QR code.")
                        .font(DesignSystem.Fonts.sans(12, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: DesignSystem.Spacing.sm) {
                    StatusPill(isRunning: model.isRunning, colors: colors)
                    ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors)) {
                        dismiss()
                    }
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.lg)
    }

    private var tabPicker: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            ForEach(ConnectTab.allCases) { tab in
                tabButton(for: tab)
            }
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("Device setup")
                .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            deviceSection
            Divider()
                .overlay(colors.border.opacity(0.25))
            serverControlsSection
            warningsSection
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }

    private var simulatorTab: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Simulator setup")
                .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            SimulatorSetupView()
                .environmentObject(settings)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Physical device profile")
                    .font(DesignSystem.Fonts.mono(16, weight: .bold))
                    .foregroundStyle(colors.textPrimary)
                Text("Includes proxy settings and the mitmproxy CA for the detected Wi‑Fi network.")
                    .font(DesignSystem.Fonts.sans(12, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                instructionRow(index: 1, text: "Scan the QR code with Camera/Safari and download the configuration profile.")
                instructionRow(index: 2, text: "Go to Settings → Profile Downloaded, install it and confirm with the device passcode.")
                instructionRow(index: 3, text: "Trust the mitmproxy CA under Settings → General → About → Certificate Trust Settings.")
            }

            Label {
                Text("HTTPS is intercepted only after step 3. Installing the profile without enabling trust is not enough.")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(colors.warning)
            }
            .padding(DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                    .fill(colors.warning.opacity(0.14))
            )

            QRCodeView(text: model.connectionURL?.absoluteString ?? "", size: 240)
                .environmentObject(settings)

            if let urlString = model.connectionURL?.absoluteString, !urlString.isEmpty {
                Label {
                    Text(urlString)
                        .font(DesignSystem.Fonts.mono(11, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "link")
                        .foregroundStyle(colors.accent)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                        .fill(colors.surfaceElevated)
                )
            } else {
                callout(
                    "Pairing URL not available yet. Start the device server to generate the QR code.",
                    icon: "hourglass",
                    tint: colors.warning
                )
            }

            Text("Profiles are tied to the current SSID. If you switch network, restart the server to regenerate the QR code.")
                .font(DesignSystem.Fonts.sans(11, weight: .medium))
                .foregroundStyle(colors.textSecondary)

            if needsSSIDOverride {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("SSID not detected — set it manually")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                        .foregroundStyle(colors.warning)
                    TextField("Enter SSID", text: $model.ssidOverride)
                        .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                        .onChange(of: model.ssidOverride) { _, newValue in
                            model.setSSIDOverride(newValue)
                        }
                }
            }
        }
    }

    private var serverControlsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ControlButton(
                    title: model.isRunning ? "Restart server" : "Start server",
                    systemImage: "bolt.fill",
                    style: .filled(colors),
                    disabled: proxyPort < 1
                ) {
                    model.stop()
                    model.start()
                }

                ControlButton(
                    title: "Stop",
                    systemImage: "stop.fill",
                    style: .destructive(colors),
                    disabled: !model.isRunning
                ) {
                    model.stop()
                }
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                ControlButton(
                    title: "Refresh Wi‑Fi SSID",
                    systemImage: "wifi",
                    style: .ghost(colors)
                ) {
                    model.refreshWiFiSSID()
                }

                ControlButton(
                    title: "Copy URL",
                    systemImage: "link",
                    style: .ghost(colors),
                    disabled: model.connectionURL == nil
                ) {
                    model.copyConnectionURLToClipboard()
                }
            }
        }
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            if !locationPermission.locationServicesEnabled || !locationPermission.hasWiFiSSIDAccess {
                callout(
                    "Location permission is required on macOS 15.3+ to read the Wi‑Fi SSID. Enable FRTMProxy under System Settings → Privacy & Security → Location Services.",
                    icon: "location.slash",
                    tint: colors.warning
                )
            }

            if !proxyIsRunning {
                callout(
                    "The main proxy is currently stopped. Start it before redirecting traffic from the device.",
                    icon: "exclamationmark.triangle.fill",
                    tint: colors.warning
                )
            }

            if let errorMessage = model.errorMessage {
                callout(
                    errorMessage,
                    icon: "xmark.octagon.fill",
                    tint: colors.danger
                )
            }
        }
    }

    private func instructionRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Text("\(index).")
                .font(DesignSystem.Fonts.mono(12, weight: .bold))
                .foregroundStyle(colors.accent)
                .frame(width: 28, alignment: .leading)
            Text(text)
                .font(DesignSystem.Fonts.sans(12, weight: .medium))
                .foregroundStyle(colors.textPrimary)
                .lineSpacing(2)
        }
    }

    private func callout(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .padding(DesignSystem.Spacing.sm)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous))
            Text(text)
                .font(DesignSystem.Fonts.sans(12, weight: .medium))
                .foregroundStyle(colors.textPrimary)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    private var needsSSIDOverride: Bool {
        model.detectedWiFiSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func tabButton(for tab: ConnectTab) -> some View {
        let isSelected = tab == selectedTab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? colors.accent : colors.textSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text(tab.title)
                        .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                        .foregroundStyle(isSelected ? colors.textPrimary : colors.textSecondary)
                    Text(tab.subtitle)
                        .font(DesignSystem.Fonts.sans(11, weight: .medium))
                        .foregroundStyle(isSelected ? colors.accent : colors.textSecondary.opacity(0.8))
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? colors.accent : colors.border)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                    .fill(isSelected ? colors.surface : colors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                    .stroke(isSelected ? colors.accent.opacity(0.6) : colors.border.opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
