import Foundation

/// ProxyPin-style scripting (`script.json` + `scripts/*.js` or remoteUrl).
public struct ScriptInterceptor: ProxyInterceptor {
    public let store: ScriptStore
    public let engine: JavaScriptEngine

    public init(store: ScriptStore, engine: JavaScriptEngine) {
        self.store = store
        self.engine = engine
    }

    public init(store: ScriptStore, baseDirectory: URL, logger: @escaping JavaScriptEngine.Logger = { _ in }) {
        self.store = store
        self.engine = JavaScriptEngine(baseDirectory: baseDirectory, logger: logger)
    }

    public var priority: Int { 10 }

    public func onRequest(_ request: ProxyRequest) async -> ProxyRequest? {
        var req = request

        let scripts = await store.matchingScripts(url: req.url)
        guard !scripts.isEmpty else { return req }

        for item in scripts {
            guard let script = await store.getScript(for: item) else { continue }

            let ctx = await store.scriptContext(for: item)
            let jsReq = ProxyScriptCodec.makeJSRequest(req)

            do {
                guard let result = try await engine.evalOnRequest(script: script, context: ctx, request: jsReq) else {
                    return nil
                }

                await store.updateSession(fromReturnedObject: result)

                if case .object(let root) = result, let sc = root["scriptContext"] {
                    await store.storeContextForRequestID(req.id, context: sc)
                }

                ProxyScriptCodec.applyJSRequestObject(result, to: &req)
            } catch {
                // Best-effort: don't block traffic on script failures.
                continue
            }
        }

        return req
    }

    public func onResponse(request: ProxyRequest, response: ProxyResponse) async -> ProxyResponse? {
        var res = response

        let scripts = await store.matchingScripts(url: request.url)
        guard !scripts.isEmpty else {
            await store.clearContextForRequestID(request.id)
            return res
        }

        let storedContext = await store.contextForRequestID(request.id)

        for item in scripts {
            guard let script = await store.getScript(for: item) else { continue }

            let ctx: JSONValue
            if let storedContext {
                ctx = storedContext
            } else {
                ctx = await store.scriptContext(for: item)
            }
            let jsReq = ProxyScriptCodec.makeJSRequest(request)
            let jsRes = ProxyScriptCodec.makeJSResponse(res)

            do {
                guard let result = try await engine.evalOnResponse(script: script, context: ctx, request: jsReq, response: jsRes) else {
                    await store.clearContextForRequestID(request.id)
                    return nil
                }

                await store.updateSession(fromReturnedObject: result)
                ProxyScriptCodec.applyJSResponseObject(result, to: &res)
            } catch {
                // Match ProxyPin's intent: surface script failures without crashing the proxy.
                let msg = "Script exec error: \(error)"
                res.statusCode = 500
                res.headers["Content-Type"] = "text/plain; charset=utf-8"
                res.bodyPreview = Data(msg.utf8)
                res.bodyIsTruncated = false
                res.rawBodySize = msg.utf8.count
                await store.clearContextForRequestID(request.id)
                return res
            }
        }

        await store.clearContextForRequestID(request.id)
        return res
    }
}
