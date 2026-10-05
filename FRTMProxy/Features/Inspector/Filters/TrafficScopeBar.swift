import SwiftUI

struct TrafficScopeBar: View {
    let colors: DesignSystem.ColorPalette
    @Binding var filter: FlowFilter
    @Binding var noiseQuery: String
    @Binding var noiseEnabled: Bool
    @AppStorage(SavedFocusSet.dataKey) private var savedData = Data()
    @AppStorage("inspector.focusSets.unreadableBackup") private var unreadableBackup = Data()
    @State private var focusSets: [SavedFocusSet] = []
    @State private var showSave = false
    @State private var showNoise = false
    @State private var showReset = false
    @State private var unreadable = false
    @State private var error: String?
    @State private var name = ""
    @State private var draftNoise = ""
    @State private var draftNoiseEnabled = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Menu("Focus Sets", systemImage: "line.3.horizontal.decrease.circle") {
                ForEach(focusSets) { scope in
                    Button(focusSets.filter { $0.name.caseInsensitiveCompare(scope.name) == .orderedSame }.count > 1
                           ? scope.name + " (" + scope.id.uuidString.prefix(6) + ")" : scope.name) { filter = scope.filter }
                }
                Divider()
                Button("Save Current Filters…") { name = ""; showSave = true }
                    .disabled(unreadable || focusSets.count >= 50)
                if !focusSets.isEmpty {
                    Menu("Delete Focus Set") {
                        ForEach(focusSets) { scope in
                            Button(scope.name, role: .destructive) { _ = persist(focusSets.filter { $0.id != scope.id }) }
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .font(DesignSystem.Fonts.label)
            .foregroundStyle(colors.textPrimary)
            .fixedSize()
            ControlButton(title: "Noise Control", systemImage: noiseEnabled ? "speaker.slash" : "speaker.wave.2", style: .ghost(colors)) {
                draftNoise = noiseQuery
                draftNoiseEnabled = noiseEnabled
                showNoise = true
            }
            if unreadable { ControlButton(title: "Reset Focus Sets", systemImage: "arrow.counterclockwise", style: .ghost(colors)) { showReset = true } }
            if let error { Text(error).foregroundStyle(colors.warning).lineLimit(1).help(error) }
            if noiseEnabled {
                Text("Matching traffic is hidden; capture continues").font(DesignSystem.Fonts.caption).foregroundStyle(colors.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.bottom, DesignSystem.Spacing.sm)
        .task { reload(savedData) }
        .onChange(of: savedData) { _, data in reload(data) }
        .alert("Reset unreadable focus sets?", isPresented: $showReset) {
            Button("Reset") {
                unreadableBackup = savedData
                savedData = Data()
                reload(savedData)
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("The unreadable data is kept as the latest local backup. Saved focus sets will start empty.") }
        .sheet(isPresented: $showSave) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Save Focus Set").font(DesignSystem.Fonts.title)
                TextField("Name", text: $name)
                Text("Up to 50 distinct names (128 bytes each); filter query up to 4 KiB.").font(DesignSystem.Fonts.caption)
                if let error { Text(error).foregroundStyle(colors.warning) }
                HStack {
                    ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors)) { showSave = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    ControlButton(title: "Save", systemImage: "checkmark", style: .filled(colors), disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unreadable) {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !focusSets.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) else {
                            error = "A focus set with this name already exists."
                            return
                        }
                        if persist(focusSets + [.init(name: trimmedName, filter: filter)]) { showSave = false }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .textFieldStyle(ProxyTextFieldStyle(palette: colors))
            .font(DesignSystem.Fonts.body)
            .foregroundStyle(colors.textPrimary)
            .padding(DesignSystem.Spacing.lg)
            .frame(width: DesignSystem.Metrics.scaled(520))
            .background(colors.background)
        }
        .sheet(isPresented: $showNoise) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Noise Control").font(DesignSystem.Fonts.title)
                TextField("Filter query, e.g. host:telemetry.example", text: $draftNoise)
                Toggle("Hide matching traffic", isOn: $draftNoiseEnabled)
                Text("Hidden traffic remains captured and available in Sessions.").font(DesignSystem.Fonts.caption).foregroundStyle(colors.textSecondary)
                if draftNoise.utf8.count > 4096 { Text("Maximum query length: 4 KiB.").foregroundStyle(colors.warning) }
                HStack {
                    ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors)) { showNoise = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    ControlButton(title: "Save", systemImage: "checkmark", style: .filled(colors), disabled: draftNoise.utf8.count > 4096) {
                        noiseQuery = draftNoise
                        noiseEnabled = draftNoiseEnabled
                        showNoise = false
                    }.keyboardShortcut(.defaultAction)
                }
            }
            .textFieldStyle(ProxyTextFieldStyle(palette: colors))
            .font(DesignSystem.Fonts.body)
            .foregroundStyle(colors.textPrimary)
            .padding(DesignSystem.Spacing.lg)
            .frame(width: DesignSystem.Metrics.scaled(520))
            .background(colors.background)
        }
    }
    private func reload(_ data: Data) {
        do { focusSets = try SavedFocusSet.decode(data); unreadable = false; error = nil }
        catch { focusSets = []; unreadable = true; self.error = "Saved focus sets are unreadable; existing data has been preserved." }
    }
    private func persist(_ sets: [SavedFocusSet]) -> Bool {
        guard !unreadable else { return false }
        do { savedData = try SavedFocusSet.encode(sets); focusSets = sets; error = nil; return true }
        catch { self.error = "Cannot save: invalid/duplicate name, filter too large or focus set limit exceeded."; return false }
    }
}
