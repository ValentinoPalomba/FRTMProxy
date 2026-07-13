import SwiftUI

struct LogConsoleView: View {
    let logText: String
    let colors: DesignSystem.ColorPalette
    @State private var scrollTask: Task<Void, Never>?
    private let bottomAnchorID = "log-bottom-anchor"
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Label("Log", systemImage: "terminal")
                    .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logText.isEmpty ? "No logs available" : logText)
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.accent)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(DesignSystem.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                                .fill(colors.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                                        .stroke(colors.border.opacity(0.7), lineWidth: 1)
                                )
                        )
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .onChange(of: logText) { _, _ in
                    scrollTask?.cancel()
                    scrollTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(80))
                        guard !Task.isCancelled else { return }
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .surfaceCard(fill: colors.surfaceElevated, stroke: colors.border)
    }
}
