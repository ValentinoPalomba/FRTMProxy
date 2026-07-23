import Foundation

struct CaptureSessionPage: Equatable, Sendable {
    let flows: [CaptureSessionFlow]
    let nextCursor: CaptureSessionPageCursor?
    let corruptFlowIDs: [String]
}
