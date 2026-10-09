import SwiftUI

struct CaptureProfilesControl: View {
    @ObservedObject var store: CaptureProfileStore
    let colors: DesignSystem.ColorPalette
    let onCreate: () -> Void
    var onManage: (() -> Void)? = nil
    @State private var showsManager = false

    var body: some View {
        Menu {
            Button {
                store.selectProfile(nil)
            } label: {
                Label("All Traffic", systemImage: store.activeProfileID == nil ? "checkmark" : "network")
            }
            .disabled(!store.canEdit)
            ForEach(store.profiles) { profile in
                Button {
                    store.selectProfile(profile.id)
                } label: {
                    Label(profile.name, systemImage: store.activeProfileID == profile.id ? "checkmark" : "folder")
                }
                .disabled(!store.canEdit)
            }
            Divider()
            Button("New Profile…", systemImage: "plus", action: onCreate)
                .disabled(!store.canEdit)
            Button("Manage Profiles…", systemImage: "slider.horizontal.3") {
                if let onManage {
                    onManage()
                } else {
                    showsManager = true
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: store.errorMessage == nil ? "folder" : "exclamationmark.triangle")
                    .foregroundStyle(store.errorMessage == nil ? colors.textSecondary : colors.danger)
                Text(store.activeProfile?.name ?? String(localized: "All Traffic", bundle: AppLocalization.bundle))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(DesignSystem.Fonts.caption)
            }
            .font(DesignSystem.Fonts.label)
            .foregroundStyle(colors.textPrimary)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .frame(maxWidth: DesignSystem.Metrics.scaled(180))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .hoverHighlight(colors)
        .help(store.errorMessage ?? String(localized: "Capture profile: \(store.activeProfile?.name ?? String(localized: "All Traffic", bundle: AppLocalization.bundle))"))
        .accessibilityLabel("Capture profile")
        .accessibilityIdentifier("capture.profile.picker")
        .accessibilityValue(store.activeProfile?.name ?? String(localized: "All Traffic", bundle: AppLocalization.bundle))
        .sheet(isPresented: $showsManager) {
            CaptureProfilesManagerView(store: store, colors: colors)
        }
    }
}

struct CaptureProfileCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CaptureProfileStore
    let colors: DesignSystem.ColorPalette
    let member: CaptureProfileMember?
    let onCreated: () -> Void
    @State private var name = ""
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("New capture profile")
                .font(DesignSystem.Fonts.title)
            Text("Name a set of requests, hosts, or apps to keep together.")
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(colors.textSecondary)
            if let member {
                Label(member.displayName, systemImage: "plus.circle")
                    .font(DesignSystem.Fonts.monoBody)
                    .lineLimit(3)
                    .help(member.displayName)
                    .padding(DesignSystem.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard(palette: colors, shadowOpacity: 0)
            }
            TextField("Profile name", text: $name)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "folder"))
                .accessibilityLabel("Profile name")
                .accessibilityIdentifier("capture.profile.name")
                .focused($nameFocused)
            if let message = errorMessage ?? store.errorMessage {
                CaptureProfileErrorView(message: message, colors: colors)
            }
            HStack(spacing: DesignSystem.Spacing.sm) {
                Spacer()
                ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                ControlButton(
                    title: "Create Profile", systemImage: "plus",
                    style: .filled(colors),
                    disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canEdit
                ) {
                    do {
                        let profile = try store.createProfile(name: name, member: member)
                        store.selectProfile(profile.id)
                        onCreated()
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("capture.profile.create")
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: DesignSystem.Metrics.scaled(520))
        .foregroundStyle(colors.textPrimary)
        .background(colors.background)
        .tint(colors.accent)
        .onAppear { nameFocused = true }
    }
}

