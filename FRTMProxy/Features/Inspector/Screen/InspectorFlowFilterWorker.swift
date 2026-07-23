import Foundation

actor InspectorFlowFilterWorker {
    private let cache = FlowFilter.Cache()

    func project(
        flows: [MitmFlow],
        filter: FlowFilter
    ) throws -> (flows: [MitmFlow], clientIPs: [String]) {
        try Task.checkCancellation()
        let filteredFlows = try filter.applyCancellable(to: flows, using: cache)
        try Task.checkCancellation()

        let clientIPs = Array(
            Set(flows.lazy.map(\.clientIP).filter { !$0.isEmpty })
        ).sorted()

        try Task.checkCancellation()
        return (filteredFlows, clientIPs)
    }
}
