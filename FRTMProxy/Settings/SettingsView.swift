import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) private var scheme
    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: scheme)
    }

    var body: some View {
        GeometryReader { proxy in
            TabView {
                generalTab
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
                themesTab
                    .tabItem {
                        Label("Themes", systemImage: "paintpalette")
                    }
            }
            .padding(20)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private var generalTab: some View {
        Form {
            Section(header: Text("Proxy Behavior")) {
                Toggle("Start proxy automatically", isOn: $settings.autoStartProxy)
                Toggle("Clear captured flows on start", isOn: $settings.autoClearOnStart)
                Toggle("Intercept only active pinned hosts", isOn: $settings.restrictInterceptionToActivePinnedHosts)
                HStack {
                    Text("Default port")
                    Spacer()
                    TextField(
                        "",
                        value: $settings.defaultPort,
                        formatter: portFormatter
                    )
                    .frame(width: 80)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
                    .onChange(of: settings.defaultPort) { _, newValue in
                        settings.defaultPort = Self.sanitizedPort(newValue)
                    }
                }
                Text("Port used when starting the embedded mitmproxy. Range 1024-65535.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("When enabled, mitmproxy will only MITM active pinned hosts; all other HTTPS traffic is tunneled to avoid interfering with other apps. Restart the proxy to apply changes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var themesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ThemePickerSection(
                    title: "Automatico",
                    subtitle: "Usa l'aspetto di macOS e mantieni i colori originali dell'app.",
                    themes: ThemeLibrary.automaticThemes,
                    selection: $settings.selectedThemeID
                )

                ThemePickerSection(
                    title: "Temi Chiari",
                    subtitle: "Palette pensate per ambienti luminosi.",
                    themes: ThemeLibrary.lightThemes,
                    selection: $settings.selectedThemeID
                )

                ThemePickerSection(
                    title: "Temi Scuri",
                    subtitle: "Ideali per sessioni notturne o ambienti poco illuminati.",
                    themes: ThemeLibrary.darkThemes,
                    selection: $settings.selectedThemeID
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var portFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 1024
        formatter.maximum = 65535
        formatter.numberStyle = .decimal
        return formatter
    }

    private static func sanitizedPort(_ value: Int) -> Int {
        min(max(value, 1024), 65535)
    }
}

private struct ThemePickerSection: View {
    let title: String
    let subtitle: String
    let themes: [AppTheme]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(themes) { theme in
                    ThemeOptionRow(theme: theme, selection: $selection)
                }
            }
        }
        .padding(.horizontal, 6)
    }
}

private struct ThemeOptionRow: View {
    let theme: AppTheme
    @Binding var selection: String

    private var isSelected: Bool {
        selection == theme.id
    }

    var body: some View {
        Button {
            selection = theme.id
        } label: {
            HStack(spacing: 16) {
                ThemePreviewSwatches(colors: theme.previewSwatches)
                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.name)
                        .font(.headline)
                    Text(theme.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ThemePreviewSwatches: View {
    let colors: [Color]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(colors.enumerated()), id: \.offset) { item in
                let color = item.element
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: 16, height: 28)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.08))
        )
    }
}
