import Foundation

struct CaptureSessionFlow: Identifiable, Equatable, Sendable {
    var flow: MitmFlow
    var note: String?
    var isBookmarked: Bool

    var id: String { flow.id }
}
