import SwiftUI
import Foundation

struct FlowSplitInspector: View {
    let flow: MitmFlow
    let colors: DesignSystem.ColorPalette
    let onMapLocal: (() -> Void)?
    let onCopyUrl: (() -> Void)?
    let onCopyCurl: (() -> Void)?
    let onCopyBody: (() -> Void)?
    let isRequestBreakpointEnabled: Bool
    let isResponseBreakpointEnabled: Bool
    let onToggleBreakpoint: ((FlowBreakpointPhase, Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowHeaderView(
                flow: flow,
                colors: colors,
                onMapLocal: onMapLocal,
                onCopyUrl: onCopyUrl,
                onCopyCurl: onCopyCurl,
                onCopyBody: onCopyBody,
                isRequestBreakpointEnabled: isRequestBreakpointEnabled,
                isResponseBreakpointEnabled: isResponseBreakpointEnabled,
                onToggleBreakpoint: onToggleBreakpoint
            )

            HStack(spacing: 16) {
                FlowPanel(
                    title: "Request",
                    method: flow.request?.method,
                    status: nil,
                    headers: flow.request?.headers ?? [:],
                    queryParameters: queryParameters(in: flow.request?.url),
                    bodyFlow: flow.request?.body,
                    emptyText: "Request non disponibile",
                    isMapped: false,
                    colors: colors
                )
                .id("\(flow.id)-request")
                .frame(maxWidth: .infinity)

                FlowPanel(
                    title: "Response",
                    method: nil,
                    status: flow.response?.status,
                    headers: flow.response?.headers ?? [:],
                    queryParameters: [],
                    bodyFlow: flow.response?.body,
                    emptyText: "Response non disponibile",
                    isMapped: flow.isMapped,
                    colors: colors
                )
                .id("\(flow.id)-response")
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private func queryParameters(in urlString: String?) -> [(String, String)] {
    guard
        let urlString,
        let components = URLComponents(string: urlString),
        let items = components.queryItems
    else {
        return []
    }
    return items.map { ($0.name, $0.value ?? "") }
}
