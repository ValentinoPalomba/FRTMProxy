import SwiftUI

struct SettingsUpstreamProxySection: View {
    @EnvironmentObject private var settings: SettingsStore
    let colors: DesignSystem.ColorPalette
    @State private var password = ""
    @State private var credentialMessage: String?

    var body: some View {
        SettingsCard(title: "Upstream Proxy", colors: colors) {
            Toggle("Enable upstream proxy", isOn: $settings.upstreamProxy.isEnabled)
                .toggleStyle(.switch)
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Picker("Protocol", selection: $settings.upstreamProxy.scheme) {
                    Text("HTTP").tag("http")
                    Text("HTTPS").tag("https")
                }
                LabeledContent("Server host") {
                    TextField("127.0.0.1", text: $settings.upstreamProxy.host)
                        .accessibilityLabel("Server host")
                }
                LabeledContent("Port") {
                    TextField("7890", text: $settings.upstreamProxy.port)
                        .accessibilityLabel("Port")
                }
                LabeledContent("Username (optional)") {
                    TextField("", text: $settings.upstreamProxy.username)
                        .accessibilityLabel("Username (optional)")
                }
                LabeledContent("Password") {
                    SecureField("Password", text: $password)
                }
                Button("Save password in Keychain") {
                    do {
                        try UpstreamProxyPasswordStore().save(password)
                        credentialMessage = String(
                            localized: "Password saved. Restart the proxy to apply changes.",
                            bundle: AppLocalization.bundle
                        )
                    } catch {
                        credentialMessage = String(
                            localized: "Could not save the password: \(error.localizedDescription)",
                            bundle: AppLocalization.bundle
                        )
                    }
                }
                LabeledContent("Bypass hosts (comma-separated)") {
                    TextField("localhost, *.local", text: $settings.upstreamProxy.bypassHosts)
                        .accessibilityLabel("Bypass hosts (comma-separated)")
                }
                if let error = settings.upstreamProxy.validationError(listenPort: settings.defaultPort) {
                    Text(error).foregroundStyle(.red)
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(!settings.upstreamProxy.isEnabled)
            if let credentialMessage {
                Text(credentialMessage).font(DesignSystem.Fonts.caption)
            }
            Text("""
                Restart the proxy to apply changes. Bypassed hosts connect directly and are still captured. \
                Use exact hostnames or wildcards such as *.local.
                """)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
            Text("""
                HTTP and HTTPS upstream proxies support Basic authentication. \
                For Clash or Sing-box, use an HTTP or mixed port; \
                SOCKS5 upstream is not supported by the embedded engine.
                """)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
        }
        .task {
            guard !settings.upstreamProxy.username.isEmpty else { return }
            do {
                password = try UpstreamProxyPasswordStore().load()
            } catch {
                credentialMessage = String(
                    localized: "Could not read the saved password: \(error.localizedDescription)",
                    bundle: AppLocalization.bundle
                )
            }
        }
    }
}
