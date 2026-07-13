import SwiftUI

struct SettingsThemesTab: View {
    @EnvironmentObject private var settings: SettingsStore
    let colors: DesignSystem.ColorPalette

    var body: some View {
        SettingsTabScaffold(
            title: "Themes",
            subtitle: "Choose an appearance preset for the app UI and inspector panels.",
            colors: colors
        ) {
            InterfaceScaleSection(
                selection: $settings.interfaceScaleID,
                colors: colors
            )

            ThemePickerSection(
                title: "Automatic",
                subtitle: "Match macOS appearance and keep the app's original colors.",
                themes: ThemeLibrary.automaticThemes,
                selection: $settings.selectedThemeID,
                colors: colors
            )

            ThemePickerSection(
                title: "Light Themes",
                subtitle: "Palettes designed for bright environments.",
                themes: ThemeLibrary.lightThemes,
                selection: $settings.selectedThemeID,
                colors: colors
            )

            ThemePickerSection(
                title: "Dark Themes",
                subtitle: "Ideal for night sessions or low-light environments.",
                themes: ThemeLibrary.darkThemes,
                selection: $settings.selectedThemeID,
                colors: colors
            )
        }
    }
}

private struct InterfaceScaleSection: View {
    @Binding var selection: String
    let colors: DesignSystem.ColorPalette

    private var selectedScale: DesignSystem.InterfaceScale {
        DesignSystem.InterfaceScale.option(with: selection)
    }

    var body: some View {
        SettingsCard(
            title: "Interface Scale",
            subtitle: "Choose the global UI density. M matches the current default.",
            colors: colors
        ) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(DesignSystem.InterfaceScale.allCases) { option in
                        scaleButton(option)
                    }
                }

                Text(selectedScale.summary)
                    .font(DesignSystem.Fonts.sans(11, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func scaleButton(_ option: DesignSystem.InterfaceScale) -> some View {
        let isSelected = selection == option.id
        Button {
            selection = option.id
        } label: {
            Text(option.label)
                .font(DesignSystem.Fonts.mono(12, weight: .bold))
                .foregroundStyle(isSelected ? colors.accent : colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                        .fill(isSelected ? colors.accent.opacity(0.12) : colors.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                        .stroke(isSelected ? colors.accent.opacity(0.7) : colors.border.opacity(0.8), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
