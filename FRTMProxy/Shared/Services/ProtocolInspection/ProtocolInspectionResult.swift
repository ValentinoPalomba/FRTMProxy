import Foundation

struct ProtocolInspectionResult: Codable, Equatable, Sendable {
    let kind: InspectedProtocolKind
    let summary: String?
    let sections: [ProtocolInspectionSection]
}
