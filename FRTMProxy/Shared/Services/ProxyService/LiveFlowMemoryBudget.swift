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
        return 1024 + flow.id.utf8.count + (flow.request?.url.utf8.count ?? 0)
            + (flow.request?.body?.utf8.count ?? 0) + (flow.response?.body?.utf8.count ?? 0)
            + headers(flow.request?.headers, flow.request?.headerFields)
            + headers(flow.response?.headers, flow.response?.headerFields)
            + flow.websocketMessages.reduce(0) { $0 + $1.content.utf8.count + $1.id.utf8.count + 32 }
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
            flow.livePreviewWarning = String(localized: "Live WebSocket preview limited to 1000 frames / 4 MiB. Older or oversized frames are omitted; recorded sessions receive events before this limit.", bundle: AppLocalization.bundle)
        }
        return removed
    }

    static func retain(_ flows: [String: MitmFlow], weights: [String: Int], maximumCount: Int = 500,
                       maximumBytes: Int = maximumBytes) -> [String: MitmFlow] {
        func activity(_ flow: MitmFlow) -> TimeInterval {
            max(flow.responseTimestamp ?? flow.requestTimestamp ?? flow.timestamp ?? 0, flow.websocketMessages.last?.timestamp ?? 0)
        }
        func preferred(_ first: MitmFlow, _ second: MitmFlow) -> Bool {
            let waitingA = first.breakpoint?.state == .waiting, waitingB = second.breakpoint?.state == .waiting
            if waitingA != waitingB { return waitingA }
            let firstActivity = activity(first), secondActivity = activity(second)
            return firstActivity == secondActivity ? first.id < second.id : firstActivity > secondActivity
        }
        // Steady capture normally adds one small flow to a full live window.
        // Select the one eviction in linear time rather than sorting 501 rows.
        if flows.count == maximumCount + 1,
           flows.values.reduce(0, { $0 + (weights[$1.id] ?? cost($1)) }) <= maximumBytes,
           let oldest = flows.values.max(by: preferred) {
            var retained = flows
            retained.removeValue(forKey: oldest.id)
            return retained
        }
        let ordered = flows.values.sorted(by: preferred)
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
