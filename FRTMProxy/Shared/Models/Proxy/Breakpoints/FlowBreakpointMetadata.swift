import Foundation

struct FlowBreakpointMetadata: Codable, Equatable {
    let phase: FlowBreakpointPhase
    let state: FlowBreakpointState
    let key: String
}