struct CaptureProfilesManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CaptureProfileStore
    let colors: DesignSystem.ColorPalette
    @State private var selectedProfileID: UUID?
    @State private var nameDraft = ""
    @State private var memberDraft = ""
    @State private var addsApp = false
    @State private var errorMessage: String?
    @State private var deletionTarget: CaptureProfile?
    @State private var showsCreation = false

    private var selectedProfile: CaptureProfile? {
        store.profiles.first { $0.id == selectedProfileID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Capture profiles")
                        .font(DesignSystem.Fonts.title)
                    Text("Group requests, hosts, and apps into named profiles.")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                ControlButton(
                    title: "New Profile", systemImage: "plus",
                    style: .ghost(colors),
                    disabled: !store.canEdit
                ) { showsCreation = true }
                ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(colors.surface)
            Divider()
            if let message = errorMessage ?? store.errorMessage {
                CaptureProfileErrorView(message: message, colors: colors)
                    .padding(DesignSystem.Spacing.md)
            }
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.xs) {
                        ForEach(store.profiles) { profile in
                            Button {
                                selectedProfileID = profile.id
                            } label: {
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                    Text(profile.name)
                                        .font(DesignSystem.Fonts.label)
                                        .lineLimit(2)
                                        .help(profile.name)
                                    Text("Member count: \(profile.members.count)")
                                        .font(DesignSystem.Fonts.caption)
                                        .foregroundStyle(colors.textSecondary)
                                }
                                .padding(DesignSystem.Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    selectedProfileID == profile.id ? colors.accent.opacity(0.12) : colors.surface,
                                    in: .rect(cornerRadius: DesignSystem.Radius.sm)
                                )
                            }
                            .buttonStyle(.pressable)
                            .hoverHighlight(colors)
                            .accessibilityAddTraits(selectedProfileID == profile.id ? [.isSelected] : [])
                        }
                    }
                    .padding(DesignSystem.Spacing.sm)
                }
                .frame(width: DesignSystem.Metrics.scaled(220))
                .background(colors.surface)
                Divider()
                if let profile = selectedProfile {
                    profileEditor(profile)
                } else {
                    StateView(
                        kind: .empty(
                            title: "No profile selected",
                            message: "Create a profile such as Intesa, CheBanca, or Curl, then add its requests, hosts, or apps.",
                            systemImage: "folder"
                        ),
                        palette: colors
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: DesignSystem.Metrics.scaled(820), height: DesignSystem.Metrics.scaled(680))
        .font(DesignSystem.Fonts.body)
        .foregroundStyle(colors.textPrimary)
        .background(colors.background)
        .tint(colors.accent)
        .onAppear {
            selectedProfileID = store.activeProfileID ?? store.profiles.first?.id
            loadDraft()
        }
        .onChange(of: selectedProfileID) { _, _ in loadDraft() }
        .onChange(of: store.profiles.map(\.id)) { _, ids in
            if let selectedProfileID, !ids.contains(selectedProfileID) {
                self.selectedProfileID = ids.first
            } else if selectedProfileID == nil {
                selectedProfileID = ids.first
            }
        }
        .sheet(isPresented: $showsCreation) {
            CaptureProfileCreationView(store: store, colors: colors, member: nil) {
                selectedProfileID = store.activeProfileID
            }
        }
        .confirmationDialog(
            "Delete capture profile?",
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Profile", role: .destructive) {
                if let target = deletionTarget {
                    perform { try store.removeProfile(target.id) }
                }
                deletionTarget = nil
            }
            Button("Cancel", role: .cancel) { deletionTarget = nil }
        } message: {
            Text("\(deletionTarget?.name ?? String(localized: "This profile", bundle: AppLocalization.bundle)) will be removed. Captured traffic remains available in All Traffic.")
        }
    }

    @ViewBuilder
    private func profileEditor(_ profile: CaptureProfile) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                TextField("Profile name", text: $nameDraft)
                    .accessibilityLabel("Profile name")
                ControlButton(
                    title: "Save Name", systemImage: "checkmark",
                    style: .ghost(colors),
                    disabled: !store.canEdit
                        || nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || nameDraft == profile.name
                ) {
                    if perform({ try store.renameProfile(profile.id, name: nameDraft) }) {
                        nameDraft = selectedProfile?.name ?? nameDraft
                    }
                }
            }
            HStack(spacing: DesignSystem.Spacing.sm) {
                ControlButton(
                    title: store.activeProfileID == profile.id ? "Active Profile" : "Use Profile",
                    systemImage: "checkmark.circle",
                    style: .filled(colors), disabled: !store.canEdit || store.activeProfileID == profile.id
                ) { store.selectProfile(profile.id) }
                Spacer()
                ControlButton(
                    title: "Delete", systemImage: "trash",
                    style: .destructive(colors),
                    disabled: !store.canEdit
                ) { deletionTarget = profile }
            }
            Divider()
            if profile.legacyFilter != nil {
                Label("Includes a migrated saved filter.", systemImage: "line.3.horizontal.decrease.circle")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
            }
            if profile.members.isEmpty {
                StateView(
                    kind: .empty(
                        title: profile.legacyFilter == nil ? "No members yet" : "No additional members",
                        message: "Add a host or app below, or add a request from the traffic list.",
                        systemImage: "plus.rectangle.on.folder"
                    ),
                    palette: colors
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(profile.members, id: \.self) { member in
                            HStack(spacing: DesignSystem.Spacing.sm) {
                                Text(member.displayName)
                                    .font(DesignSystem.Fonts.monoBody)
                                    .lineLimit(3)
                                    .help(member.displayName)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Remove member", systemImage: "minus.circle") {
                                    perform { try store.removeMember(member, from: profile.id) }
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.pressable)
                                .hoverHighlight(colors)
                                .disabled(!store.canEdit)
                                .help("Remove \(member.displayName)")
                            }
                            .padding(DesignSystem.Spacing.md)
                            .surfaceCard(palette: colors, radius: DesignSystem.Radius.sm, shadowOpacity: 0)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            Divider()
            Picker("Member type", selection: $addsApp) {
                Text("Host").tag(false)
                Text("App").tag(true)
            }
            .pickerStyle(.segmented)
            TextField(addsApp ? String(localized: "App bundle ID (com.example.app)", bundle: AppLocalization.bundle) : String(localized: "Host (api.example.com)", bundle: AppLocalization.bundle), text: $memberDraft)
                .accessibilityLabel(addsApp ? String(localized: "App bundle ID", bundle: AppLocalization.bundle) : String(localized: "Host", bundle: AppLocalization.bundle))
            HStack {
                Text(addsApp ? String(localized: "Use the app’s bundle identifier.", bundle: AppLocalization.bundle) : String(localized: "Add a hostname without a URL path.", bundle: AppLocalization.bundle))
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                ControlButton(
                    title: "Add Member", systemImage: "plus",
                    style: .ghost(colors),
                    disabled: !store.canEdit || memberDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    let value = memberDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if perform({ try store.add(member: addsApp ? .app(value) : .host(value), to: profile.id) }) {
                        memberDraft = ""
                    }
                }
            }
        }
        .textFieldStyle(ProxyTextFieldStyle(palette: colors, size: .compact))
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func loadDraft() {
        nameDraft = selectedProfile?.name ?? ""
        memberDraft = ""
        errorMessage = nil
    }

    @discardableResult
    private func perform(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct CaptureProfileErrorView: View {
    let message: String
    let colors: DesignSystem.ColorPalette

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(DesignSystem.Fonts.caption)
            .foregroundStyle(colors.danger)
            .lineLimit(3)
            .help(message)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Capture profile error: \(message)")
    }
}
