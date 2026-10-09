import Foundation

enum LiveFlowMemoryBudget {
    static let maximumBytes = 64 * 1024 * 1024
    static let maximumWebSocketBytes = 4 * 1024 * 1024

    static func cost(_ flow: MitmFlow) -> Int {
        func headers(_ dictionary: [String: String]?, _ fields: [HTTPHeaderField]?) -> Int {
            (dictionary ?? [:]).reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
                + (fields ?? []).reduce(0) { $0 + $1.name.utf8.count + $1.value.utf8.count }
        }
        // Payload estimate; RSS also includes Swift/Combine/UI allocations and in-flight events.
        var bytes = 1024 + flow.id.utf8.count
        bytes += flow.request?.url.utf8.count ?? 0
        bytes += flow.request?.body?.utf8.count ?? 0
        bytes += flow.response?.body?.utf8.count ?? 0
        bytes += headers(flow.request?.headers, flow.request?.headerFields)
        bytes += headers(flow.response?.headers, flow.response?.headerFields)
        bytes += flow.websocketMessages.reduce(0) { $0 + $1.content.utf8.count + $1.id.utf8.count + 32 }
        return bytes
    }

    static func trimWebSocket(_ flow: inout MitmFlow, maximumBytes: Int = maximumWebSocketBytes) -> Int {
        var bytes = flow.websocketMessages.reduce(0) { $0 + $1.content.utf8.count }
        var removed = 0
        while removed < flow.websocketMessages.count,
              flow.websocketMessages.count - removed > 1000 || bytes > maximumBytes {
            bytes -= flow.websocketMessages[removed].content.utf8.count
            removed += 1
        }
        if removed > 0 {
            flow.websocketMessages.removeFirst(removed)
            flow.livePreviewWarning = "Live WebSocket preview limited to 1000 frames / 4 MiB. Older or oversized frames are omitted; recorded sessions receive events before this limit."
        }
        return removed
    }

    static func retain(_ flows: [String: MitmFlow], weights: [String: Int], maximumCount: Int = 500,
                       maximumBytes: Int = maximumBytes) -> [String: MitmFlow] {
        func activity(_ flow: MitmFlow) -> TimeInterval {
            max(flow.responseTimestamp ?? flow.requestTimestamp ?? flow.timestamp ?? 0, flow.websocketMessages.last?.timestamp ?? 0)
        }
        let ordered = flows.values.sorted {
            let waitingA = $0.breakpoint?.state == .waiting, waitingB = $1.breakpoint?.state == .waiting
            if waitingA != waitingB { return waitingA }
            let a = activity($0), b = activity($1)
            return a == b ? $0.id < $1.id : a > b
        }
        var retained: [String: MitmFlow] = [:]
        var bytes = 0
        for flow in ordered {
            let weight = weights[flow.id] ?? cost(flow)
            guard retained.count < maximumCount, weight <= maximumBytes - bytes else { continue }
            retained[flow.id] = flow
            bytes += weight
        }
        return retained
    }
}
