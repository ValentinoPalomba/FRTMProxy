import Foundation

@main
enum FRTMProxyEntry {
    @MainActor
    static func main() async {
        #if DEBUG
        if CommandLine.arguments.contains("--composer-probe") {
            await ComposerProbe.run()
            return
        }
        #endif
        if CommandLine.arguments.contains("--script-worker") {
            ScriptWorker.run()
            return
        }
        if CommandLine.arguments.contains("--recover-proxy") {
            do {
                let owner = CommandLine.arguments.dropFirst(2).first.flatMap(Int32.init)
                try await MacOSProxyOverrideManager.shared.disableProxy(expectedOwnerPID: owner)
            } catch {
                FileHandle.standardError.write(Data("Proxy recovery failed: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }
        FRTMProxyApp.main()
    }
}
