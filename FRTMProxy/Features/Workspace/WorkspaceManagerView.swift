import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceManagerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore

    @State private var model: WorkspaceManagerModel
    @State private var isImporting = false
    @State private var isChoosingExportRoot = false

    private let exportBundle: WorkspaceBundle?
    private let onImport: (WorkspaceImportPlan) throws -> WorkspaceImportResult

    init(
        service: WorkspaceBundleService = WorkspaceBundleService(),
        exportBundle: WorkspaceBundle? = nil,
        onImport: @escaping (WorkspaceImportPlan) throws -> WorkspaceImportResult
    ) {
        _model = State(initialValue: WorkspaceManagerModel(service: service))
        self.exportBundle = exportBundle
        self.onImport = onImport
    }

    var body: some View {
        let colors = DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)

        VStack(spacing: 0) {
            WorkspaceManagerHeader(
                isWorking: model.isWorking,
                canExport: exportBundle != nil,
                colors: colors,
                onImport: { isImporting = true },
                onExport: { isChoosingExportRoot = true },
                onClose: { dismiss() }
            )

            Divider()

            Group {
                if let plan = model.importPlan {
                    WorkspaceImportPreviewView(
                        plan: plan,
                        result: model.importResult,
                        isWorking: model.isWorking,
                        colors: colors,
                        onApply: { model.applyImport(using: onImport) },
                        onDiscard: model.discardImport
                    )
                } else if let bundle = exportBundle {
                    WorkspaceBundleDetailView(
                        bundle: bundle,
                        lastExportURL: model.lastExportURL,
                        colors: colors
                    )
                } else {
                    StateView(
                        kind: .empty(
                            title: "No Workspace Loaded",
                            message: "Import a workspace directory or export the current debugging setup.",
                            systemImage: "shippingbox"
                        ),
                        palette: colors
                    )
                }
            }
            .padding(DesignSystem.Spacing.xl)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(colors.background)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case let .success(url):
                Task {
                    await model.prepareImport(from: url)
                }
            case let .failure(error):
                model.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isChoosingExportRoot,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case let .success(url):
                guard let exportBundle else { return }
                Task {
                    await model.exportWorkspace(exportBundle, toSelectedRoot: url)
                }
            case let .failure(error):
                model.errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Workspace operation failed",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct WorkspaceImportPreviewView: View {
    let plan: WorkspaceImportPlan
    let result: WorkspaceImportResult?
    let isWorking: Bool
    let colors: DesignSystem.ColorPalette
    let onApply: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(result == nil ? "Review Import" : "Import Complete")
                        .font(DesignSystem.Fonts.heading)
                        .foregroundStyle(colors.textPrimary)
                    Text(
                        result == nil
                            ? "Confirm the supported resources before changing the current setup."
                            : "\(result?.appliedResources.count ?? 0) applied, \(result?.skippedResources.count ?? 0) skipped."
                    )
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(colors.textSecondary)
                }

                Spacer()

                ControlButton(
                    title: result == nil ? "Cancel" : "Done",
                    systemImage: result == nil ? "xmark" : "checkmark",
                    style: .ghost(colors),
                    disabled: isWorking,
                    action: onDiscard
                )
                if result == nil {
                    ControlButton(
                        title: "Apply Workspace",
                        systemImage: "checkmark.circle",
                        style: .filled(colors),
                        disabled: isWorking || (plan.resourcesToApply.isEmpty && plan.bundle.manifest.inspectorPreferences == nil),
                        action: onApply
                    )
                }
            }

            WorkspaceSummaryCard(
                bundle: plan.bundle,
                lastExportURL: nil,
                colors: colors
            )

            if result?.inspectorPreferencesApplied == true {
                Label("Inspector preferences applied", systemImage: "checkmark.circle").foregroundStyle(colors.success)
            }
            Text("Resources")
                .font(DesignSystem.Fonts.heading)
                .foregroundStyle(colors.textPrimary)

            List(plan.resources) { resource in
                WorkspaceImportResourceRow(
                    resource: resource,
                    didApply: result?.appliedResources.contains(resource) == true,
                    colors: colors
                )
            }
            .scrollContentBackground(.hidden)
            .background(colors.surface)
            .clipShape(.rect(cornerRadius: DesignSystem.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .strokeBorder(colors.border, lineWidth: 1)
            }
        }
    }
}

private struct WorkspaceImportResourceRow: View {
    let resource: WorkspaceImportResource
    let didApply: Bool
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: DesignSystem.Spacing.lg)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(resource.reference.identifier)
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                Text(resource.reference.path)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                if case let .skip(reason) = resource.disposition {
                    skipReason(reason)
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }

            Spacer()

            statusLabel
            Text(Int64(resource.byteCount), format: .byteCount(style: .file))
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if didApply {
            Text("Applied")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(statusColor)
        } else {
            switch resource.disposition {
            case .apply:
                Text("Will apply")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(statusColor)
            case .skip:
                Text("Skipped")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(statusColor)
            }
        }
    }

    @ViewBuilder
    private func skipReason(_ reason: WorkspaceImportSkipReason) -> some View {
        switch reason {
        case .javascriptRequiresManualImport:
            Text("JavaScript files are preserved but not imported as script rules.")
        case .unsupportedResourceType:
            Text("This resource type is not supported by this version.")
        }
    }

    private var statusIcon: String {
        if didApply {
            return "checkmark.circle.fill"
        }
        switch resource.disposition {
        case .apply:
            return "checkmark.circle"
        case .skip:
            return "minus.circle"
        }
    }

    private var statusColor: Color {
        if didApply {
            return colors.success
        }
        switch resource.disposition {
        case .apply:
            return colors.accent
        case .skip:
            return colors.textSecondary
        }
    }
}

