import SwiftUI

struct SessionFlowMetadataSheet: View {
    @Environment(\.dismiss) private var dismiss

    let flow: CaptureSessionFlow
    let colors: DesignSystem.ColorPalette
    let onSave: (String?, Bool) async throws -> Void

    @State private var note: String
    @State private var isBookmarked: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        flow: CaptureSessionFlow,
        colors: DesignSystem.ColorPalette,
        onSave: @escaping (String?, Bool) async throws -> Void
    ) {
        self.flow = flow
        self.colors = colors
        self.onSave = onSave
        _note = State(initialValue: flow.note ?? "")
        _isBookmarked = State(initialValue: flow.isBookmarked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Flow Notes")
                    .font(DesignSystem.Fonts.title)
                    .foregroundStyle(colors.textPrimary)
                Text(flow.flow.request?.url ?? flow.id)
                    .font(DesignSystem.Fonts.monoBody)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Toggle("Bookmark this flow", isOn: $isBookmarked)

            TextEditor(text: $note)
                .accessibilityLabel("Flow note")
                .proxyTextEditor(palette: colors)
                .frame(minHeight: DesignSystem.Metrics.scaled(140))
                .padding(DesignSystem.Spacing.sm)
                .background(colors.surfaceElevated)
                .clipShape(.rect(cornerRadius: DesignSystem.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                        .stroke(colors.border, lineWidth: 1)
                }

            HStack {
                Spacer()
                ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors), disabled: isSaving) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                ControlButton(title: "Save", systemImage: "checkmark", style: .filled(colors), disabled: isSaving) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: DesignSystem.Metrics.scaled(520), height: DesignSystem.Metrics.scaled(360))
        .background(colors.background)
        .interactiveDismissDisabled(isSaving)
        .alert(
            "Unable to Save Note",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func save() {
        isSaving = true
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isSaving = false }
            do {
                try await onSave(normalizedNote.isEmpty ? nil : normalizedNote, isBookmarked)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
