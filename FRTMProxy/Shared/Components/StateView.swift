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
                Label(title, systemImage: systemImage)
            } description: {
                if let message { Text(message) }
            }
        case let .loading(message):
            VStack(spacing: DesignSystem.Spacing.md) {
                ProgressView()
                    .controlSize(.small)
                if let message {
                    Text(message)
                        .font(DesignSystem.Fonts.body)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(title, message, retry):
            ContentUnavailableView {
                Label(title, systemImage: "exclamationmark.triangle")
            } description: {
                if let message { Text(message) }
            } actions: {
                if let retry {
                    Button("Retry", action: retry)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
