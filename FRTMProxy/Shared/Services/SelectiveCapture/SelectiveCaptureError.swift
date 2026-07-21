import Foundation

enum SelectiveCaptureError: LocalizedError {
    case invalidExecutable

    var errorDescription: String? {
        switch self {
        case .invalidExecutable:
            "The executable must be an absolute local file URL."
        }
    }
}