private struct WorkspaceManagerHeader: View {
    let isWorking: Bool
    let canExport: Bool
    let colors: DesignSystem.ColorPalette
    let onImport: () -> Void
    let onExport: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Workspaces")
                    .font(DesignSystem.Fonts.title)
                    .foregroundStyle(colors.textPrimary)
                Text("Import or export a local, Git-friendly debugging workspace.")
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(colors.textSecondary)
            }

            Spacer()

            if isWorking {
                ProgressView("Working…")
                    .controlSize(.small)
                    .font(DesignSystem.Fonts.caption)
            }

            ControlButton(
                title: "Import",
                systemImage: "square.and.arrow.down",
                style: .ghost(colors),
                disabled: isWorking,
                action: onImport
            )
            ControlButton(
                title: "Export",
                systemImage: "square.and.arrow.up",
                style: .filled(colors),
                disabled: isWorking || !canExport,
                action: onExport
            )
            ControlButton(
                title: "Close",
                systemImage: "xmark",
                style: .ghost(colors),
                disabled: isWorking,
                action: onClose
            )
        }
        .padding(DesignSystem.Spacing.xl)
        .background(colors.surface)
    }
}

private struct WorkspaceBundleDetailView: View {
    let bundle: WorkspaceBundle
    let lastExportURL: URL?
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            WorkspaceSummaryCard(bundle: bundle, lastExportURL: lastExportURL, colors: colors)
            WorkspaceResourceList(resources: bundle.resources, colors: colors)
        }
    }
}

private struct WorkspaceSummaryCard: View {
    let bundle: WorkspaceBundle
    let lastExportURL: URL?
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Image(systemName: "shippingbox")
                    .foregroundStyle(colors.accent)
                Text(bundle.manifest.displayName)
                    .font(DesignSystem.Fonts.heading)
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                Text("Schema \(bundle.manifest.schemaVersion)")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
            }

            if let preferences = bundle.manifest.inspectorPreferences {
                Text("Inspector: \(preferences.headerColumns.count) header columns; configuration and sort order will replace local preferences.")
                    .font(.caption)
                    .foregroundStyle(colors.textSecondary)
                if let scopes = preferences.focusSets {
                    Text("Focus sets: \(scopes.count); replaces local saved focus sets.").font(.caption)
                    ForEach(scopes) { scope in
                        Text("\(scope.name): \(scope.filter.searchText)").font(.caption).textSelection(.enabled)
                        Text("Hosts: \(scope.filter.activePinnedHosts.sorted().joined(separator: ", ")) · Apps: \(scope.filter.activePinnedApps.sorted().joined(separator: ", ")) · Devices: \(scope.filter.activeClientIPs.sorted().joined(separator: ", ")) · mapped=\(scope.filter.showMappedOnly) · errors=\(scope.filter.showErrorsOnly)")
                            .font(.caption).textSelection(.enabled)
                    }
                }
                if let noise = preferences.noiseControl {
                    Text("Noise: \(noise.enabled ? "enabled" : "disabled") · \(noise.query)")
                        .font(.caption).textSelection(.enabled)
                }
                ForEach(preferences.headerColumns) { column in
                    Text(column.title).font(.caption).foregroundStyle(colors.textSecondary)
                }
            }
            Text(bundle.manifest.summary ?? bundle.manifest.identifier)
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(colors.textSecondary)

            if let lastExportURL {
                Label(lastExportURL.path, systemImage: "checkmark.circle")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.success)
                    .lineLimit(1)
                    .help(lastExportURL.path)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .surfaceCard(fill: colors.surface, stroke: colors.border, shadowOpacity: 0.08)
    }
}

private struct WorkspaceResourceList: View {
    let resources: [WorkspaceResourcePayload]
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Resources")
                .font(DesignSystem.Fonts.heading)
                .foregroundStyle(colors.textPrimary)

            List(resources.sorted { $0.reference.path < $1.reference.path }, id: \.reference.path) { resource in
                WorkspaceResourceRow(resource: resource, colors: colors)
            }
            .scrollContentBackground(.hidden)
            .background(colors.surface)
            .clipShape(.rect(cornerRadius: DesignSystem.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .strokeBorder(colors.border, lineWidth: 1)
            }
            .overlay {
                if resources.isEmpty {
                    ContentUnavailableView(
                        "No Resources",
                        systemImage: "doc",
                        description: Text("The workspace manifest does not reference any resources.")
                    )
                }
            }
        }
    }
}

private struct WorkspaceResourceRow: View {
    let resource: WorkspaceResourcePayload
    let colors: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "doc.text")
                .foregroundStyle(colors.textSecondary)
                .frame(width: DesignSystem.Spacing.lg)
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(resource.reference.identifier)
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                Text(resource.reference.path)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(resource.kind.rawValue)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
            Text(Int64(resource.data.count), format: .byteCount(style: .file))
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}
