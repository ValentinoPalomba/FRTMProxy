import SwiftUI

struct AppRootView: View {
    private var viewModel: ProxyViewModel
    @StateObject private var rulesViewModel: MapRuleViewModel

    init(
        viewModel: ProxyViewModel,
        rulesViewModel: MapRuleViewModel = MapRuleViewModel()
    ) {
        self.viewModel = viewModel
        _rulesViewModel = StateObject(wrappedValue: rulesViewModel)
    }

    var body: some View {
        NavigationStack {
            InspectorScreen(viewModel: viewModel, rulesViewModel: rulesViewModel)
                .navigationTitle("FRTMProxy Inspector")
        }
    }
}
