import Foundation

enum CaptureLaunchProfile: String, Codable, CaseIterable, Sendable {
    case standardEnvironment
    case chromium
    case electron
}
