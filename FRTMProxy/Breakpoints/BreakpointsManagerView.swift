import SwiftUI

struct BreakpointsManagerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var viewModel: ProxyViewModel

    @State private var newHost: String = ""
    @State private var newPath: String = "/"
    @State private var includeRequest: Bool = true
    @State private var includeResponse: Bool = true

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    private var breakpointRules: [FlowBreakpointRule] {
        viewModel.orderedBreakpointRules
    }

    var body: some View {
        VStack(spacing: 18) {
            header
            Divider()
            creationCard
            if breakpointRules.isEmpty {
                emptyPlaceholder
            } else {
                rulesList
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 600)
        .background(colors.background)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Breakpoints")
                    .font(DesignSystem.Fonts.mono(20, weight: .semibold))
                Text("Crea e abilita breakpoints persistenti per request e response.")
                    .font(DesignSystem.Fonts.mono(13))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors)) {
                dismiss()
            }
        }
    }

    private var creationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nuovo breakpoint")
                    .font(DesignSystem.Fonts.sans(14, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                Button {
                    fillFromSelection()
                } label: {
                    Label("Usa flow selezionato", systemImage: "cursorarrow.rays")
                        .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.selectedFlow == nil)
            }

            HStack(spacing: 12) {
                TextField("Host (es. api.example.com)", text: $newHost)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                TextField("Path (es. /v1/users)", text: $newPath)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors))
            }

            HStack(spacing: 12) {
                PhaseChip(
                    title: "Request",
                    subtitle: "Interrompi prima che parta",
                    isOn: includeRequest,
                    colors: colors,
                    action: { includeRequest.toggle() }
                )
                PhaseChip(
                    title: "Response",
                    subtitle: "Interrompi prima di mostrarla",
                    isOn: includeResponse,
                    colors: colors,
                    action: { includeResponse.toggle() }
                )
                Spacer()
                ControlButton(
                    title: "Add Breakpoint",
                    systemImage: "plus",
                    style: .filled(colors),
                    disabled: !canCreateBreakpoint
                ) {
                    createBreakpoint()
                }
            }
        }
        .padding(16)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.8), shadowOpacity: 0.05)
    }

    private var rulesList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(breakpointRules) { rule in
                    BreakpointRow(
                        rule: rule,
                        colors: colors,
                        onToggleRequest: { value in
                            viewModel.updateBreakpointPhases(
                                key: rule.key,
                                request: value,
                                response: rule.interceptResponse
                            )
                        },
                        onToggleResponse: { value in
                            viewModel.updateBreakpointPhases(
                                key: rule.key,
                                request: rule.interceptRequest,
                                response: value
                            )
                        },
                        onToggleEnabled: { enabled in
                            viewModel.setBreakpointEnabled(rule.key, enabled: enabled)
                        },
                        onDelete: {
                            viewModel.deleteBreakpoint(key: rule.key)
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(colors.border.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 46))
                .foregroundStyle(colors.textSecondary)
            Text("Nessun breakpoint configurato")
                .font(DesignSystem.Fonts.sans(16, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            Text("Aggiungi un host/path per bloccare request o response prima che passino dal proxy.")
                .font(DesignSystem.Fonts.sans(13))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var canCreateBreakpoint: Bool {
        !newHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (includeRequest || includeResponse)
    }

    private func createBreakpoint() {
        guard viewModel.createBreakpoint(
            host: newHost,
            path: newPath,
            interceptRequest: includeRequest,
            interceptResponse: includeResponse
        ) != nil else { return }
        newHost = ""
        newPath = "/"
        includeRequest = true
        includeResponse = true
    }

    private func fillFromSelection() {
        guard
            let flow = viewModel.selectedFlow,
            let urlString = flow.request?.url,
            let url = URL(string: urlString),
            let host = url.host
        else { return }
        newHost = host
        newPath = url.path.isEmpty ? "/" : url.path
    }
}

private struct BreakpointRow: View {
    let rule: FlowBreakpointRule
    let colors: DesignSystem.ColorPalette
    let onToggleRequest: (Bool) -> Void
    let onToggleResponse: (Bool) -> Void
    let onToggleEnabled: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.host)
                    .font(DesignSystem.Fonts.sans(15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(rule.path)
                    .font(DesignSystem.Fonts.mono(13))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            PhaseChip(
                title: "Request",
                subtitle: nil,
                isOn: rule.interceptRequest,
                colors: colors,
                action: { onToggleRequest(!rule.interceptRequest) }
            )
            PhaseChip(
                title: "Response",
                subtitle: nil,
                isOn: rule.interceptResponse,
                colors: colors,
                action: { onToggleResponse(!rule.interceptResponse) }
            )
            Toggle("Attivo", isOn: Binding(
                get: { rule.isEnabled },
                set: { onToggleEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle())

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.danger)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(colors.border.opacity(0.7), lineWidth: 1)
                )
        )
    }
}

private struct PhaseChip: View {
    let title: String
    let subtitle: String?
    let isOn: Bool
    let colors: DesignSystem.ColorPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Fonts.sans(12, weight: .semibold))
                    .foregroundStyle(isOn ? colors.accent : colors.textSecondary)
                if let subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Fonts.sans(10))
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isOn ? colors.accent.opacity(0.2) : colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isOn ? colors.accent : colors.border.opacity(0.8), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
