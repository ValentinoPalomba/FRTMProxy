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
    @EnvironmentObject private var settings: SettingsStore
    @State private var tooltipScale: CGFloat = 0.9
    @State private var tooltipOpacity: Double = 0
    @State private var highlightScale: CGFloat = 0.9
    @State private var highlightOpacity: Double = 0
    @State private var tooltipSize: CGSize = .zero

    private var step: OnboardingStep { manager.currentStep }
    private var colors: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    var body: some View {
        GeometryReader { proxy in
            let focusRect = highlightRect(in: proxy)
            let tooltipMaxWidth = min(360, proxy.size.width - 48)
            let tooltipPosition = tooltipPosition(for: focusRect, in: proxy.size)

            ZStack {
                spotlightLayer(for: focusRect)
                    .onTapGesture {
                        manager.nextStep()
                    }

                highlightView(for: focusRect)
                    .scaleEffect(highlightScale)
                    .opacity(highlightOpacity)
                    .animation(.spring(response: 0.55, dampingFraction: 0.82), value: step)

                tooltipView(maxWidth: tooltipMaxWidth)
                    .scaleEffect(tooltipScale)
                    .opacity(tooltipOpacity)
                    .position(tooltipPosition)
                    .animation(.spring(response: 0.55, dampingFraction: 0.82), value: step)
                    .background(
                        GeometryReader { tooltipProxy in
                            Color.clear.preference(key: TooltipSizePreferenceKey.self, value: tooltipProxy.size)
                        }
                    )
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
        let gradient = LinearGradient(
            colors: [colors.accent, colors.accentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return RoundedRectangle(cornerRadius: step.cornerRadius, style: .continuous)
            .fill(colors.accent.opacity(colorScheme == .dark ? 0.12 : 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: step.cornerRadius, style: .continuous)
                    .stroke(gradient, lineWidth: 2)
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .shadow(color: colors.accent.opacity(colorScheme == .dark ? 0.45 : 0.35), radius: 18)
    }

    private func tooltipView(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: stepIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.accent)
                    .padding(8)
                    .background(
                        Circle().fill(colors.accent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(DesignSystem.Fonts.sans(15, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text("\(currentStepIndex + 1) / \(OnboardingStep.allCases.count)")
                        .font(DesignSystem.Fonts.mono(11, weight: .semibold))
                        .foregroundStyle(colors.textSecondary)
                }

                Spacer()
            }

            Text(step.description)
                .font(DesignSystem.Fonts.sans(13))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                secondaryButton(title: "Salta") {
                    manager.skipOnboarding()
                }

                Spacer()

                progressDots

                if isLastStep {
                    primaryButton(title: "Inizia", color: colors.success) {
                        manager.completeOnboarding()
                    }
                } else {
                    primaryButton(title: "Avanti", color: colors.accent) {
                        manager.nextStep()
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(colors.border.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.18), radius: 20, y: 10)
        )
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<OnboardingStep.allCases.count, id: \.self) { index in
                Circle()
                    .fill(index <= currentStepIndex ? colors.accent : colors.border.opacity(0.8))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func primaryButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: 32)
                .background(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(color.opacity(0.85), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Fonts.mono(12, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 32)
                .background(colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(colors.border.opacity(0.9), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var stepIcon: String {
        switch step {
        case .startProxy:
            return "play.circle.fill"
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
        let fallbackSize = CGSize(width: 300, height: 160)
        let resolvedSize = tooltipSize == .zero ? fallbackSize : tooltipSize
        let spacing: CGFloat = 16
        let preferAbove = rect.midY > size.height * 0.6

        var x = rect.midX + step.tooltipOffset.x
        var y = preferAbove
            ? rect.minY - spacing - resolvedSize.height / 2
            : rect.maxY + spacing + resolvedSize.height / 2
        y += step.tooltipOffset.y

        let safePadding: CGFloat = 16
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
        let animation = Animation.spring(response: 0.6, dampingFraction: 0.82).delay(0.1)
        withAnimation(animation) {
            tooltipScale = 1.0
            tooltipOpacity = 1.0
            highlightScale = 1.0
            highlightOpacity = 1.0
        }
    }

    private func animateStepChange() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            tooltipScale = 0.9
            tooltipOpacity = 0
            highlightScale = 0.9
            highlightOpacity = 0
        }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.1)) {
            tooltipScale = 1.0
            tooltipOpacity = 1.0
            highlightScale = 1.0
            highlightOpacity = 1.0
        }
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
