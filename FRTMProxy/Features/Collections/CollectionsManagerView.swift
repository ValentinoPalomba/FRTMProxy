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
    @State private var showGitSheet = false
    @State private var publishContext: GitPublishContext?

    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    private var selectedCollection: MapCollection? {
        guard let id = selectedCollectionID else { return viewModel.collections.first }
        return viewModel.collections.first(where: { $0.id == id }) ?? viewModel.collections.first
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            header
            Divider()
            content
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(minWidth: 1240, minHeight: 680)
        .background(colors.background)
        .sheet(isPresented: $showStartSheet) {
            CollectionNameSheet(
                title: "New Collection",
                message: "Mapped requests captured while recording is active will be saved in this collection.",
                name: $pendingName,
                colors: colors,
                confirmLabel: "Start",
                onConfirm: startRecording,
                onCancel: { pendingName = ""; showStartSheet = false }
            )
        }
        .sheet(item: $renameTarget) { collection in
            CollectionNameSheet(
                title: "Rename Collection",
                message: "Update the name to better organize your collections.",
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
        .sheet(isPresented: $showGitSheet) {
            GitCollectionsSheet(viewModel: viewModel, colors: colors)
        }
        .sheet(item: $publishContext) { context in
            if let collection = viewModel.collections.first(where: { $0.id == context.collectionID }) {
                GitPublishCollectionSheet(viewModel: viewModel, collection: collection, colors: colors)
            } else {
                Text("Collection not found.")
                    .padding(DesignSystem.Spacing.xl)
            }
        }
        .alert(
            "Operation failed",
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
            Button("Save session") {
                viewModel.stopCollectionRecording(save: true)
            }
            Button("Discard", role: .destructive) {
                viewModel.stopCollectionRecording(save: false)
            }
            Button("Cancel", role: .cancel) { }
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
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Collections")
                    .font(DesignSystem.Fonts.mono(22, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text("Group Map Local into exportable collections and enable rule sets in one click.")
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
                title: "Git",
                systemImage: "arrow.triangle.branch",
                style: .ghost(colors)
            ) {
                showGitSheet = true
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
        HStack(spacing: DesignSystem.Spacing.lg) {
            collectionSidebar
                .frame(width: 320)
            VStack(spacing: DesignSystem.Spacing.lg) {
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
                        gitPublishDisabled: viewModel.gitCollectionSources.isEmpty,
                        onGitPublish: {
                            publishContext = GitPublishContext(collectionID: collection.id)
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
            LazyVStack(spacing: DesignSystem.Spacing.sm) {
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
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                        .stroke(colors.border.opacity(0.7), lineWidth: 1)
                )
        )
    }

    private var collectionsPlaceholder: some View {
        StateView(
            kind: .empty(
                title: "No collections",
                message: "Start a recording to automatically save a Map Local collection.",
                systemImage: "folder.badge.questionmark"
            ),
            palette: colors
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var detailPlaceholder: some View {
        StateView(
            kind: .empty(
                title: "Select a collection to view its rules.",
                message: nil,
                systemImage: "tray"
            ),
            palette: colors
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                        .stroke(colors.border.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private func recordingBadge(name: String, count: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Circle()
                .fill(colors.danger)
                .frame(width: 10, height: 10)
            Text("Recording \"\(name)\" (\(count) \(count == 1 ? "rule" : "rules"))")
                .font(DesignSystem.Fonts.mono(12, weight: .semibold))
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
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
        panel.nameFieldStringValue = "\(collection.name.proxySanitizedFilename()).har"
        let harType = UTType(filenameExtension: "har") ?? UTType.json
        panel.allowedContentTypes = [harType]
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
        let harType = UTType(filenameExtension: "har") ?? UTType.json
        panel.allowedContentTypes = [harType, UTType.zip, UTType.json]
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
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
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
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(isSelected ? colors.accent.opacity(0.12) : colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                        .stroke(isSelected ? colors.accent.opacity(0.6) : colors.border.opacity(0.6), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous))
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
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text("Recording \"\(collectionName)\"")
                        .font(DesignSystem.Fonts.sans(18, weight: .semibold))
                    Text("\(rules.count) \(rules.count == 1 ? "rule" : "rules") captured so far")
                        .font(DesignSystem.Fonts.mono(12))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            Divider()
            if rules.isEmpty {
                Text("No Map Local recorded yet. Map a flow to start populating the collection.")
                    .font(DesignSystem.Fonts.sans(13))
                    .foregroundStyle(colors.textSecondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
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
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
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
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(rule.path)
                    .font(DesignSystem.Fonts.mono(11, weight: .semibold))
                Text(rule.host)
                    .font(DesignSystem.Fonts.sans(13))
                    .foregroundStyle(colors.textSecondary)
                if let variantLabel {
                    Text(variantLabel)
                        .font(DesignSystem.Fonts.mono(10))
                        .foregroundStyle(colors.textSecondary)
                }
            }
            Spacer()
            Text("\(rule.status)")
                .font(DesignSystem.Fonts.mono(11, weight: .semibold))
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
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
            .accessibilityLabel("Edit rule")
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .fill(colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .stroke(colors.border.opacity(0.5), lineWidth: 1)
        )
    }

    private var variantLabel: String? {
        let method = rule.request?.method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let tag = MapRuleKeyBuilder.variantTag(from: rule.key)
        if let method, !method.isEmpty, let tag {
            return "\(method) • #\(tag)"
        }
        if let tag {
            return "#\(tag)"
        }
        return nil
    }
}

private struct CollectionDetailView: View {
    let collection: MapCollection
    let colors: DesignSystem.ColorPalette
    let onToggle: (Bool) -> Void
    let gitPublishDisabled: Bool
    let onGitPublish: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onEditRule: (MapRule) -> Void
    let onDeleteRule: (MapRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(collection.name)
                        .font(DesignSystem.Fonts.sans(20, weight: .semibold))
                    Text("Created \(collection.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(DesignSystem.Fonts.mono(12))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Toggle(isOn: Binding(get: { collection.isEnabled }, set: { onToggle($0) })) {
                    Text("Enabled")
                }
                .toggleStyle(.switch)
                .labelsHidden()
                ControlButton(
                    title: collection.origin?.git == nil ? "Publish" : "Push",
                    systemImage: "arrow.up.circle",
                    style: .ghost(colors),
                    disabled: gitPublishDisabled
                ) {
                    onGitPublish()
                }
                ControlButton(title: "Rename", systemImage: "pencil", style: .ghost(colors)) {
                    onRename()
                }
                ControlButton(title: "Delete", systemImage: "trash", style: .destructive(colors)) {
                    onDelete()
                }
            }
            Divider()
            if collection.rules.isEmpty {
                StateView(
                    kind: .empty(
                        title: "No rules saved in this collection",
                        message: nil,
                        systemImage: "questionmark.square.dashed"
                    ),
                    palette: colors
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(collection.rules) { rule in
                            CollectionRuleRow(
                                rule: rule,
                                colors: colors,
                                onEdit: { onEditRule(rule) },
                                onDelete: { onDeleteRule(rule) }
                            )
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                        .stroke(colors.border.opacity(0.6), lineWidth: 1)
                )
        )
    }
}

private struct GitPublishContext: Identifiable {
    let collectionID: UUID
    var id: UUID { collectionID }
}

private struct CollectionRuleRow: View {
    let rule: MapRule
    let colors: DesignSystem.ColorPalette
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(rule.path)
                    .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                Text(rule.host)
                    .font(DesignSystem.Fonts.sans(14))
                    .foregroundStyle(colors.textSecondary)
                if let variantLabel {
                    Text(variantLabel)
                        .font(DesignSystem.Fonts.mono(10))
                        .foregroundStyle(colors.textSecondary)
                }
            }
            Spacer()
            Text("\(rule.status)")
                .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
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
                    .padding(DesignSystem.Spacing.sm)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit rule")
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .padding(DesignSystem.Spacing.sm)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete rule")
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .stroke(colors.border.opacity(0.6), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous))
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var variantLabel: String? {
        let method = rule.request?.method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let tag = MapRuleKeyBuilder.variantTag(from: rule.key)
        if let method, !method.isEmpty, let tag {
            return "\(method) • #\(tag)"
        }
        if let tag {
            return "#\(tag)"
        }
        return nil
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
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text(title)
                .font(DesignSystem.Fonts.sans(20, weight: .semibold))
            Text(message)
                .font(DesignSystem.Fonts.sans(13))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Collection name", text: $name)
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
        .padding(DesignSystem.Spacing.xl)
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
