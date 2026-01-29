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
                VStack(alignment: .leading, spacing: 12) {
                    ControlButton(
                        title: "Riavvia tutorial guidato",
                        systemImage: "arrow.counterclockwise",
                        style: .destructive(colors)
                    ) {
                        OnboardingManager().resetOnboarding()
                    }

                    Text("Mostra nuovamente il tour interattivo delle funzionalità principali dell'app.")
                        .font(DesignSystem.Fonts.mono(11))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }
}
