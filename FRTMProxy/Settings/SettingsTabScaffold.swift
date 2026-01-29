import SwiftUI

struct SettingsTabScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    let colors: DesignSystem.ColorPalette
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        colors: DesignSystem.ColorPalette,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.colors = colors
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsTabHeader(title: title, subtitle: subtitle, colors: colors)
                content
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .background(colors.background)
    }
}
