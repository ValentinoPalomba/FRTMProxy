import SwiftUI

struct GitPublishCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    @ObservedObject var viewModel: ProxyViewModel
    let collection: MapCollection
    let colors: DesignSystem.ColorPalette

    @State private var selectedSourceID: UUID
    @State private var branch: String
    @State private var relativePath: String
    @State private var commitMessage: String
    @State private var tagName: String
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(viewModel: ProxyViewModel, collection: MapCollection, colors: DesignSystem.ColorPalette) {
        self.viewModel = viewModel
        self.collection = collection
        self.colors = colors

        let origin = collection.origin?.git
        let initialSourceID = origin?.sourceID ?? viewModel.gitCollectionSources.first?.id ?? UUID()
        _selectedSourceID = State(initialValue: initialSourceID)

        let initialBranch = origin?.reference ?? viewModel.gitCollectionSources.first(where: { $0.id == initialSourceID })?.reference ?? "main"
        _branch = State(initialValue: initialBranch)

        let initialPath = origin?.relativePath ?? "\(collection.name.proxySanitizedFilename()).har"
        _relativePath = State(initialValue: initialPath)

        let initialMessage = origin == nil ? "Add collection \(collection.name)" : "Update collection \(collection.name)"
        _commitMessage = State(initialValue: initialMessage)

        _tagName = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            form
            footer
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
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
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(collection.origin?.git == nil ? "Publish Collection" : "Push Collection")
                    .font(DesignSystem.Fonts.mono(22, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text("Export the collection as `.har`, create a commit, and push to a branch. Optionally create a tag too.")
                    .font(DesignSystem.Fonts.mono(12))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            ControlButton(title: "Close", systemImage: "xmark", style: .ghost(colors), disabled: isWorking) {
                dismiss()
            }
        }
        .padding(16)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.08)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            repositorySection
            branchSection
            pathSection
            commitSection
            tagSection
        }
        .padding(16)
        .surfaceCard(fill: colors.surface, stroke: colors.border.opacity(0.9), shadowOpacity: 0.08)
    }

    private var repositorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Repository")
                .font(DesignSystem.Fonts.sans(14, weight: .semibold))
                .foregroundStyle(colors.textPrimary)

            if let lockedSource {
                Text(lockedSource.remoteURL)
                    .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if viewModel.gitCollectionSources.isEmpty {
                Text("No Git source configured.")
                    .font(DesignSystem.Fonts.mono(12))
                    .foregroundStyle(colors.textSecondary)
            } else {
                Picker("Repo", selection: $selectedSourceID) {
                    ForEach(viewModel.gitCollectionSources) { source in
                        Text(source.remoteURL).tag(source.id)
                    }
                }
                .pickerStyle(.menu)
                Text("Configure repositories in Collections → Git.")
                    .font(DesignSystem.Fonts.mono(11))
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }

    private var branchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Branch")
                .font(DesignSystem.Fonts.sans(14, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
            TextField("Branch name (e.g. main)", text: $branch)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "arrow.triangle.branch"))
        }
    }

    private var pathSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Path")
                .font(DesignSystem.Fonts.sans(14, weight: .semibold))
                .foregroundStyle(colors.textPrimary)

            if collection.origin?.git != nil {
                Text(relativePathLabel)
                    .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                TextField("Relative path (e.g. collections/api.har)", text: $relativePath)
                    .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "doc"))
                Text("Relative path to the Git source subdirectory (if configured).")
                    .font(DesignSystem.Fonts.mono(11))
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }

    private var commitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commit Message")
                .font(DesignSystem.Fonts.sans(14, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
            TextField("Message", text: $commitMessage)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "text.quote"))
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tag (optional)")
                .font(DesignSystem.Fonts.sans(14, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
            TextField("Tag name (e.g. v1.2.3)", text: $tagName)
                .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "tag"))
            Text("If set, FRTMProxy will create an annotated tag after the push.")
                .font(DesignSystem.Fonts.mono(11))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            ControlButton(
                title: collection.origin?.git == nil ? "Publish" : "Push",
                systemImage: "arrow.up.circle",
                style: .filled(colors),
                disabled: isWorking || !canPublish
            ) {
                Task { await publish() }
            }

            if isWorking {
                ProgressView()
                    .progressViewStyle(.circular)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var lockedSource: GitCollectionSource? {
        guard let origin = collection.origin?.git else { return nil }
        return viewModel.gitCollectionSources.first(where: { $0.id == origin.sourceID })
    }

    private var canPublish: Bool {
        guard !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard viewModel.gitCollectionSources.contains(where: { $0.id == selectedSourceID }) else { return false }
        if collection.origin?.git == nil {
            return !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var relativePathLabel: String {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func publish() async {
        if isWorking { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let pathToUse = collection.origin?.git?.relativePath ?? relativePath
            let trimmedTag = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            try await viewModel.pushCollectionToGit(
                collectionID: collection.id,
                sourceID: selectedSourceID,
                branch: branch,
                relativePath: pathToUse,
                commitMessage: commitMessage,
                tagName: trimmedTag.isEmpty ? nil : trimmedTag,
                authorName: settings.gitAuthorName,
                authorEmail: settings.gitAuthorEmail
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
