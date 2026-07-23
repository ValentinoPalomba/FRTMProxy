import Foundation

enum InspectorDestination: String, Identifiable {
    case mapEditor
    case mapLocalRules
    case trafficRules
    case collections
    case retryEditor
    case breakpointEditor
    case breakpoints
    case deviceSetup
    case composer
    case scripts
    case sessions
    case selectiveCapture
    case workspace

    var id: String { rawValue }
}
