import Foundation

/// ProxyPin-style Request Map (`request_map.json` + `request_map/*.json` items).
public struct RequestMapInterceptor: ProxyInterceptor {
    public let store: RequestMapStore
    public let baseDirectory: URL
    public let engine: JavaScriptEngine

    private let scriptSession = RequestMapScriptSession()

    public init(store: RequestMapStore, baseDirectory: URL, engine: JavaScriptEngine? = nil) {
        self.store = store
        self.baseDirectory = baseDirectory
        self.engine = engine ?? JavaScriptEngine(baseDirectory: baseDirectory)
    }

    public var priority: Int { -800 }

    public func execute(_ request: ProxyRequest) async -> ProxyResponse? {
        guard let match = await store.findMatch(url: request.url) else { return nil }

        let item = match.item

        switch match.rule.type {
        case .local:
            let status = item?.statusCode ?? 200
            let headers = item?.headers ?? [:]

            let bodyData: Data? = {
                guard let item else { return nil }
                if let bodyType = item.bodyType?.lowercased(), bodyType == "file", let file = item.bodyFile, !file.isEmpty {
                    let url = resolveRelativeURL(file, under: baseDirectory)
                    return try? Data(contentsOf: url)
                }
                if let body = item.body {
                    return Data(body.utf8)
                }
                return nil
            }()

            return ProxyResponse(
                requestID: request.id,
                httpVersion: request.httpVersion,
                streamID: request.streamID,
                statusCode: status,
                headers: headers,
                bodyPreview: bodyData,
                bodyIsTruncated: false,
                rawBodySize: bodyData.map { $0.count }
            )

        case .script:
            guard let script = item?.script, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let ctx = await scriptSession.scriptContext(ruleName: match.rule.name)
            let jsReq = ProxyScriptCodec.makeJSRequest(request)

            do {
                guard let result = try await engine.evalOnRequest(script: script, context: ctx, request: jsReq) else {
                    return nil
                }

                await scriptSession.updateSession(fromReturnedObject: result)
                return ProxyScriptCodec.responseFromRequestMapScriptResult(result, request: request)
            } catch {
                return nil
            }
        }
    }
}

private actor RequestMapScriptSession {
    private var session: JSONValue = .object([:])

    func scriptContext(ruleName: String?) -> JSONValue {
        .object([
            "scriptName": .string(ruleName ?? ""),
            "os": .string(Self.osName()),
            "session": session,
        ])
    }

    func updateSession(fromReturnedObject result: JSONValue) {
        guard
            case .object(let root) = result,
            case .object(let ctx) = root["scriptContext"],
            let sess = ctx["session"]
        else {
            return
        }
        session = sess
    }

    private static func osName() -> String {
        #if os(macOS)
        return "macos"
        #elseif os(iOS)
        return "ios"
        #elseif os(Linux)
        return "linux"
        #elseif os(Windows)
        return "windows"
        #else
        return "unknown"
        #endif
    }
}
