import Foundation

enum SelectiveCaptureLaunchState: Equatable {
    case idle
    case launching
    case running(displayName: String)
    case failed(message: String)
    case terminated(displayName: String, exitCode: Int32?)

    var isActive: Bool {
        switch self {
        case .launching, .running:
            true
        case .idle, .failed, .terminated:
            false
        }
    }
}
