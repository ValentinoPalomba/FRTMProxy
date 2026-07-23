import SwiftUI

struct SessionFlowRow: View {
    let item: CaptureSessionFlow
    let colors: DesignSystem.ColorPalette
    let onEditMetadata: () -> Void
    let onToggleBookmark: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: item.isBookmarked ? "star.fill" : "star")
                .foregroundStyle(item.isBookmarked ? colors.warning : colors.textSecondary.opacity(0.45))
                .frame(width: DesignSystem.Metrics.scaled(18))
                .accessibilityLabel(item.isBookmarked ? "Bookmarked" : "Not bookmarked")

            Text(formattedTime)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(colors.textSecondary)
                .monospacedDigit()
                .frame(width: DesignSystem.Metrics.scaled(78), alignment: .leading)

            Text(item.flow.request?.method.uppercased() ?? "—")
                .font(DesignSystem.Fonts.label)
                .foregroundStyle(DesignSystem.Colors.methodColor(item.flow.request?.method ?? "", palette: colors))
                .frame(width: DesignSystem.Metrics.scaled(62), alignment: .leading)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(displayHost)
                    .font(DesignSystem.Fonts.label)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                Text(displayPath)
                    .font(DesignSystem.Fonts.monoBody)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note = item.note, !note.isEmpty {
                    Label(note, systemImage: "note.text")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DesignSystem.Spacing.sm)

            if let status = item.flow.response?.status {
                Text(status, format: .number.grouping(.never))
                    .font(DesignSystem.Fonts.label)
                    .foregroundStyle(statusColor)
                    .frame(width: DesignSystem.Metrics.scaled(44), alignment: .trailing)
            } else {
                Text("Pending")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: DesignSystem.Metrics.scaled(54), alignment: .trailing)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: onOpen)
        .contextMenu {
            Button(item.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: item.isBookmarked ? "star.slash" : "star") {
                onToggleBookmark()
            }
            Button("Edit Note", systemImage: "note.text") { onEditMetadata() }
            Divider()
            Button("Open Flow", systemImage: "arrow.up.right.square") { onOpen() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAction(named: "Open Flow", onOpen)
        .accessibilityAction(named: item.isBookmarked ? "Remove Bookmark" : "Bookmark", onToggleBookmark)
        .accessibilityAction(named: "Edit Note", onEditMetadata)
    }

    private var displayHost: String {
        guard let urlString = item.flow.request?.url,
              let url = URL(string: urlString) else {
            return "Unknown host"
        }
        return url.host ?? "Unknown host"
    }

    private var displayPath: String {
        guard let urlString = item.flow.request?.url,
              let url = URL(string: urlString) else {
            return item.flow.request?.url ?? "Unknown URL"
        }
        let path = url.path.isEmpty ? "/" : url.path
        guard let query = url.query, !query.isEmpty else { return path }
        return "\(path)?\(query)"
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

    private var accessibilitySummary: String {
        let method = item.flow.request?.method.uppercased() ?? "Unknown method"
        let status = item.flow.response?.status.map(String.init) ?? "pending"
        return "\(formattedTime), \(method), \(displayHost), \(displayPath), status \(status)"
    }
}
