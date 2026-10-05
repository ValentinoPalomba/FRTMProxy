import Foundation

actor InspectorFlowFilterWorker {
    private let cache = FlowFilter.Cache()

    func project(
        flows: [MitmFlow],
        filter: FlowFilter,
        noiseQuery: String = ""
    ) throws -> (flows: [MitmFlow], clientIPs: [String]) {
        try Task.checkCancellation()
        var filteredFlows = try filter.applyCancellable(to: flows, using: cache)
        if !noiseQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hidden = try FlowFilter(searchText: noiseQuery).applyCancellable(to: flows, using: cache)
            let ids = Set(hidden.map(\.id))
            filteredFlows.removeAll { ids.contains($0.id) }
        }
        try Task.checkCancellation()

        let clientIPs = Array(
            Set(flows.lazy.map(\.clientIP).filter { !$0.isEmpty })
        ).sorted()

        try Task.checkCancellation()
        return (filteredFlows, clientIPs)
    }
}
