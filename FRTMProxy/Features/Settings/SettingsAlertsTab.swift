import SwiftUI
import UserNotifications

struct SettingsAlertsTab: View {
    @EnvironmentObject private var settings: SettingsStore
    let colors: DesignSystem.ColorPalette

    @State private var editingRule: AlertRule?
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        SettingsTabScaffold(
            title: "Alerts",
            subtitle: "Send notifications when captured flows match your queries.",
            colors: colors
        ) {
            SettingsCard(title: "Notifications", colors: colors) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Toggle(isOn: $settings.alertsEnabled) {
                        Text("Enable alerts")
                            .font(DesignSystem.Fonts.sans(13, weight: .medium))
                            .foregroundStyle(colors.textPrimary)
                    }
                        .toggleStyle(SwitchToggleStyle())

                    Text("Notification permission: \(authorizationLabel(authorizationStatus))")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(colors.textSecondary)

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ControlButton(
                            title: "Request permission",
                            systemImage: "bell.badge",
                            style: .ghost(colors),
                            disabled: !settings.alertsEnabled
                        ) {
                            Task {
                                _ = await AlertNotificationService.shared.requestAuthorizationIfNeeded()
                                authorizationStatus = await AlertNotificationService.shared.authorizationStatus()
                            }
                        }

                        ControlButton(
                            title: "Test notification",
                            systemImage: "paperplane",
                            style: .ghost(colors),
                            disabled: !settings.alertsEnabled
                        ) {
                            Task {
                                await AlertNotificationService.shared.postAlertNotification(
                                    title: "FRTMProxy Test",
                                    body: "If you can read this, notifications work."
                                )
                            }
                        }

                        Spacer()
                    }
                }
            }

            SettingsCard(
                title: "Rules",
                subtitle: "Use the same query syntax as flow search (e.g. `host:api.example.com status:>=400`, `method:POST`, `type:json`, `-type:image`).",
                colors: colors
            ) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    HStack {
                        Text("\(settings.alertRules.count) configured")
                            .font(DesignSystem.Fonts.label)
                            .foregroundStyle(colors.textSecondary)
                        Spacer()
                        ControlButton(title: "Add Rule", systemImage: "plus", style: .filled(colors)) {
                            editingRule = AlertRule(name: "New alert", query: "status:>=400", isEnabled: true)
                        }
                    }

                    if settings.alertRules.isEmpty {
                        Text("No alert rules configured.")
                            .font(DesignSystem.Fonts.caption)
                            .foregroundStyle(colors.textSecondary)
                    } else {
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(settings.alertRules) { rule in
                                AlertRuleRow(
                                    rule: rule,
                                    colors: colors,
                                    onToggle: { isEnabled in
                                        var updated = rule
                                        updated.isEnabled = isEnabled
                                        settings.upsertAlertRule(updated)
                                    },
                                    onEdit: { editingRule = rule },
                                    onDelete: { settings.deleteAlertRule(rule.id) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .task {
            authorizationStatus = await AlertNotificationService.shared.authorizationStatus()
        }
        .sheet(item: $editingRule) { rule in
            AlertRuleEditorSheet(
                rule: rule,
                colors: colors,
                onSave: { updated in
                    settings.upsertAlertRule(updated)
                    editingRule = nil
                },
                onCancel: { editingRule = nil }
            )
        }
    }

    private func authorizationLabel(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Allowed"
        case .denied:
            return "Denied (enable in System Settings → Notifications)"
        case .notDetermined:
            return "Not determined"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }
}
