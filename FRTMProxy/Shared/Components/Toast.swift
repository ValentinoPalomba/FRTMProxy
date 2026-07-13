import SwiftUI

enum ToastStyle: Equatable {
    case info
    case success
    case warning
    case error
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: ToastStyle
}

@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    func show(_ text: String, style: ToastStyle = .info, duration: Duration = .seconds(3.5)) {
        current = ToastMessage(text: text, style: style)
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

private struct ToastBanner: View {
    let message: ToastMessage
    let palette: DesignSystem.ColorPalette

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: DesignSystem.Metrics.font(13), weight: .semibold))
            Text(message.text)
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .fill(palette.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6)
        )
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch message.style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch message.style {
        case .info: return palette.accent
        case .success: return palette.success
        case .warning: return palette.warning
        case .error: return palette.danger
        }
    }
}

private struct ToastLayer: ViewModifier {
    @ObservedObject var center: ToastCenter
    let palette: DesignSystem.ColorPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = center.current {
                    ToastBanner(message: toast, palette: palette)
                        .padding(.bottom, DesignSystem.Spacing.xl)
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { center.dismiss() }
                }
            }
            .animation(
                DesignSystem.Motion.adaptive(DesignSystem.Motion.base, reduceMotion: reduceMotion),
                value: center.current
            )
    }
}

extension View {
    func toastLayer(_ center: ToastCenter, palette: DesignSystem.ColorPalette) -> some View {
        modifier(ToastLayer(center: center, palette: palette))
    }
}
