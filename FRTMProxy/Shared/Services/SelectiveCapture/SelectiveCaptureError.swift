import Foundation

enum SelectiveCaptureError: LocalizedError {
    case invalidApplication
    case invalidExecutable
    case executableIsNotRunnable

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            "The application must be an absolute local file URL."
        case .invalidExecutable:
            "The executable must be an absolute local file URL."
        case .executableIsNotRunnable:
            "The selected file is not executable."
        }
    }

    static func validateApplication(at url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw SelectiveCaptureError.invalidApplication
        }
    }

    static func validateExecutable(at url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw SelectiveCaptureError.invalidExecutable
        }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw SelectiveCaptureError.executableIsNotRunnable
        }
    }
}
