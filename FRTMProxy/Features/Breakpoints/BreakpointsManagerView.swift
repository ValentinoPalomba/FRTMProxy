import SwiftUI

struct BreakpointsManagerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var viewModel: ProxyViewModel

    @State private var newHost: String = ""
    @State private var newPath: String = "/"
    @State private var newMethod: String = "ANY"
    private static let methods = ["ANY", "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    @State private var includeRequest: Bool = true
    @State private var includeResponse: Bool = true
    @State private var isApplyingURLSplit = false
    @State private var pendingDeletion: FlowBreakpointRule?

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    private var breakpointRules: [FlowBreakpointRule] {
        viewModel.orderedBreakpointRules
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            header
            Divider()
            creationCard
            if breakpointRules.isEmpty {
                emptyPlaceholder
            } else {
                rulesList
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(minWidth: DesignSystem.Metrics.scaled(800), minHeight: DesignSystem.Metrics.scaled(560))
        .font(DesignSystem.Fonts.body)
        .foregroundStyle(colors.textPrimary)
        .tint(colors.accent)
        .background(colors.background)
        .confirmationDialog(
            "Delete breakpoint?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Breakpoint", role: .destructive) {
                guard let rule = pendingDeletion else { return }
                viewModel.deleteBreakpoint(key: rule.key)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingDeletion.map { "\($0.host)\($0.path) will no longer pause traffic." } ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Breakpoints")
                    .font(DesignSystem.Fonts.title)
                Text("Create and enable persistent breakpoints for requests and responses.")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors)) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private var creationCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("New breakpoint")
                    .font(DesignSystem.Fonts.heading)
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                ControlButton(title: "Use selected flow", systemImage: "cursorarrow.rays", style: .ghost(colors), disabled: viewModel.selectedFlow == nil) {
                    fillFromSelection()
                }
            }

            HStack(spacing: DesignSystem.Spacing.md) {
                TextField("Host (e.g. api.example.com)", text: $newHost)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "network"))
                    .onChange(of: newHost) { oldValue, newValue in
                        applyURLSplitIfNeeded(changedField: .host, previousValue: oldValue, newValue: newValue)
                    }
                TextField("Path (e.g. /v1/users)", text: $newPath)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "arrow.turn.down.right"))
                    .onChange(of: newPath) { oldValue, newValue in
                        applyURLSplitIfNeeded(changedField: .path, previousValue: oldValue, newValue: newValue)
                    }
            }

            HStack(spacing: DesignSystem.Spacing.md) {
                Picker("HTTP method", selection: $newMethod) {
                    ForEach(Self.methods, id: \.self) { method in
                        Text(method == "ANY" ? "Any method" : method).tag(method)
                    }
                }
                .frame(width: 185)
                PhaseChip(
                    title: "Request",
                    subtitle: "Pause before it starts",
                    isOn: includeRequest,
                    colors: colors,
                    action: { includeRequest.toggle() }
                )
                PhaseChip(
                    title: "Response",
                    subtitle: "Pause before displaying it",
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
        .padding(DesignSystem.Spacing.lg)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.8), shadowOpacity: 0.05)
    }

    private var rulesList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.sm) {
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
                            pendingDeletion = rule
                        }
                    )
                }
            }
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                        .stroke(colors.border.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private var emptyPlaceholder: some View {
        StateView(
            kind: .empty(
                title: "No breakpoints configured",
                message: "Add a host/path to pause requests or responses before they pass through the proxy.",
                systemImage: "exclamationmark.shield"
            ),
            palette: colors
        )
        .frame(maxWidth: .infinity, minHeight: DesignSystem.Metrics.scaled(200))
    }

    private var canCreateBreakpoint: Bool {
        !newHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (includeRequest || includeResponse)
    }

    private func createBreakpoint() {
        guard viewModel.createBreakpoint(
            host: newHost,
            path: newPath,
            interceptRequest: includeRequest,
            interceptResponse: includeResponse,
            method: newMethod == "ANY" ? nil : newMethod
        ) != nil else { return }
        newHost = ""
        newPath = "/"
        newMethod = "ANY"
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
        let method = flow.request?.method.uppercased() ?? "ANY"
        newMethod = Self.methods.contains(method) ? method : "ANY"
    }

    private func applyURLSplitIfNeeded(changedField: URLInputField, previousValue: String, newValue: String) {
        guard !isApplyingURLSplit else { return }
        let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }

        let hostWasEmpty: Bool
        let pathWasEmpty: Bool
        switch changedField {
        case .host:
            hostWasEmpty = previousValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let currentPath = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
            pathWasEmpty = currentPath.isEmpty || currentPath == "/"
        case .path:
            hostWasEmpty = newHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let previousPath = previousValue.trimmingCharacters(in: .whitespacesAndNewlines)
            pathWasEmpty = previousPath.isEmpty || previousPath == "/"
        }

        guard hostWasEmpty && pathWasEmpty else { return }
        guard let split = FormattingUtils.splitHostAndPath(from: trimmedValue) else { return }

        isApplyingURLSplit = true
        newHost = split.host
        newPath = split.path
        isApplyingURLSplit = false
    }
}

private enum URLInputField {
    case host
    case path
}

private struct BreakpointRow: View {
    let rule: FlowBreakpointRule
    let colors: DesignSystem.ColorPalette
    let onToggleRequest: (Bool) -> Void
    let onToggleResponse: (Bool) -> Void
    let onToggleEnabled: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(rule.host)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rule.host)
                    .font(DesignSystem.Fonts.heading)
                    .foregroundStyle(colors.textPrimary)
                Text(rule.path)
                    .lineLimit(2)
                    .help(rule.path)
                    .font(DesignSystem.Fonts.mono(13))
                    .foregroundStyle(colors.textSecondary)
                Text(rule.method ?? "Any HTTP method")
                    .font(DesignSystem.Fonts.mono(12))
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
            Toggle("Active", isOn: Binding(
                get: { rule.isEnabled },
                set: { onToggleEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle())

            Button("Delete breakpoint", systemImage: "trash", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.pressable)
                .hoverHighlight(colors)
                .foregroundStyle(colors.destructive)
                .help("Delete breakpoint")
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
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
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(LocalizedStringKey(title))
                    .font(DesignSystem.Fonts.label)
                    .foregroundStyle(isOn ? colors.accent : colors.textSecondary)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                    .fill(isOn ? colors.accent.opacity(0.2) : colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                            .stroke(isOn ? colors.accent : colors.border.opacity(0.8), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.pressable)
        .hoverHighlight(colors)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
