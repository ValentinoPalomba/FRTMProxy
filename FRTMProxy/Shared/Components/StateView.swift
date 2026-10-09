import SwiftUI

enum ContentStateKind {
    case empty(title: String, message: String?, systemImage: String)
    case loading(message: String?)
    case failed(title: String, message: String?, retry: (() -> Void)?)
}

struct StateView: View {
    let kind: ContentStateKind
    var palette: DesignSystem.ColorPalette

    var body: some View {
        switch kind {
        case let .empty(title, message, systemImage):
            ContentUnavailableView {
                Label(LocalizedStringKey(title), systemImage: systemImage)
                    .font(DesignSystem.Fonts.heading)
                    .foregroundStyle(palette.textPrimary)
            } description: {
                if let message {
                    Text(LocalizedStringKey(message))
                        .font(DesignSystem.Fonts.body)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(4)
                        .help(Text(LocalizedStringKey(message)))
                }
            }
        case let .loading(message):
            VStack(spacing: DesignSystem.Spacing.md) {
                ProgressView()
                    .controlSize(.small)
                    .tint(palette.accent)
                if let message {
                    Text(LocalizedStringKey(message))
                        .font(DesignSystem.Fonts.body)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(title, message, retry):
            ContentUnavailableView {
                Label(LocalizedStringKey(title), systemImage: "exclamationmark.triangle")
                    .font(DesignSystem.Fonts.heading)
                    .foregroundStyle(palette.danger)
            } description: {
                if let message {
                    Text(LocalizedStringKey(message))
                        .font(DesignSystem.Fonts.body)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(4)
                        .help(Text(LocalizedStringKey(message)))
                }
            } actions: {
                if let retry {
                    ControlButton(title: "Retry", systemImage: "arrow.clockwise", style: .filled(palette), action: retry)
                }
            }
        }
    }
}
