import SwiftUI

struct UnifiedTrafficRuleActionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: UnifiedTrafficRuleActionFormModel
    let onSave: (TrafficRuleAction) -> Void

    init(action: TrafficRuleAction, onSave: @escaping (TrafficRuleAction) -> Void) {
        _model = State(initialValue: UnifiedTrafficRuleActionFormModel(action: action))
        self.onSave = onSave
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(model.kind.title)
                        .font(.title2)
                        .bold()
                    Text("Configure this action. Its position controls execution order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", systemImage: "xmark") { dismiss() }
                Button("Save Action", systemImage: "checkmark") {
                    onSave(model.makeAction())
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.validationMessage != nil)
            }
            .padding(DesignSystem.Spacing.lg)

            Divider()

            Form {
                switch model.kind {
                case .mock:
                    UnifiedMockActionFields(model: model)
                case .mapRemote:
                    UnifiedMapRemoteActionFields(model: model)
                case .rewriteRequest:
                    UnifiedRewriteRequestActionFields(model: model)
                case .rewriteResponse:
                    UnifiedRewriteResponseActionFields(model: model)
                case .block:
                    UnifiedBlockActionFields(model: model)
                case .delay:
                    UnifiedDelayActionFields(model: model)
                case .breakpoint:
                    UnifiedBreakpointActionFields(model: model)
                case .script:
                    UnifiedScriptActionFields(model: model)
                }

                if let message = model.validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Validation error: \(message)")
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 720, minHeight: 620)
    }
}

private struct UnifiedMockActionFields: View {
    @Bindable var model: UnifiedTrafficRuleActionFormModel

    var body: some View {
        Section("Response") {
            Stepper("Status: \(model.status)", value: $model.status, in: 100...599)
            UnifiedActionHeadersField(text: $model.headersText)
            UnifiedActionBodyField(text: $model.body, label: "Response body")
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

    var body: some View {
        Section("Request overrides") {
            TextField("Method (leave empty to preserve)", text: $model.method)
            TextField("URL (leave empty to preserve)", text: $model.url)
            UnifiedActionHeadersField(text: $model.headersText)
            Toggle("Replace request body", isOn: $model.includesBody)
            if model.includesBody {
                UnifiedActionBodyField(text: $model.body, label: "Request body")
            }
        }
    }
}

private struct UnifiedRewriteResponseActionFields: View {
    @Bindable var model: UnifiedTrafficRuleActionFormModel

    var body: some View {
        Section("Response overrides") {
            Toggle("Replace status", isOn: $model.includesStatus)
            if model.includesStatus {
                Stepper("Status: \(model.status)", value: $model.status, in: 100...599)
            }
            UnifiedActionHeadersField(text: $model.headersText)
            Toggle("Replace response body", isOn: $model.includesBody)
            if model.includesBody {
                UnifiedActionBodyField(text: $model.body, label: "Response body")
            }
        }
    }
}

private struct UnifiedBlockActionFields: View {
    @Bindable var model: UnifiedTrafficRuleActionFormModel

    var body: some View {
        Section("Synthetic response") {
            Stepper("Status: \(model.status)", value: $model.status, in: 100...599)
            UnifiedActionHeadersField(text: $model.headersText)
            UnifiedActionBodyField(text: $model.body, label: "Block message")
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

    var body: some View {
        Section("JavaScript") {
            Toggle("Response only", isOn: $model.responseOnly)
            TextEditor(text: $model.source)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 320)
                .accessibilityLabel("Script source")
        }
    }
}

private struct UnifiedActionHeadersField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Headers")
                .font(.headline)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
                .accessibilityLabel("Headers, one name colon value pair per line")
            Text("One Name: Value pair per line. Existing names are replaced.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct UnifiedActionBodyField: View {
    @Binding var text: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(label)
                .font(.headline)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150)
                .accessibilityLabel(label)
        }
    }
}
