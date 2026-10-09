import SwiftUI

struct UnifiedTrafficRuleActionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: UnifiedTrafficRuleActionFormModel
    let colors: DesignSystem.ColorPalette
    let onSave: (TrafficRuleAction) -> Void

    init(action: TrafficRuleAction, colors: DesignSystem.ColorPalette, onSave: @escaping (TrafficRuleAction) -> Void) {
        _model = State(initialValue: UnifiedTrafficRuleActionFormModel(action: action))
        self.onSave = onSave
        self.colors = colors
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(LocalizedStringKey(model.kind.title))
                        .font(DesignSystem.Fonts.title)
                    Text("Configure this action. Its position controls execution order.")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                ControlButton(title: "Save Action", systemImage: "checkmark", style: .filled(colors), disabled: model.validationMessage != nil) {
                    onSave(model.makeAction())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(colors.surface)

            Divider()

            Form {
                switch model.kind {
                case .mock:
                    UnifiedMockActionFields(model: model, colors: colors)
                case .mapRemote:
                    UnifiedMapRemoteActionFields(model: model)
                case .rewriteRequest:
                    UnifiedRewriteRequestActionFields(model: model, colors: colors)
                case .rewriteResponse:
                    UnifiedRewriteResponseActionFields(model: model, colors: colors)
                case .block:
                    UnifiedBlockActionFields(model: model, colors: colors)
                case .delay:
                    UnifiedDelayActionFields(model: model)
                case .breakpoint:
                    UnifiedBreakpointActionFields(model: model)
                case .script:
                    UnifiedScriptActionFields(model: model, colors: colors)
                }

                if let message = model.validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(colors.danger)
                            .lineLimit(3)
                            .help(message)
                            .accessibilityLabel("Validation error: \(message)")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
        .font(DesignSystem.Fonts.body)
        .foregroundStyle(colors.textPrimary)
        .tint(colors.accent)
        .background(colors.background)
        .frame(width: DesignSystem.Metrics.scaled(720), height: DesignSystem.Metrics.scaled(620))
    }
}

private struct UnifiedMockActionFields: View {
    @Bindable var model: UnifiedTrafficRuleActionFormModel
    let colors: DesignSystem.ColorPalette

    var body: some View {
        Section("Response") {
            Stepper("Status: \(model.status)", value: $model.status, in: 100...599)
            UnifiedActionHeadersField(text: $model.headersText, colors: colors)
            UnifiedActionBodyField(text: $model.body, colors: colors, label: "Response body")
        }
    }
}

private struct UnifiedMapRemoteActionFields: View {
    @Bindable var model: UnifiedTrafficRuleActionFormModel

    var body: some View {
        Section("Destination") {
            TextField("https://api.example.com", text: $model.destinationURL)
                .accessibilityLabel("Destination URL")
            Toggle("Preserve source path", isOn: $model.preservePath)
            Toggle("Preserve source query", isOn: $model.preserveQuery)
        }
    }
}

private struct UnifiedRewriteRequestActionFields: View {
    @Bindable var model: UnifiedTrafficRuleActionFormModel
    let colors: DesignSystem.ColorPalette

    var body: some View {
        Section("Request overrides") {
            TextField("Method (leave empty to preserve)", text: $model.method)
            TextField("URL (leave empty to preserve)", text: $model.url)
            UnifiedActionHeadersField(text: $model.headersText, colors: colors)
            Toggle("Replace request body", isOn: $model.includesBody)
            if model.includesBody {
                UnifiedActionBodyField(text: $model.body, colors: colors, label: "Request body")
            }
        }
    }
}

private struct UnifiedRewriteResponseActionFields: View {
    @Bindable var model: UnifiedTrafficRuleActionFormModel
    let colors: DesignSystem.ColorPalette

    var body: some View {
        Section("Response overrides") {
            Toggle("Replace status", isOn: $model.includesStatus)
            if model.includesStatus {
                Stepper("Status: \(model.status)", value: $model.status, in: 100...599)
            }
            UnifiedActionHeadersField(text: $model.headersText, colors: colors)
            Toggle("Replace response body", isOn: $model.includesBody)
            if model.includesBody {
                UnifiedActionBodyField(text: $model.body, colors: colors, label: "Response body")
            }
        }
    }
}

private struct UnifiedBlockActionFields: View {
    @Bindable var model: UnifiedTrafficRuleActionFormModel
    let colors: DesignSystem.ColorPalette

    var body: some View {
        Section("Synthetic response") {
            Stepper("Status: \(model.status)", value: $model.status, in: 100...599)
            UnifiedActionHeadersField(text: $model.headersText, colors: colors)
            UnifiedActionBodyField(text: $model.body, colors: colors, label: "Block message")
        }
    }
}

private struct UnifiedDelayActionFields: View {
    @Bindable var model: UnifiedTrafficRuleActionFormModel

    var body: some View {
        Section("Delay in milliseconds") {
            TextField("Request delay", value: $model.requestMilliseconds, format: .number)
            TextField("Response delay", value: $model.responseMilliseconds, format: .number)
        }
    }
}

private struct UnifiedBreakpointActionFields: View {
    @Bindable var model: UnifiedTrafficRuleActionFormModel

    var body: some View {
        Section("Pause phase") {
            Toggle("Request", isOn: $model.interceptRequest)
            Toggle("Response", isOn: $model.interceptResponse)
        }
    }
}

private struct UnifiedScriptActionFields: View {
    @Bindable var model: UnifiedTrafficRuleActionFormModel
    let colors: DesignSystem.ColorPalette

    var body: some View {
        Section("JavaScript") {
            Toggle("Response only", isOn: $model.responseOnly)
            TextEditor(text: $model.source)
                .proxyTextEditor(palette: colors, minHeight: DesignSystem.Metrics.scaled(280))
                .accessibilityLabel("Script source")
        }
    }
}

private struct UnifiedActionHeadersField: View {
    @Binding var text: String
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Headers")
                .font(DesignSystem.Fonts.heading)
            TextEditor(text: $text)
                .proxyTextEditor(palette: colors, minHeight: DesignSystem.Metrics.scaled(90))
                .accessibilityLabel("Headers, one name colon value pair per line")
            Text("One Name: Value pair per line. Existing names are replaced.")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
        }
    }
}

private struct UnifiedActionBodyField: View {
    @Binding var text: String
    let colors: DesignSystem.ColorPalette
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(label)
                .font(DesignSystem.Fonts.heading)
            TextEditor(text: $text)
                .proxyTextEditor(palette: colors, minHeight: DesignSystem.Metrics.scaled(150))
                .accessibilityLabel(label)
        }
    }
}
