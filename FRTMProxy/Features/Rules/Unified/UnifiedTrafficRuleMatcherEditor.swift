import SwiftUI

struct UnifiedTrafficRuleMatcherEditor: View {
    let draft: UnifiedTrafficRuleDraft

    var body: some View {
        @Bindable var draft = draft

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Label("Request matcher", systemImage: "scope")
                .font(.headline)
            Text("Unset fields match any value. Query and body values use canonical request formatting.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: DesignSystem.Spacing.lg) {
                GridRow {
                    UnifiedTrafficRulePatternEditor(title: "Scheme", pattern: $draft.rule.matcher.scheme)
                    UnifiedTrafficRulePatternEditor(title: "Host", pattern: $draft.rule.matcher.host)
                }
                GridRow {
                    UnifiedTrafficRulePatternEditor(title: "Path", pattern: $draft.rule.matcher.path)
                    UnifiedTrafficRulePatternEditor(title: "Method", pattern: $draft.rule.matcher.method)
                }
                GridRow {
                    UnifiedTrafficRulePatternEditor(title: "Canonical query", pattern: $draft.rule.matcher.query)
                    UnifiedTrafficRulePatternEditor(title: "Canonical body", pattern: $draft.rule.matcher.body)
                }
            }

            HStack {
                Text("Header matchers")
                    .font(.headline)
                Spacer()
                Button("Add Header", systemImage: "plus") {
                    draft.addHeaderMatcher()
                }
                .accessibilityHint("Adds a request header matcher")
            }

            if draft.headerMatchers.isEmpty {
                Text("No header constraints")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(draft.headerMatchers) { header in
                        UnifiedTrafficRuleHeaderMatcherRow(draft: draft, headerID: header.id)
                    }
                }
            }
        }
    }
}

private struct UnifiedTrafficRuleHeaderMatcherRow: View {
    let draft: UnifiedTrafficRuleDraft
    let headerID: UUID

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            TextField("Header name", text: headerName)
                .frame(minWidth: 140)
            TextField("Value pattern", text: headerValue)
            Picker("Mode", selection: headerMode) {
                ForEach(TrafficRuleTextPattern.Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 145)
            Toggle("Case sensitive", isOn: headerCaseSensitivity)
            Button("Remove Header", systemImage: "trash", role: .destructive) {
                draft.removeHeaderMatcher(id: headerID)
            }
            .labelStyle(.iconOnly)
            .accessibilityHint("Removes this header matcher")
        }
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
