import Foundation
import JavaScriptCore

/// One disposable process per hook. The bridge kills it on timeout, including infinite JS loops.
enum ScriptWorker {
    static func run() {
        do {
            var input = Data()
            while true {
                let chunk = FileHandle.standardInput.availableData
                if chunk.isEmpty { break }
                guard input.count + chunk.count <= 8 * 1024 * 1024 else {
                    throw CocoaError(.fileReadTooLarge)
                }
                input.append(chunk)
            }
            guard let payload = try JSONSerialization.jsonObject(with: input) as? [String: Any],
                  let source = payload["source"] as? String,
                  let phase = payload["phase"] as? String,
                  ["request", "response"].contains(phase),
                  let flow = payload["flow"] as? [String: Any],
                  let context = JSContext() else { throw CocoaError(.fileReadCorruptFile) }
            context.setObject(flow, forKeyedSubscript: "flow" as NSString)
            context.evaluateScript(source)
            guard context.exception == nil else { throw CocoaError(.executableRuntimeMismatch) }
            let hook = phase == "request" ? "onRequest" : "onResponse"
            let expression = "typeof \(hook) === 'function' ? \(hook)(flow) : (typeof transform === 'function' ? transform(flow) : undefined)"
            guard let result = context.evaluateScript(expression), context.exception == nil,
                  let object = result.toDictionary() as? [String: Any],
                  JSONSerialization.isValidJSONObject(object) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let data = try JSONSerialization.data(withJSONObject: object)
            guard data.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            FileHandle.standardOutput.write(data)
        } catch {
            FileHandle.standardError.write(Data("Script failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
