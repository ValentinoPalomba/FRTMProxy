import SwiftUI

struct SettingsOnboardingTab: View {
    let colors: DesignSystem.ColorPalette

    var body: some View {
        SettingsTabScaffold(
            title: "Onboarding",
            subtitle: "Reset the guided tour and feature highlights.",
            colors: colors
        ) {
            SettingsCard(title: "Guided Tour", colors: colors) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    ControlButton(
                        title: "Restart guided tour",
                        systemImage: "arrow.counterclockwise",
                        style: .destructive(colors)
                    ) {
                        OnboardingManager().resetOnboarding()
                    }

                    Text("Show the interactive tour of the app's main features again.")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }
}
