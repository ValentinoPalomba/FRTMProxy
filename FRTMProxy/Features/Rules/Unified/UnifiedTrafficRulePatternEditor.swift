import SwiftUI

struct UnifiedTrafficRulePatternEditor: View {
    let title: String
    @Binding var pattern: TrafficRuleTextPattern?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Toggle(
                title,
                isOn: Binding(
                    get: { pattern != nil },
                    set: { isEnabled in
                        pattern = isEnabled ? (pattern ?? .init(value: "")) : nil
                    }
                )
            )
            if pattern != nil {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    TextField(
                        "Pattern",
                        text: Binding(
                            get: { pattern?.value ?? "" },
                            set: { pattern?.value = $0 }
                        )
                    )
                    Picker(
                        "Mode",
                        selection: Binding(
                            get: { pattern?.mode ?? .exact },
                            set: { pattern?.mode = $0 }
                        )
                    ) {
                        ForEach(TrafficRuleTextPattern.Mode.allCases, id: \.self) { mode in
                            Text(modeLabel(mode)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    Toggle(
                        "Case sensitive",
                        isOn: Binding(
                            get: { pattern?.isCaseSensitive ?? true },
                            set: { pattern?.isCaseSensitive = $0 }
                        )
                    )
                }
                if let error = pattern?.validationError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Invalid regular expression: \(error)")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func modeLabel(_ mode: TrafficRuleTextPattern.Mode) -> String {
        switch mode {
        case .exact: "Exact"
        case .wildcard: "Wildcard"
        case .regularExpression: "Regular expression"
        }
    }
}
