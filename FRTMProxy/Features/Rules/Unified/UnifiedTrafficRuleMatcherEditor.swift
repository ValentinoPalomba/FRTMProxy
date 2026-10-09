import SwiftUI

struct UnifiedTrafficRuleMatcherEditor: View {
    @Bindable var draft: UnifiedTrafficRuleDraft
    let colors: DesignSystem.ColorPalette
    @FocusState private var focusedHeader: UUID?
    @State private var addedHeader: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Label("Request matcher", systemImage: "scope")
                .font(DesignSystem.Fonts.title)
            Text("Unset fields match any value. Query and body values use canonical request formatting.")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)

            Grid(alignment: .leading, horizontalSpacing: DesignSystem.Spacing.lg) {
                GridRow {
                    UnifiedTrafficRulePatternEditor(title: "Scheme", colors: colors, pattern: $draft.rule.matcher.scheme)
                    UnifiedTrafficRulePatternEditor(title: "Host", colors: colors, pattern: $draft.rule.matcher.host)
                }
                GridRow {
                    UnifiedTrafficRulePatternEditor(title: "Path", colors: colors, pattern: $draft.rule.matcher.path)
                    UnifiedTrafficRulePatternEditor(title: "Method", colors: colors, pattern: $draft.rule.matcher.method)
                }
                GridRow {
                    UnifiedTrafficRulePatternEditor(title: "Canonical query", colors: colors, pattern: $draft.rule.matcher.query)
                    UnifiedTrafficRulePatternEditor(title: "Canonical body", colors: colors, pattern: $draft.rule.matcher.body)
                }
            }

            HStack {
                Text("Header matchers")
                    .font(DesignSystem.Fonts.title)
                Spacer()
                ControlButton(title: "Add Header", systemImage: "plus", style: .ghost(colors)) {
                    draft.addHeaderMatcher()
                    addedHeader = draft.headerMatchers.last?.id
                }
                .accessibilityHint("Adds a request header matcher")
            }

            if draft.headerMatchers.isEmpty {
                Text("No header constraints")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(draft.headerMatchers) { header in
                                UnifiedTrafficRuleHeaderMatcherRow(draft: draft, headerID: header.id, colors: colors, focusedHeader: $focusedHeader)
                                    .id(header.id)
                            }
                        }
                    }
                    .task(id: addedHeader) {
                        guard let id = addedHeader else { return }
                        proxy.scrollTo(id, anchor: .bottom)
                        await Task.yield()
                        guard !Task.isCancelled, draft.headerMatchers.contains(where: { $0.id == id }) else { return }
                        focusedHeader = id
                    }
                }
                .frame(maxHeight: DesignSystem.Metrics.scaled(260))
            }
        }
    }
}

private struct UnifiedTrafficRuleHeaderMatcherRow: View {
    @Bindable var draft: UnifiedTrafficRuleDraft
    let headerID: UUID
    let colors: DesignSystem.ColorPalette
    var focusedHeader: FocusState<UUID?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
            TextField("Header name", text: headerName)
                .accessibilityLabel("Header matcher name")
                .focused(focusedHeader, equals: headerID)
                .frame(minWidth: DesignSystem.Metrics.scaled(140))
            TextField("Value pattern", text: headerValue)
                .accessibilityLabel("Header matcher pattern")
            }
            HStack(spacing: DesignSystem.Spacing.sm) {
            Picker("Mode", selection: headerMode) {
                ForEach(TrafficRuleTextPattern.Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Header matcher mode")
            .frame(width: DesignSystem.Metrics.scaled(145))
            Toggle("Case sensitive", isOn: headerCaseSensitivity)
            Spacer()
            ControlButton(title: "Remove Header", systemImage: "trash", style: .ghost(colors)) {
                draft.removeHeaderMatcher(id: headerID)
            }
            .accessibilityHint("Removes this header matcher")
        }
            }
        .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
        .font(DesignSystem.Fonts.body)
        .foregroundStyle(colors.textPrimary)
        .padding(DesignSystem.Spacing.md)
        .surfaceCard(palette: colors, shadowOpacity: 0)
        .accessibilityElement(children: .contain)
    }

    private var headerName: Binding<String> {
        Binding(
            get: { header?.name ?? "" },
            set: { newValue in updateHeader { $0.name = newValue } }
        )
    }

    private var headerValue: Binding<String> {
        Binding(
            get: { header?.value.value ?? "" },
            set: { newValue in updateHeader { $0.value.value = newValue } }
        )
    }

    private var headerMode: Binding<TrafficRuleTextPattern.Mode> {
        Binding(
            get: { header?.value.mode ?? .exact },
            set: { newValue in updateHeader { $0.value.mode = newValue } }
        )
    }

    private var headerCaseSensitivity: Binding<Bool> {
        Binding(
            get: { header?.value.isCaseSensitive ?? true },
            set: { newValue in updateHeader { $0.value.isCaseSensitive = newValue } }
        )
    }

    private var header: UnifiedTrafficRuleDraft.HeaderMatcher? {
        draft.headerMatchers.first { $0.id == headerID }
    }

    private func updateHeader(_ update: (inout UnifiedTrafficRuleDraft.HeaderMatcher) -> Void) {
        guard let index = draft.headerMatchers.firstIndex(where: { $0.id == headerID }) else { return }
        update(&draft.headerMatchers[index])
    }
}
