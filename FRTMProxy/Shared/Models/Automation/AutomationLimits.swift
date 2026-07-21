import Foundation

struct AutomationLimits: Codable, Equatable, Sendable {
    static let defaults = AutomationLimits()

    let maximumRequestBytes: Int
    let maximumResponseBytes: Int
    let maximumBodyBytes: Int
    let maximumBatchItems: Int
    let requestsPerMinute: Int

    init(
        maximumRequestBytes: Int = 1_048_576,
        maximumResponseBytes: Int = 10_485_760,
        maximumBodyBytes: Int = 65_536,
        maximumBatchItems: Int = 500,
        requestsPerMinute: Int = 120
    ) {
        self.maximumRequestBytes = maximumRequestBytes
        self.maximumResponseBytes = maximumResponseBytes
        self.maximumBodyBytes = maximumBodyBytes
        self.maximumBatchItems = maximumBatchItems
        self.requestsPerMinute = requestsPerMinute
    }

    func validate() throws {
        guard maximumRequestBytes > 0 else { throw AutomationLimitError.nonPositive("maximumRequestBytes") }
        guard maximumResponseBytes > 0 else { throw AutomationLimitError.nonPositive("maximumResponseBytes") }
        guard maximumBodyBytes > 0 else { throw AutomationLimitError.nonPositive("maximumBodyBytes") }
        guard maximumBodyBytes <= maximumResponseBytes else {
            throw AutomationLimitError.bodyExceedsResponse
        }
        guard maximumBatchItems > 0 else { throw AutomationLimitError.nonPositive("maximumBatchItems") }
        guard requestsPerMinute > 0 else { throw AutomationLimitError.nonPositive("requestsPerMinute") }
    }

    func validateRequest(byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= maximumRequestBytes else {
            throw AutomationLimitError.requestTooLarge(limit: maximumRequestBytes)
        }
    }

    func validateResponse(byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= maximumResponseBytes else {
            throw AutomationLimitError.responseTooLarge(limit: maximumResponseBytes)
        }
    }

    func validateBatch(itemCount: Int) throws {
        guard itemCount >= 0, itemCount <= maximumBatchItems else {
            throw AutomationLimitError.batchTooLarge(limit: maximumBatchItems)
        }
    }
}

enum AutomationLimitError: Error, Equatable {
    case nonPositive(String)
    case bodyExceedsResponse
    case requestTooLarge(limit: Int)
    case responseTooLarge(limit: Int)
    case batchTooLarge(limit: Int)
}
