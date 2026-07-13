import SwiftUI

struct GitCollectionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProxyViewModel
    let colors: DesignSystem.ColorPalette

    @State private var remoteURL: String = ""
    @State private var reference: String = "main"
    @State private var subdirectory: String = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmRemoveID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            header

            addSection
            sourcesSection
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(minWidth: 820, minHeight: 520)
        .background(colors.background)
        .alert(
            "Operation failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Remove this repository?",
            isPresented: Binding(
                get: { confirmRemoveID != nil },
                set: { if !$0 { confirmRemoveID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let id = confirmRemoveID {
                    viewModel.removeGitCollectionSource(id)
                }
                confirmRemoveID = nil
            }
            Button("Cancel", role: .cancel) {
                confirmRemoveID = nil
            }
        } message: {
            Text("Imported collections will remain in your workspace; sync will be disabled.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Git Collections")
                    .font(DesignSystem.Fonts.mono(22, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text("Import and sync collections from a Git repository (branch/tag/commit). Collections are read from `.har` files in the repo.")
                    .font(DesignSystem.Fonts.mono(12))
                    .foregroundStyle(colors.textSecondary)
            }

            Spacer()

            ControlButton(
                title: isWorking ? "Syncing…" : "Sync All",
                systemImage: "arrow.triangle.2.circlepath",
                style: .ghost(colors),
                disabled: isWorking || viewModel.gitCollectionSources.isEmpty
            ) {
                Task { await syncAll() }
            }

            ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors), disabled: isWorking) {
                dismiss()
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.08)
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Add Repository")
                .font(DesignSystem.Fonts.sans(16, weight: .semibold))
                .foregroundStyle(colors.textPrimary)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                TextField("Remote URL", text: $remoteURL)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "link"))

                TextField("Branch / Tag / Commit", text: $reference)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "arrow.triangle.branch"))

                TextField("Subdirectory (optional)", text: $subdirectory)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "folder"))

                Text("Example: `main`, `v1.2.3`, or a commit SHA. The subdirectory limits the `.har` scan (e.g. `collections/`).")
                    .font(DesignSystem.Fonts.mono(11))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DesignSystem.Spacing.sm) {
                ControlButton(
                    title: "Add & Sync",
                    systemImage: "square.and.arrow.down",
                    style: .filled(colors),
                    disabled: isWorking || remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    Task { await addAndSync() }
                }

                if isWorking {
                    ProgressView()
                        .progressViewStyle(.circular)
                }

                Spacer()
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.08)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                Text("Repositories")
                    .font(DesignSystem.Fonts.sans(16, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                Text("\(viewModel.gitCollectionSources.count)")
                    .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(
                        Capsule()
                            .fill(colors.surfaceElevated)
                    )
                    .overlay(
                        Capsule()
                            .stroke(colors.border.opacity(0.7), lineWidth: 1)
                    )
            }

            Divider()

            if viewModel.gitCollectionSources.isEmpty {
                StateView(
                    kind: .empty(
                        title: "No repository configured.",
                        message: "Add a repo on the left to import collections collaboratively via Git.",
                        systemImage: "arrow.triangle.branch"
                    ),
                    palette: colors
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(viewModel.gitCollectionSources) { source in
                            GitSourceRow(
                                source: source,
                                colors: colors,
                                isWorking: isWorking,
                                onSync: { Task { await sync(sourceID: source.id) } },
                                onRemove: { confirmRemoveID = source.id }
                            )
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.08)
    }

    private func addAndSync() async {
        if isWorking { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let trimmedSubdirectory = subdirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            try await viewModel.addGitCollectionSource(
                remoteURL: remoteURL,
                reference: reference,
                subdirectory: trimmedSubdirectory.isEmpty ? nil : trimmedSubdirectory
            )
            remoteURL = ""
            reference = "main"
            subdirectory = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sync(sourceID: UUID) async {
        if isWorking { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await viewModel.syncGitCollectionSource(sourceID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncAll() async {
        if isWorking { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await viewModel.syncAllGitCollectionSources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GitSourceRow: View {
    let source: GitCollectionSource
    let colors: DesignSystem.ColorPalette
    let isWorking: Bool
    let onSync: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text(source.remoteURL)
                        .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Label("ref: \(source.reference)", systemImage: "arrow.triangle.branch")
                            .labelStyle(.titleAndIcon)
                        if let subdirectoryLabel {
                            Label(subdirectoryLabel, systemImage: "folder")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(DesignSystem.Fonts.mono(11))
                    .foregroundStyle(colors.textSecondary)
                }

                Spacer()

                HStack(spacing: DesignSystem.Spacing.sm) {
                    InlineActionButton(
                        title: isWorking ? "Syncing…" : "Sync",
                        systemImage: "arrow.triangle.2.circlepath",
                        palette: colors,
                        isDestructive: false,
                        disabled: isWorking,
                        action: onSync
                    )
                    InlineActionButton(
                        title: "Remove",
                        systemImage: "trash",
                        palette: colors,
                        isDestructive: true,
                        disabled: isWorking,
                        action: onRemove
                    )
                }
            }

            if let lastSyncedAt = source.lastSyncedAt {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Label("Last sync \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    if let commitLabel {
                        Label(commitLabel, systemImage: "number")
                    }
                }
                .font(DesignSystem.Fonts.mono(11))
                .foregroundStyle(colors.textSecondary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .stroke(colors.border.opacity(0.7), lineWidth: 1)
        )
    }

    private var subdirectoryLabel: String? {
        let trimmed = source.subdirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var commitLabel: String? {
        let trimmed = source.lastSyncedCommit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(10))
    }
}

private struct InlineActionButton: View {
    let title: String
    let systemImage: String
    let palette: DesignSystem.ColorPalette
    let isDestructive: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(DesignSystem.Fonts.mono(11, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
                .clipShape(.rect(cornerRadius: DesignSystem.Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private var background: Color {
        if isDestructive {
            return palette.danger.opacity(0.14)
        }
        return palette.surface
    }

    private var border: Color {
        if isDestructive {
            return palette.danger.opacity(0.55)
        }
        return palette.border.opacity(0.85)
    }

    private var foreground: Color {
        if isDestructive {
            return palette.danger
        }
        return palette.textPrimary
    }
}
