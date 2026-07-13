import SwiftUI

struct SettingsGitTab: View {
    @EnvironmentObject private var settings: SettingsStore
    let colors: DesignSystem.ColorPalette

    var body: some View {
        SettingsTabScaffold(
            title: "Git",
            subtitle: "Commit identity used when publishing collections to a Git repository.",
            colors: colors
        ) {
            SettingsCard(title: "Commit Identity", colors: colors) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    TextField("Commit author name", text: $settings.gitAuthorName)
                        .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "person"))
                    TextField("Commit author email", text: $settings.gitAuthorEmail)
                        .textFieldStyle(ProxyTextFieldStyle(palette: colors, leadingIcon: "envelope"))
                    Text("Used when FRTMProxy creates commits while publishing collections to a Git repository.")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }
}
