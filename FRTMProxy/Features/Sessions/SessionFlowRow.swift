import SwiftUI

struct SessionFlowRow: View {
    let item: CaptureSessionFlow
    let colors: DesignSystem.ColorPalette
    let onEditMetadata: () -> Void
    let onToggleBookmark: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(formattedTime)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
                    .monospacedDigit()
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
            .frame(width: DesignSystem.Metrics.scaled(72))

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(item.flow.request?.method.uppercased() ?? "—")
                        .font(DesignSystem.Fonts.label)
                        .foregroundStyle(DesignSystem.Colors.methodColor(item.flow.request?.method ?? "", palette: colors))
                    Text(displayURL)
                        .font(DesignSystem.Fonts.monoBody)
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let status = item.flow.response?.status {
                        Text(status, format: .number.grouping(.never))
                            .font(DesignSystem.Fonts.label)
                            .foregroundStyle(statusColor)
                    }
                    Button(item.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: item.isBookmarked ? "star.fill" : "star") {
                        onToggleBookmark()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(item.isBookmarked ? colors.warning : colors.textSecondary)
                }

                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(DesignSystem.Fonts.body)
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button("Open Flow", systemImage: "arrow.up.right.square") { onOpen() }
                        .buttonStyle(.borderless)
                    Button(item.note?.isEmpty == false ? "Edit Note" : "Add Note", systemImage: "note.text") {
                        onEditMetadata()
                    }
                    .buttonStyle(.borderless)
                }
                .font(DesignSystem.Fonts.caption)
            }
            .padding(DesignSystem.Spacing.md)
            .background(colors.surface)
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md)
                    .stroke(colors.border, lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: DesignSystem.Radius.md))
        }
        .contextMenu {
            Button(item.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: item.isBookmarked ? "star.slash" : "star") {
                onToggleBookmark()
            }
            Button("Edit Note", systemImage: "note.text") { onEditMetadata() }
            Divider()
            Button("Open Flow", systemImage: "arrow.up.right.square") { onOpen() }
        }
    }

    private var displayURL: String {
        item.flow.request?.url ?? "Unknown URL"
    }

    private var formattedTime: String {
        guard let timestamp = item.flow.responseTimestamp ?? item.flow.requestTimestamp ?? item.flow.timestamp else {
            return "—"
        }
        return Date(timeIntervalSince1970: timestamp).formatted(date: .omitted, time: .standard)
    }

    private var statusColor: Color {
        guard let status = item.flow.response?.status else { return colors.textSecondary }
        if status >= 500 { return colors.danger }
        if status >= 400 { return colors.warning }
        return colors.success
    }
}
