import Foundation

enum ShellCommand {
    struct Result {
        let status: Int32
        let output: String
        let error: String
        var succeeded: Bool { status == 0 }
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "", error: error.localizedDescription)
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return Result(
            status: process.terminationStatus,
            output: out.trimmingCharacters(in: .whitespacesAndNewlines),
            error: err.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
