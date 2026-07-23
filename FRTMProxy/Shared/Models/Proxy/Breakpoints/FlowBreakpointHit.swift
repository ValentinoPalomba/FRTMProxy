import Foundation

struct FlowBreakpointHit: Identifiable, Equatable {
    let flowID: String
    let phase: FlowBreakpointPhase
    let key: String
    let timestamp: TimeInterval?

    var id: String {
        "\(flowID)-\(phase.rawValue)"
    }
}
