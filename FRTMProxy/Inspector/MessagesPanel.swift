import SwiftUI

struct MessagesPanel: View {
    let title: String
    let flow: MitmFlow
    let colors: DesignSystem.ColorPalette

    private struct DisplayMessage: Identifiable, Hashable {
        let id = UUID()
        let fromClient: Bool
        let content: String
        let contentType: String?
        let timestamp: TimeInterval
    }

    private var messages: [DisplayMessage] {
        let wsMessages = flow.webSocketMessages.map {
            DisplayMessage(fromClient: $0.fromClient, content: $0.content, contentType: $0.contentType, timestamp: $0.timestamp)
        }
        let grpcMessages = flow.grpcMessages.map {
            DisplayMessage(fromClient: $0.fromClient, content: $0.content, contentType: "application/grpc", timestamp: $0.timestamp)
        }
        return (wsMessages + grpcMessages).sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MessagesPanelHeader(title: title, colors: colors)

            if messages.isEmpty {
                Text("Nessun messaggio disponibile")
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            MessageRow(message: message, colors: colors)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 1) // Prevent clipping shadow
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colors.border.opacity(0.65), lineWidth: 1)
                )
        )
    }
}

private struct MessagesPanelHeader: View {
    let title: String
    let colors: DesignSystem.ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DesignSystem.Fonts.sans(16, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
            Divider().overlay(colors.border.opacity(0.5))
        }
    }
}

private struct MessageRow: View {
    let message: DisplayMessage
    let colors: DesignSystem.ColorPalette

    private var isBinary: Bool {
        message.contentType == "binary" || message.contentType == "application/grpc"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                directionLabel
                timestampLabel
                Spacer()
            }
            content
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colors.surfaceElevated)
                .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
        )
    }

    private var directionLabel: some View {
        Text(message.fromClient ? "Client →" : "← Server")
            .font(DesignSystem.Fonts.sans(11, weight: .bold))
            .foregroundStyle(message.fromClient ? colors.textSecondary : colors.accent)
    }

    private var timestampLabel: some View {
        Text(Date(timeIntervalSince1970: message.timestamp).formatted(date: .abbreviated, time: .standard))
            .font(DesignSystem.Fonts.mono(10))
            .foregroundStyle(colors.textDisabled)
    }

    @ViewBuilder
    private var content: some View {
        if isBinary {
            Text(formattedBinaryData(message.content))
                .font(DesignSystem.Fonts.mono(12))
                .textSelection(.enabled)
                .foregroundStyle(colors.textPrimary)
        } else {
            Text(message.content)
                .font(DesignSystem.Fonts.mono(12))
                .textSelection(.enabled)
                .foregroundStyle(colors.textPrimary)
        }
    }

    private func formattedBinaryData(_ content: String) -> String {
        let base64String: String
        if content.starts(with: "data:application/grpc;base64,") {
            base64String = String(content.dropFirst("data:application/grpc;base64,".count))
        } else {
            base64String = content
        }
        guard let data = Data(base64Encoded: base64String) else { return "Invalid Base64 Data" }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
