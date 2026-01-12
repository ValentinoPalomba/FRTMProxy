import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct CollectionsManagerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var viewModel: ProxyViewModel
    @StateObject private var editorViewModel = MapEditorViewModel()

    @State private var selectedCollectionID: UUID?
    @State private var showStartSheet = false
    @State private var pendingName: String = ""
    @State private var renameTarget: MapCollection?
    @State private var renameInput: String = ""
    @State private var confirmStopRecording = false
    @State private var editingRuleContext: RuleEditorContext?
    @State private var alertMessage: String?

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    private var selectedCollection: MapCollection? {
        guard let id = selectedCollectionID else { return viewModel.collections.first }
        return viewModel.collections.first(where: { $0.id == id }) ?? viewModel.collections.first
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            content
        }
        .padding(20)
        .frame(minWidth: 1240, minHeight: 680)
        .background(colors.background)
        .sheet(isPresented: $showStartSheet) {
            CollectionNameSheet(
                title: "Nuova Collection",
                message: "Le richieste mappate mentre la registrazione è attiva verranno salvate in questa collection.",
                name: $pendingName,
                colors: colors,
                confirmLabel: "Start",
                onConfirm: startRecording,
                onCancel: { pendingName = ""; showStartSheet = false }
            )
        }
        .sheet(item: $renameTarget) { collection in
            CollectionNameSheet(
                title: "Rinomina Collection",
                message: "Aggiorna il nome per organizzare meglio le tue raccolte.",
                name: $renameInput,
                colors: colors,
                confirmLabel: "Rename",
                onConfirm: { applyRename(collection: collection) },
                onCancel: { renameTarget = nil }
            )
        }
        .sheet(item: $editingRuleContext, onDismiss: { editingRuleContext = nil }) { context in
            RuleEditorSheet(
                context: context,
                editorViewModel: editorViewModel,
                colors: colors,
                onSave: { updatedRule in
                    switch context {
                    case .collection(let id, _):
                        viewModel.updateRule(inCollection: id, rule: updatedRule)
                    case .recording:
                        viewModel.updateRecordingRule(updatedRule)
                    }
                    editorViewModel.markSynced()
                },
                onClose: { editingRuleContext = nil }
            )
        }
        .alert(
            "Operazione non riuscita",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            "Stop Collection Registration?",
            isPresented: $confirmStopRecording,
            titleVisibility: .visible
        ) {
            Button("Salva sessione") {
                viewModel.stopCollectionRecording(save: true)
            }
            Button("Scarta", role: .destructive) {
                viewModel.stopCollectionRecording(save: false)
            }
            Button("Annulla", role: .cancel) { }
        }
        .onAppear {
            if selectedCollectionID == nil {
                selectedCollectionID = viewModel.collections.first?.id
            }
        }
        .onChange(of: viewModel.collections) { _, collections in
            if let id = selectedCollectionID, !collections.contains(where: { $0.id == id }) {
                selectedCollectionID = collections.first?.id
            } else if selectedCollectionID == nil {
                selectedCollectionID = collections.first?.id
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Collections")
                    .font(DesignSystem.Fonts.mono(22, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text("Raggruppa Map Local in collezioni esportabili e abilita blocchi di regole in un colpo solo.")
                    .font(DesignSystem.Fonts.mono(13))
                    .foregroundStyle(colors.textSecondary)
            }

            if viewModel.isRecordingCollection, let name = viewModel.recordingCollectionName {
                recordingBadge(name: name, count: viewModel.recordingRulesPreview.count)
            }

            Spacer()

            ControlButton(
                title: "Start Registration",
                systemImage: "record.circle",
                style: .filled(colors),
                disabled: viewModel.isRecordingCollection
            ) {
                pendingName = ""
                showStartSheet = true
            }

            ControlButton(
                title: "Stop",
                systemImage: "stop.circle",
                style: .destructive(colors),
                disabled: !viewModel.isRecordingCollection
            ) {
                confirmStopRecording = true
            }

            ControlButton(
                title: "Import",
                systemImage: "square.and.arrow.down",
                style: .ghost(colors)
            ) {
                importCollection()
            }

            ControlButton(
                title: "Export",
                systemImage: "square.and.arrow.up",
                style: .ghost(colors),
                disabled: selectedCollection == nil
            ) {
                exportSelectedCollection()
            }

            ControlButton(
                title: "Close",
                systemImage: "xmark",
                style: .ghost(colors)
            ) {
                dismiss()
            }
        }
    }

    private var content: some View {
        HStack(spacing: 16) {
            collectionSidebar
                .frame(width: 320)
            VStack(spacing: 16) {
                if viewModel.isRecordingCollection {
                    RecordingPreviewView(
                        collectionName: viewModel.recordingCollectionName ?? "",
                        rules: viewModel.recordingRulesPreview,
                        colors: colors,
                        onEditRule: { rule in openRecordingEditor(for: rule) }
                    )
                }
                if let collection = selectedCollection {
                    CollectionDetailView(
                        collection: collection,
                        colors: colors,
                        onToggle: { enabled in
                            viewModel.toggleCollection(collection.id, enabled: enabled)
                        },
                        onRename: {
                            renameInput = collection.name
                            renameTarget = collection
                        },
                        onDelete: {
                            viewModel.deleteCollection(collection.id)
                        },
                        onEditRule: { rule in
                            openEditor(for: rule, collectionID: collection.id)
                        },
                        onDeleteRule: { rule in
                            viewModel.deleteRule(inCollection: collection.id, ruleKey: rule.key)
                        }
                    )
                } else {
                    detailPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var collectionSidebar: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if viewModel.collections.isEmpty {
                    collectionsPlaceholder
                } else {
                    ForEach(viewModel.collections) { collection in
                        CollectionCard(
                            collection: collection,
                            colors: colors,
                            isSelected: collection.id == selectedCollection?.id,
                            onSelect: { selectedCollectionID = collection.id },
                            onToggle: { enabled in
                                viewModel.toggleCollection(collection.id, enabled: enabled)
                            },
                            onRename: {
                                renameInput = collection.name
                                renameTarget = collection
                            },
                            onDelete: {
                                viewModel.deleteCollection(collection.id)
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colors.border.opacity(0.7), lineWidth: 1)
                )
        )
    }

    private var collectionsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 42))
                .foregroundStyle(colors.textSecondary)
            Text("Nessuna collection")
                .font(DesignSystem.Fonts.sans(16, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            Text("Avvia una registrazione per salvare automaticamente una collezione di Map Local.")
                .font(DesignSystem.Fonts.sans(13))
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var detailPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(colors.textSecondary)
            Text("Seleziona una collection per vedere le sue regole.")
                .font(DesignSystem.Fonts.sans(15, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colors.border.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private func recordingBadge(name: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colors.danger)
                .frame(width: 10, height: 10)
            Text("Recording \"\(name)\" (\(count) \(count == 1 ? "rule" : "rules"))")
                .font(DesignSystem.Fonts.mono(12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(colors.surfaceElevated)
        )
        .overlay(
            Capsule()
                .stroke(colors.border.opacity(0.6), lineWidth: 1)
        )
    }

    private func startRecording() {
        viewModel.startCollectionRecording(name: pendingName)
        pendingName = ""
        showStartSheet = false
    }

    private func applyRename(collection: MapCollection) {
        viewModel.renameCollection(collection.id, newName: renameInput)
        renameTarget = nil
        renameInput = ""
    }

    private func openEditor(for rule: MapRule, collectionID: UUID) {
        editingRuleContext = .collection(collectionID, rule)
        editorViewModel.load(rule: rule)
    }

    private func openRecordingEditor(for rule: MapRule) {
        editingRuleContext = .recording(rule)
        editorViewModel.load(rule: rule)
    }

    private func exportSelectedCollection() {
        guard let collection = selectedCollection else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(collection.name.proxySanitizedFilename()).zip"
        panel.allowedContentTypes = [UTType.zip]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try viewModel.exportCollection(collection.id, to: url)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func importCollection() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try viewModel.importCollection(from: url)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }
}

private struct CollectionCard: View {
    let collection: MapCollection
    let colors: DesignSystem.ColorPalette
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(DesignSystem.Fonts.sans(16, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text("\(collection.rules.count) rules • \(collection.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(DesignSystem.Fonts.mono(11))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            Toggle(isOn: Binding(get: { collection.isEnabled }, set: { onToggle($0) })) {
                Text("Enabled")
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? colors.accent.opacity(0.12) : colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? colors.accent.opacity(0.6) : colors.border.opacity(0.6), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Rename") { onRename() }
            Button(collection.isEnabled ? "Disable" : "Enable") { onToggle(!collection.isEnabled) }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

private struct RecordingPreviewView: View {
    let collectionName: String
    let rules: [MapRule]
    let colors: DesignSystem.ColorPalette
    let onEditRule: (MapRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording \"\(collectionName)\"")
                        .font(DesignSystem.Fonts.sans(18, weight: .semibold))
                    Text("\(rules.count) \(rules.count == 1 ? "rule" : "rules") catturate finora")
                        .font(DesignSystem.Fonts.mono(12))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            Divider()
            if rules.isEmpty {
                Text("Map Local non ancora registrate. Map un flow per iniziare a popolare la collection.")
                    .font(DesignSystem.Fonts.sans(13))
                    .foregroundStyle(colors.textSecondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(rules) { rule in
                            RecordingPreviewRuleRow(
                                rule: rule,
                                colors: colors,
                                onEdit: { onEditRule(rule) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colors.border.opacity(0.6), lineWidth: 1)
                )
        )
    }
}

private struct RecordingPreviewRuleRow: View {
    let rule: MapRule
    let colors: DesignSystem.ColorPalette
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.path)
                    .font(DesignSystem.Fonts.mono(11, weight: .semibold))
                Text(rule.host)
                    .font(DesignSystem.Fonts.sans(13))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            Text("\(rule.status)")
                .font(DesignSystem.Fonts.mono(11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(colors.surface)
                )
                .overlay(
                    Capsule()
                        .stroke(colors.border.opacity(0.7), lineWidth: 1)
                )
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(colors.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colors.border.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct CollectionDetailView: View {
    let collection: MapCollection
    let colors: DesignSystem.ColorPalette
    let onToggle: (Bool) -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onEditRule: (MapRule) -> Void
    let onDeleteRule: (MapRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name)
                        .font(DesignSystem.Fonts.sans(20, weight: .semibold))
                    Text("Creata \(collection.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(DesignSystem.Fonts.mono(12))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Toggle(isOn: Binding(get: { collection.isEnabled }, set: { onToggle($0) })) {
                    Text("Enabled")
                }
                .toggleStyle(.switch)
                .labelsHidden()
                ControlButton(title: "Rename", systemImage: "pencil", style: .ghost(colors)) {
                    onRename()
                }
                ControlButton(title: "Delete", systemImage: "trash", style: .destructive(colors)) {
                    onDelete()
                }
            }
            Divider()
            if collection.rules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 40))
                        .foregroundStyle(colors.textSecondary)
                    Text("Nessuna regola salvata in questa collection")
                        .font(DesignSystem.Fonts.sans(14, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(collection.rules) { rule in
                            CollectionRuleRow(
                                rule: rule,
                                colors: colors,
                                onEdit: { onEditRule(rule) },
                                onDelete: { onDeleteRule(rule) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colors.border.opacity(0.6), lineWidth: 1)
                )
        )
    }
}

private struct CollectionRuleRow: View {
    let rule: MapRule
    let colors: DesignSystem.ColorPalette
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.path)
                    .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                Text(rule.host)
                    .font(DesignSystem.Fonts.sans(14))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            Text("\(rule.status)")
                .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(colors.surfaceElevated)
                )
                .overlay(
                    Capsule()
                        .stroke(colors.border.opacity(0.7), lineWidth: 1)
                )
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .padding(6)
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border.opacity(0.6), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

private struct CollectionNameSheet: View {
    let title: String
    let message: String
    @Binding var name: String
    let colors: DesignSystem.ColorPalette
    let confirmLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(DesignSystem.Fonts.sans(20, weight: .semibold))
            Text(message)
                .font(DesignSystem.Fonts.sans(13))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Nome collection", text: $name)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors))
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button(confirmLabel) {
                    onConfirm()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}

private enum RuleEditorContext: Identifiable {
    case collection(UUID, MapRule)
    case recording(MapRule)

    var id: String {
        switch self {
        case .collection(let id, let rule):
            return "\(id.uuidString)-\(rule.id)"
        case .recording(let rule):
            return "recording-\(rule.id)"
        }
    }

    var rule: MapRule {
        switch self {
        case .collection(_, let rule), .recording(let rule):
            return rule
        }
    }
}

private struct RuleEditorSheet: View {
    let context: RuleEditorContext
    @ObservedObject var editorViewModel: MapEditorViewModel
    let colors: DesignSystem.ColorPalette
    let onSave: (MapRule) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            MapEditorView(
                viewModel: editorViewModel,
                colors: colors,
                allowRequestEditing: false,
                showsRequestEditor: false,
                actions: MapEditorActions(
                    saveLabel: "Save",
                    saveIcon: "square.and.arrow.down",
                    onSave: {
                        guard let payload = editorViewModel.payload(defaultStatus: context.rule.status) else { return }
                        var updated = context.rule
                        updated.body = payload.responseBody
                        updated.status = payload.responseStatus
                        updated.headers = payload.responseHeaders
                        onSave(updated)
                        onClose()
                    },
                    closeLabel: "Close",
                    closeIcon: "xmark",
                    onClose: onClose
                ),
                isSelectionAvailable: true
            )
            .onAppear {
                editorViewModel.load(rule: context.rule)
            }
        }
        .frame(minWidth: 980, minHeight: 700)
    }
}
