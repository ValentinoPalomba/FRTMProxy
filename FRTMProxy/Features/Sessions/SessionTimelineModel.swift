import Foundation
import Observation

@MainActor
@Observable
final class SessionTimelineModel {
    private(set) var sessionID: UUID?
    private(set) var loadingGeneration = UUID()
    private var flowIndexes: [String: Int] = [:]
    private var corruptIDs = Set<String>()
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
        loadingGeneration = UUID()
        flowIndexes = [:]
        corruptIDs = []
        flows = []
        nextCursor = nil
        corruptFlowIDs = []
        hasLoadedPage = false
        isLoading = false
        errorMessage = nil
    }

    @discardableResult
    func startLoading() -> UUID {
        loadingGeneration = UUID()
        isLoading = true
        errorMessage = nil
        return loadingGeneration
    }

    func receive(_ page: CaptureSessionPage, for sessionID: UUID, generation: UUID? = nil) {
        guard self.sessionID == sessionID, generation == nil || generation == loadingGeneration else { return }
        for incoming in page.flows {
            if let index = flowIndexes[incoming.id] {
                flows[index] = incoming
            } else {
                flowIndexes[incoming.id] = flows.count
                flows.append(incoming)
            }
        }
        for flowID in page.corruptFlowIDs where corruptIDs.insert(flowID).inserted {
            corruptFlowIDs.append(flowID)
        }
        nextCursor = page.nextCursor
        hasLoadedPage = true
        isLoading = false
        errorMessage = nil
    }

    func fail(_ error: Error, for sessionID: UUID, generation: UUID? = nil) {
        guard self.sessionID == sessionID, generation == nil || generation == loadingGeneration else { return }
        isLoading = false
        errorMessage = error.localizedDescription
    }

    func updateMetadata(flowID: String, note: String?, isBookmarked: Bool) {
        guard let index = flowIndexes[flowID] else { return }
        flows[index].note = note
        flows[index].isBookmarked = isBookmarked
    }
}
