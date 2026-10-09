import SwiftUI
import UniformTypeIdentifiers

struct SessionHARImportView: View {
    let colors: DesignSystem.ColorPalette
    let onImport: (SessionHARImporter.Prepared, String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsFilePicker = false
    @State private var prepared: SessionHARImporter.Prepared?
    @State private var name = "Imported capture"
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Import HAR").font(DesignSystem.Fonts.title)
            Text("Review before importing. Capture files may contain credentials and personal data. Imported sessions remain local and encrypted; they do not enable mocks.")
                .font(DesignSystem.Fonts.caption).foregroundStyle(colors.textSecondary)
            ControlButton(title: "Choose HAR File…", systemImage: "doc", style: .ghost(colors), disabled: isWorking) {
                showsFilePicker = true
            }
            TextField("Session name", text: $name)
                .accessibilityLabel("Session name")
                .textFieldStyle(ProxyTextFieldStyle(palette: colors))
                .disabled(isWorking)
            if let prepared {
                Text("\(prepared.items.count) transactions • \(prepared.startedAt.formatted())")
                    .font(DesignSystem.Fonts.label)
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        ForEach(prepared.items.prefix(20), id: \.flow.id) { item in
                            Text(safeURL(item.flow.request?.url))
                                .font(DesignSystem.Fonts.monoBody).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DesignSystem.Spacing.sm)
                .background(colors.surface)
                .clipShape(.rect(cornerRadius: DesignSystem.Radius.md))
                Text("""
                    Preview URLs are redacted. Stored data preserves the file, including secrets. \
                    Up to 32 MiB and 10,000 entries; body previews are limited to 2 MiB and originals are retained. \
                    Missing bodies and timing phases cannot be reconstructed.
                    """)
                    .font(DesignSystem.Fonts.caption).foregroundStyle(colors.textSecondary)
            } else {
                StateView(kind: .empty(title: "Choose a capture", message: "HAR 1.2 with HTTP or HTTPS transactions.", systemImage: "doc"), palette: colors)
            }
            if isWorking { ProgressView("Processing capture…").font(DesignSystem.Fonts.caption).tint(colors.accent) }
            if let error { Label(error, systemImage: "exclamationmark.triangle").font(DesignSystem.Fonts.caption).foregroundStyle(colors.danger).lineLimit(3).help(error) }
            HStack {
                ControlButton(title: "Cancel", systemImage: "xmark", style: .ghost(colors), disabled: isWorking) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                ControlButton(
                    title: "Import",
                    systemImage: "square.and.arrow.down",
                    style: .filled(colors),
                    disabled: prepared == nil || isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    importCapture()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .foregroundStyle(colors.textPrimary)
        .padding(DesignSystem.Spacing.lg)
        .frame(width: DesignSystem.Metrics.scaled(640), height: DesignSystem.Metrics.scaled(520))
        .background(colors.background)
        .interactiveDismissDisabled(isWorking)
        .fileImporter(isPresented: $showsFilePicker, allowedContentTypes: [.json, UTType(filenameExtension: "har") ?? .data]) { result in
            switch result {
            case .success(let url): read(url)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    private func safeURL(_ value: String?) -> String {
        (try? AutomationRedactor.redact(.init(url: value, headers: [:], body: nil)).url) ?? "URL unavailable"
    }

    private func read(_ url: URL) {
        isWorking = true
        prepared = nil
        error = nil
        Task {
            defer { isWorking = false }
            do {
                prepared = try await Task.detached(priority: .userInitiated) {
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard size <= SessionHARImporter.maximumFileBytes else { throw CocoaError(.fileReadTooLarge) }
                    return try SessionHARImporter.prepare(Data(contentsOf: url))
                }.value
                name = url.deletingPathExtension().lastPathComponent
            } catch { self.error = "Cannot read this capture: \(error.localizedDescription)" }
        }
    }

    private func importCapture() {
        guard let prepared else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do { try await onImport(prepared, name); dismiss() }
            catch { self.error = "Import failed; the draft is retained: \(error.localizedDescription)" }
        }
    }
}
