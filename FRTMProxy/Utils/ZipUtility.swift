import Foundation

enum ZipUtilityError: LocalizedError {
    case zipFailed(String)
    case unzipFailed(String)

    var errorDescription: String? {
        switch self {
        case .zipFailed(let output):
            return "Impossibile creare l'archivio zip: \(output)"
        case .unzipFailed(let output):
            return "Impossibile estrarre l'archivio: \(output)"
        }
    }
}

enum ZipUtility {
    static func zipItem(at sourceURL: URL, to destinationURL: URL) throws {
        let parent = sourceURL.deletingLastPathComponent()
        let folderName = sourceURL.lastPathComponent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", destinationURL.path, folderName]
        process.currentDirectoryURL = parent
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "zip fallito"
            throw ZipUtilityError.zipFailed(message)
        }
    }

    static func unzipItem(at archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", archiveURL.path, "-d", destinationURL.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "unzip fallito"
            throw ZipUtilityError.unzipFailed(message)
        }
    }
}
