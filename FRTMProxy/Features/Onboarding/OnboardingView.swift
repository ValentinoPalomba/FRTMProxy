import SwiftUI
import Foundation

private struct OnboardingTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [OnboardingTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [OnboardingTarget: Anchor<CGRect>],
        nextValue: () -> [OnboardingTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct TooltipSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

extension View {
    func onboardingTarget(_ target: OnboardingTarget) -> some View {
        anchorPreference(key: OnboardingTargetPreferenceKey.self, value: .bounds) { [target: $0] }
    }
}

struct OnboardingOverlay: View {
    @ObservedObject var manager: OnboardingManager
    let anchors: [OnboardingTarget: Anchor<CGRect>]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settings: SettingsStore
    @State private var tooltipScale: CGFloat = 0.98
    @State private var tooltipOpacity: Double = 0
    @State private var highlightScale: CGFloat = 0.98
    @State private var highlightOpacity: Double = 0
    @State private var tooltipSize: CGSize = .zero

    private var step: OnboardingStep { manager.currentStep }
    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    var body: some View {
        GeometryReader { proxy in
            let focusRect = highlightRect(in: proxy)
            let tooltipMaxWidth = max(0, min(DesignSystem.Metrics.scaled(420), proxy.size.width - DesignSystem.Spacing.xxl * 2))
            let tooltipPosition = tooltipPosition(for: focusRect, in: proxy.size)

            ZStack {
                Button {
                    manager.nextStep()
                } label: {
                    spotlightLayer(for: focusRect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next onboarding step")

                highlightView(for: focusRect)
                    .scaleEffect(highlightScale)
                    .opacity(highlightOpacity)
                    .allowsHitTesting(false)
                    .animation(DesignSystem.Motion.adaptive(DesignSystem.Motion.base, reduceMotion: reduceMotion), value: step)

                tooltipView(maxWidth: tooltipMaxWidth)
                    .scaleEffect(tooltipScale)
                    .opacity(tooltipOpacity)
                    .position(tooltipPosition)
                    .animation(DesignSystem.Motion.adaptive(DesignSystem.Motion.base, reduceMotion: reduceMotion), value: step)
            }
            .onPreferenceChange(TooltipSizePreferenceKey.self) { tooltipSize = $0 }
            .onAppear {
                animateIn()
            }
            .onChange(of: step) { _, _ in
                animateStepChange()
            }
        }
        .ignoresSafeArea()
    }

    private func spotlightLayer(for rect: CGRect) -> some View {
        let opacity = colorScheme == .dark ? 0.72 : 0.56
        return Color.black.opacity(opacity)
            .ignoresSafeArea()
            .overlay(
                RoundedRectangle(cornerRadius: step.cornerRadius, style: .continuous)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .blendMode(.destinationOut)
            )
            .compositingGroup()
    }

    private func highlightView(for rect: CGRect) -> some View {
        return RoundedRectangle(cornerRadius: step.cornerRadius, style: .continuous)
            .fill(colors.accent.opacity(colorScheme == .dark ? 0.12 : 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: step.cornerRadius, style: .continuous)
                    .stroke(colors.accent, lineWidth: 1.5)
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .shadow(color: colors.accent.opacity(0.16), radius: DesignSystem.Spacing.sm)
    }

    private func tooltipView(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
                Image(systemName: stepIcon)
                    .font(DesignSystem.Fonts.title)
                    .foregroundStyle(colors.accent)
                    .padding(DesignSystem.Spacing.sm)
                    .background(
                        Circle().fill(colors.accent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Text(LocalizedStringKey(step.title))
                        .font(DesignSystem.Fonts.heading)
                        .foregroundStyle(colors.textPrimary)
                    Text("\(currentStepIndex + 1) / \(OnboardingStep.allCases.count)")
                        .font(DesignSystem.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(colors.textSecondary)
                }

                Spacer()
            }

            Text(LocalizedStringKey(step.description))
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                progressDots
                HStack(spacing: DesignSystem.Spacing.md) {
                    ControlButton(title: "Skip", systemImage: "xmark", style: .ghost(colors)) {
                        manager.skipOnboarding()
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    ControlButton(title: isLastStep ? "Get started" : "Next", systemImage: isLastStep ? "checkmark" : "arrow.right", style: .filled(colors)) {
                        if isLastStep { manager.completeOnboarding() }
                        else { manager.nextStep() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background {
            GeometryReader { tooltipProxy in
                Color.clear.preference(key: TooltipSizePreferenceKey.self, value: tooltipProxy.size)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                        .stroke(colors.border.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: colors.background.opacity(colorScheme == .dark ? 0.3 : 0.18), radius: DesignSystem.Spacing.md, y: DesignSystem.Spacing.xs)
        )
    }

    private var progressDots: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(0..<OnboardingStep.allCases.count, id: \.self) { index in
                Circle()
                    .fill(index <= currentStepIndex ? colors.accent : colors.border.opacity(0.8))
                    .frame(width: DesignSystem.Metrics.scaled(6), height: DesignSystem.Metrics.scaled(6))
            }
        }
    }

    private var stepIcon: String {
        switch step {
        case .startProxy:
            return "play.circle.fill"
        case .macOSProxyOverride:
            return "globe"
        case .viewTraffic:
            return "list.bullet.rectangle.fill"
        case .filterResults:
            return "magnifyingglass.circle.fill"
        case .inspectFlow:
            return "doc.text.magnifyingglass.fill"
        case .mapResponse:
            return "arrow.triangle.2.circlepath.fill"
        }
    }

    private var currentStepIndex: Int {
        OnboardingStep.allCases.firstIndex(of: step) ?? 0
    }

    private var isLastStep: Bool {
        currentStepIndex == OnboardingStep.allCases.count - 1
    }

    private func highlightRect(in proxy: GeometryProxy) -> CGRect {
        let anchor = anchors[step.target] ?? step.fallbackTarget.flatMap { anchors[$0] }
        if let anchor {
            let rawRect = proxy[anchor].insetBy(
                dx: -step.highlightPadding,
                dy: -step.highlightPadding
            )
            return clampedRect(rawRect, in: proxy.size, padding: 12)
        }

        let fallback = step.position
        let base = anchorPoint(for: fallback.anchor, in: proxy.size)
        let center = CGPoint(x: base.x + fallback.offset.x, y: base.y + fallback.offset.y)
        let rect = CGRect(
            x: center.x - fallback.highlightSize.width / 2,
            y: center.y - fallback.highlightSize.height / 2,
            width: fallback.highlightSize.width,
            height: fallback.highlightSize.height
        )
        return clampedRect(rect, in: proxy.size, padding: 12)
    }

    private func tooltipPosition(for rect: CGRect, in size: CGSize) -> CGPoint {
        let fallbackSize = CGSize(width: DesignSystem.Metrics.scaled(420), height: DesignSystem.Metrics.scaled(220))
        let resolvedSize = tooltipSize == .zero ? fallbackSize : tooltipSize
        let spacing = DesignSystem.Spacing.lg
        let preferAbove = rect.midY > size.height * 0.6

        var x = rect.midX + step.tooltipOffset.x
        var y = preferAbove
            ? rect.minY - spacing - resolvedSize.height / 2
            : rect.maxY + spacing + resolvedSize.height / 2
        y += step.tooltipOffset.y

        let safePadding = DesignSystem.Spacing.lg
        let halfWidth = resolvedSize.width / 2
        let halfHeight = resolvedSize.height / 2
        x = min(max(x, safePadding + halfWidth), size.width - safePadding - halfWidth)
        y = min(max(y, safePadding + halfHeight), size.height - safePadding - halfHeight)
        return CGPoint(x: x, y: y)
    }

    private func anchorPoint(for alignment: Alignment, in size: CGSize) -> CGPoint {
        let x: CGFloat
        switch alignment.horizontal {
        case .leading:
            x = 0
        case .trailing:
            x = size.width
        default:
            x = size.width / 2
        }

        let y: CGFloat
        switch alignment.vertical {
        case .top:
            y = 0
        case .bottom:
            y = size.height
        default:
            y = size.height / 2
        }

        return CGPoint(x: x, y: y)
    }

    private func clampedRect(_ rect: CGRect, in size: CGSize, padding: CGFloat) -> CGRect {
        var rect = rect
        let maxX = max(padding, size.width - rect.width - padding)
        let maxY = max(padding, size.height - rect.height - padding)
        rect.origin.x = min(max(rect.origin.x, padding), maxX)
        rect.origin.y = min(max(rect.origin.y, padding), maxY)
        return rect
    }

    private func animateIn() {
        withAnimation(DesignSystem.Motion.adaptive(DesignSystem.Motion.base, reduceMotion: reduceMotion)) {
            tooltipScale = 1
            tooltipOpacity = 1
            highlightScale = 1
            highlightOpacity = 1
        }
    }

    private func animateStepChange() {
        animateIn()
    }

}

struct OnboardingContainer<Content: View>: View {
    @StateObject private var onboardingManager = OnboardingManager()
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .disabled(onboardingManager.isActive)
        }
        .overlayPreferenceValue(OnboardingTargetPreferenceKey.self) { anchors in
            if onboardingManager.isActive {
                OnboardingOverlay(manager: onboardingManager, anchors: anchors)
            }
        }
        .onAppear {
            onboardingManager.startOnboarding()
        }
        .environmentObject(onboardingManager)
    }
}
