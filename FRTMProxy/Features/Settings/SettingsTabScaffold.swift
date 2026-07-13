import SwiftUI

struct SettingsTabScaffold<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let colors: DesignSystem.ColorPalette
    let content: Content

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
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
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                SettingsTabHeader(title: title, subtitle: subtitle, colors: colors)
                content
                Spacer(minLength: 0)
            }
            .padding(DesignSystem.Spacing.xl)
        }
        .background(colors.background)
    }
}
