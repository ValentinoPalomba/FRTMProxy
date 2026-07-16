import SwiftUI

struct AppRootView: View {
    private var viewModel: ProxyViewModel
    @StateObject private var rulesViewModel: MapRuleViewModel
    @StateObject private var toastCenter = ToastCenter()
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    init(
        viewModel: ProxyViewModel,
        rulesViewModel: MapRuleViewModel = MapRuleViewModel()
    ) {
        self.viewModel = viewModel
        _rulesViewModel = StateObject(wrappedValue: rulesViewModel)
    }

    private var palette: DesignSystem.ColorPalette {
        DesignSystem.Colors.palette(for: settings.activeTheme, interfaceStyle: colorScheme)
    }

    var body: some View {
        OnboardingContainer {
            NavigationStack {
                InspectorScreen(viewModel: viewModel, rulesViewModel: rulesViewModel)
                    .navigationTitle("FRTMProxy Inspector")
            }
        }
        .environmentObject(onboardingManager)
        .toastLayer(toastCenter, palette: palette)
        .onAppear {
            viewModel.onToast = { text, style in
                toastCenter.show(text, style: style)
            }
        }
    }
}
