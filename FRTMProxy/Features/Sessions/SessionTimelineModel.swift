import Foundation
import Observation

@MainActor
@Observable
final class SessionTimelineModel {
    private(set) var sessionID: UUID?
    private(set) var flows: [CaptureSessionFlow] = []
    private(set) var nextCursor: CaptureSessionPageCursor?
    private(set) var corruptFlowIDs: [String] = []
    private(set) var hasLoadedPage = false
    var isLoading = false
    var errorMessage: String?

    var canLoadMore: Bool {
        nextCursor != nil && !isLoading
    }

    func reset(for sessionID: UUID) {
        self.sessionID = sessionID
        flows = []
        nextCursor = nil
        corruptFlowIDs = []
        hasLoadedPage = false
        isLoading = false
        errorMessage = nil
    }

    func receive(_ page: CaptureSessionPage, for sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        var indexes = Dictionary(uniqueKeysWithValues: flows.enumerated().map { ($0.element.id, $0.offset) })
        for incoming in page.flows {
            if let index = indexes[incoming.id] {
                flows[index] = incoming
            } else {
                indexes[incoming.id] = flows.count
                flows.append(incoming)
            }
        }
        for flowID in page.corruptFlowIDs where !corruptFlowIDs.contains(flowID) {
            corruptFlowIDs.append(flowID)
        }
        nextCursor = page.nextCursor
        hasLoadedPage = true
        isLoading = false
        errorMessage = nil
    }

    func fail(_ error: Error, for sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        isLoading = false
        errorMessage = error.localizedDescription
    }

    func updateMetadata(flowID: String, note: String?, isBookmarked: Bool) {
        guard let index = flows.firstIndex(where: { $0.id == flowID }) else { return }
        flows[index].note = note
        flows[index].isBookmarked = isBookmarked
    }
}
