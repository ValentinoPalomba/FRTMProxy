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
        VStack(spacing: 18) {
            header
            tabPicker
            Divider()
                .overlay(colors.border)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if selectedTab == .device {
                        pairingSection
                    } else {
                        simulatorTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connect physical devices")
                        .font(DesignSystem.Fonts.mono(19, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Text("Genera un profilo con proxy + CA e distribuiscilo con un solo QR code.")
                        .font(DesignSystem.Fonts.sans(12, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    StatusPill(isRunning: model.isRunning, colors: colors)
                    ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors)) {
                        dismiss()
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var tabPicker: some View {
        HStack {
            Picker("Modalità", selection: $selectedTab) {
                ForEach(ConnectTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Device setup")
                .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                .foregroundStyle(colors.textSecondary)

            ViewThatFits {
                HStack(alignment: .top, spacing: 18) {
                    deviceCard
                    connectionCard
                }
                VStack(spacing: 18) {
                    deviceCard
                    connectionCard
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var simulatorTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Simulator setup")
                .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            SimulatorSetupView()
                .environmentObject(settings)
        }
        .padding(.horizontal, 20)
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dispositivo fisico")
                    .font(DesignSystem.Fonts.mono(16, weight: .bold))
                    .foregroundStyle(colors.textPrimary)
                Text("Il profilo include proxy e certificato CA per la rete selezionata.")
                    .font(DesignSystem.Fonts.sans(12, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                instructionRow(index: 1, text: "Scansiona il QR con la fotocamera/Safari e scarica il profilo.")
                instructionRow(index: 2, text: "In Impostazioni → Profilo scaricato, installa e inserisci il codice di sblocco.")
                instructionRow(index: 3, text: "Impostazioni → Generali → Info → Impostazioni certificati → abilita la fiducia della CA.")
            }

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
            } else {
                Text("URL pairing non ancora disponibile: avvia il server.")
                    .font(DesignSystem.Fonts.sans(12, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }

            Text("Il profilo configura il proxy solo per questa rete Wi‑Fi. Cambia rete → rigenera il QR.")
                .font(DesignSystem.Fonts.sans(11, weight: .medium))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(18)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.12)
        .frame(maxWidth: .infinity)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stato connessione")
                .font(DesignSystem.Fonts.mono(16, weight: .bold))
                .foregroundStyle(colors.textPrimary)
            Text("Monitor Wi‑Fi, IP e porta proxy utilizzati dal profilo.")
                .font(DesignSystem.Fonts.sans(12, weight: .medium))
                .foregroundStyle(colors.textSecondary)

            VStack(spacing: 12) {
                infoRow(icon: "wifi", title: "Wi‑Fi", value: wifiDisplay)
                infoRow(icon: "dot.radiowaves.left.and.right", title: "Mac IP", value: model.ipAddress)
                infoRow(icon: "rectangle.connected.to.line.below", title: "Proxy port", value: "\(proxyPort)")
            }

            if shouldShowSSIDOverride {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SSID non rilevato — override manuale")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                        .foregroundStyle(colors.warning)
                    TextField("Inserisci SSID", text: $model.ssidOverride)
                        .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                        .onChange(of: model.ssidOverride) { _, newValue in
                            model.setSSIDOverride(newValue)
                        }
                }
            }

            if !locationPermission.locationServicesEnabled || !locationPermission.hasWiFiSSIDAccess {
                callout(
                    "Permesso localizzazione richiesto per leggere SSID su macOS 15.3+. Abilita FRTMProxy in Impostazioni di Sistema → Privacy e sicurezza → Servizi di localizzazione.",
                    icon: "location.slash",
                    tint: colors.warning
                )
            }

            if !proxyIsRunning {
                callout(
                    "Il proxy principale è fermo: avvialo prima di testare il traffico dal device.",
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

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
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

                HStack(spacing: 10) {
                    ControlButton(
                        title: "Re-detect Wi‑Fi",
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
        .padding(18)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.12)
        .frame(maxWidth: .infinity)
    }

    private func instructionRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .padding(8)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(text)
                .font(DesignSystem.Fonts.sans(12, weight: .medium))
                .foregroundStyle(colors.textPrimary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colors.surfaceElevated)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
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

    private var wifiDisplay: String {
        let trimmed = model.detectedWiFiSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private var shouldShowSSIDOverride: Bool {
        model.detectedWiFiSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
