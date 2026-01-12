import SwiftUI

struct LogConsoleView: View {
    let logText: String
    let colors: DesignSystem.ColorPalette
    @State private var anchor = UUID()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Log", systemImage: "terminal")
                    .font(DesignSystem.Fonts.sans(13, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 8)
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logText.isEmpty ? "Nessun log disponibile" : logText)
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.accent)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colors.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(colors.border.opacity(0.7), lineWidth: 1)
                                )
                        )
                        .id(anchor)
                }
                .onChange(of: logText) { _ in
                    anchor = UUID()
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(anchor, anchor: .bottom)
                    }
                }
            }
        }
        .padding(12)
        .surfaceCard(fill: colors.surfaceElevated, stroke: colors.border)
    }
}
