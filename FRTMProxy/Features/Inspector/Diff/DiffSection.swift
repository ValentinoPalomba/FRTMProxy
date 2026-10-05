enum DiffSection: String, CaseIterable, Sendable {
    case requestBody = "Request Body", responseBody = "Response Body"
    case requestHeaders = "Request Headers", responseHeaders = "Response Headers"
    var label: String { rawValue }
}
