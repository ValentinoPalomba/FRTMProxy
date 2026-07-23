import Foundation

// MitmFlow is a value graph made exclusively of Codable Foundation value types.
// Its declaration predates strict concurrency, so the conformance lives here until
// the core model can adopt Sendable directly.
extension MitmFlow: @unchecked Sendable {}

extension MitmFlow {
    func mergingSessionSnapshot(with incoming: MitmFlow) -> MitmFlow {
        var merged = self
        if incoming.request != nil { merged.request = incoming.request }
        if incoming.response != nil { merged.response = incoming.response }
        merged.event = incoming.event
        merged.timestamp = timestamp ?? incoming.timestamp
        merged.requestTimestamp = incoming.requestTimestamp ?? requestTimestamp
        merged.responseTimestamp = incoming.responseTimestamp ?? responseTimestamp
        merged.client = incoming.client ?? client
        merged.clientApp = incoming.clientApp ?? clientApp
        merged.breakpoint = incoming.breakpoint
        if !incoming.websocketMessages.isEmpty {
            let existingIDs = Set(merged.websocketMessages.map(\.id))
            merged.websocketMessages.append(
                contentsOf: incoming.websocketMessages.filter { !existingIDs.contains($0.id) }
            )
        }
        return merged
    }
}
