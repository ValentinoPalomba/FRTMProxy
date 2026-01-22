import SwiftUI

struct AppRootView: View {
    private var viewModel: ProxyViewModel
    @StateObject private var rulesViewModel: MapRuleViewModel
    @StateObject private var onboardingManager = OnboardingManager()

    init(
        viewModel: ProxyViewModel,
        rulesViewModel: MapRuleViewModel = MapRuleViewModel()
    ) {
        self.viewModel = viewModel
        _rulesViewModel = StateObject(wrappedValue: rulesViewModel)
    }

    var body: some View {
        OnboardingContainer {
            NavigationStack {
                InspectorScreen(viewModel: viewModel, rulesViewModel: rulesViewModel)
                    .navigationTitle("FRTMProxy Inspector")
            }
        }
        .environmentObject(onboardingManager)
    }
}
