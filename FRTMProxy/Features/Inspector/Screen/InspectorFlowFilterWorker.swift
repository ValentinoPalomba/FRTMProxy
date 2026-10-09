import Foundation

actor InspectorFlowFilterWorker {
    private let cache = FlowFilter.Cache()
    private var indexedProfile: CaptureProfile?
    private var membershipIndex: CaptureProfile.MembershipIndex?

    func project(
        flows: [MitmFlow],
        filter: FlowFilter,
        noiseQuery: String = "",
        profile: CaptureProfile? = nil
    ) throws -> (flows: [MitmFlow], clientIPs: [String]) {
        try Task.checkCancellation()
        var effectiveFilter = filter
        if profile != nil {
            // A named profile owns host/app membership; unrelated saved pins must not mask it.
            effectiveFilter.updateActivePinnedHosts([])
            effectiveFilter.updateActivePinnedApps([])
        }
        var filteredFlows = try effectiveFilter.applyCancellable(to: flows, using: cache)
        if !noiseQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hidden = try FlowFilter(searchText: noiseQuery).applyCancellable(to: flows, using: cache)
            let ids = Set(hidden.map(\.id))
            filteredFlows.removeAll { ids.contains($0.id) }
        }
        if let profile {
            if indexedProfile != profile {
                indexedProfile = profile
                membershipIndex = CaptureProfile.MembershipIndex(profile.members)
            }
            let legacyIDs: Set<String>
            if let legacyFilter = profile.legacyFilter {
                legacyIDs = Set(try legacyFilter.applyCancellable(to: filteredFlows, using: cache).map(\.id))
            } else {
                legacyIDs = []
            }
            var members: [MitmFlow] = []
            members.reserveCapacity(filteredFlows.count)
            for (index, flow) in filteredFlows.enumerated() {
                if index.isMultiple(of: 32) { try Task.checkCancellation() }
                if membershipIndex?.matches(flow) == true || legacyIDs.contains(flow.id) { members.append(flow) }
            }
            filteredFlows = members
        }
        try Task.checkCancellation()

        let clientIPs = Array(
            Set(flows.lazy.map(\.clientIP).filter { !$0.isEmpty })
        ).sorted()

        try Task.checkCancellation()
        return (filteredFlows, clientIPs)
    }
}
