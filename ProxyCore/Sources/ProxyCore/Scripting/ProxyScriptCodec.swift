import Foundation

enum ProxyScriptCodec {
    static func makeJSRequest(_ request: ProxyRequest) -> JSONValue {
        let url = URL(string: request.url)
        let comps = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }

        var queriesObj: [String: JSONValue] = [:]
        if let items = comps?.queryItems {
            for qi in items {
                queriesObj[qi.name] = .string(qi.value ?? "")
            }
        }

        var headersObj: [String: JSONValue] = [:]
        headersObj.reserveCapacity(request.headers.count)
        for (k, v) in request.headers {
            headersObj[k] = .string(v)
        }

        let bodyData = request.bodyPreview ?? Data()
        let bodyValue: JSONValue? = {
            guard !bodyData.isEmpty else { return nil }
            if let s = String(data: bodyData, encoding: .utf8) {
                return .string(s)
            }
            return .array(bodyData.map { .number(Double($0)) })
        }()

        let rawBodyValue: JSONValue? = bodyData.isEmpty ? nil : .array(bodyData.map { .number(Double($0)) })

        var obj: [String: JSONValue] = [
            "host": .string(url?.host ?? ""),
            "url": .string(request.url),
            "path": .string(comps?.percentEncodedPath ?? ""),
            "queries": .object(queriesObj),
            "headers": .object(headersObj),
            "method": .string(request.method),
        ]
        if let bodyValue {
            obj["body"] = bodyValue
        } else {
            obj["body"] = .null
        }
        if let rawBodyValue {
            obj["rawBody"] = rawBodyValue
        }

        return .object(obj)
    }

    static func makeJSResponse(_ response: ProxyResponse) -> JSONValue {
        var headersObj: [String: JSONValue] = [:]
        headersObj.reserveCapacity(response.headers.count)
        for (k, v) in response.headers {
            headersObj[k] = .string(v)
        }

        let bodyData = response.bodyPreview ?? Data()
        let bodyValue: JSONValue? = {
            guard !bodyData.isEmpty else { return nil }
            if let s = String(data: bodyData, encoding: .utf8) {
                return .string(s)
            }
            return .array(bodyData.map { .number(Double($0)) })
        }()
        let rawBodyValue: JSONValue? = bodyData.isEmpty ? nil : .array(bodyData.map { .number(Double($0)) })

        var obj: [String: JSONValue] = [
            "headers": .object(headersObj),
            "statusCode": .number(Double(response.statusCode)),
        ]

        if let bodyValue {
            obj["body"] = bodyValue
        } else {
            obj["body"] = .null
        }
        if let rawBodyValue {
            obj["rawBody"] = rawBodyValue
        }

        return .object(obj)
    }

    static func applyJSRequestObject(_ js: JSONValue, to request: inout ProxyRequest) {
        guard case .object(let obj) = js else { return }

        if let method = obj["method"]?.stringValue, !method.isEmpty {
            request.method = method
        }

        if let url = obj["url"]?.stringValue, !url.isEmpty {
            request.url = url
        } else {
            // Best-effort: apply path/queries to the existing URL.
            if var comps = URLComponents(string: request.url) {
                if let path = obj["path"]?.stringValue, !path.isEmpty {
                    comps.percentEncodedPath = path
                }
                if let queries = obj["queries"]?.objectValue {
                    let items: [URLQueryItem] = queries.map { (k, v) in
                        URLQueryItem(name: k, value: v.stringValue ?? "")
                    }
                    comps.queryItems = items.isEmpty ? nil : items
                }
                request.url = comps.string ?? request.url
            }
        }

        if let headers = obj["headers"]?.objectValue {
            var out: [String: String] = [:]
            out.reserveCapacity(headers.count)
            for (k, v) in headers {
                switch v {
                case .string(let s):
                    out[k] = s
                case .number(let n):
                    out[k] = String(n)
                case .bool(let b):
                    out[k] = b ? "true" : "false"
                case .array(let a):
                    let joined = a.compactMap { $0.stringValue ?? $0.intValue.map(String.init) }.joined(separator: ", ")
                    out[k] = joined
                case .object:
                    out[k] = ""
                case .null:
                    out[k] = ""
                }
            }
            removeHeaderCaseInsensitive("Content-Encoding", from: &out)
            request.headers = out
        }

        if obj.keys.contains("body") || obj.keys.contains("rawBody") {
            // If body is explicitly present, treat null as deletion.
            if let body = obj["body"] {
                if case .null = body {
                    request.bodyPreview = nil
                    request.bodyIsTruncated = false
                    request.rawBodySize = 0
                } else if let data = decodeBody(body) {
                    request.bodyPreview = data
                    request.bodyIsTruncated = false
                    request.rawBodySize = data.count
                }
            } else if let raw = obj["rawBody"], let data = decodeBody(raw) {
                request.bodyPreview = data
                request.bodyIsTruncated = false
                request.rawBodySize = data.count
            }
        }
    }

    static func applyJSResponseObject(_ js: JSONValue, to response: inout ProxyResponse) {
        guard case .object(let obj) = js else { return }

        if let code = obj["statusCode"]?.intValue {
            response.statusCode = code
        }

        if let headers = obj["headers"]?.objectValue {
            var out: [String: String] = [:]
            out.reserveCapacity(headers.count)
            for (k, v) in headers {
                switch v {
                case .string(let s):
                    out[k] = s
                case .number(let n):
                    out[k] = String(n)
                case .bool(let b):
                    out[k] = b ? "true" : "false"
                case .array(let a):
                    let joined = a.compactMap { $0.stringValue ?? $0.intValue.map(String.init) }.joined(separator: ", ")
                    out[k] = joined
                case .object:
                    out[k] = ""
                case .null:
                    out[k] = ""
                }
            }
            removeHeaderCaseInsensitive("Content-Encoding", from: &out)
            response.headers = out
        }

        if obj.keys.contains("body") || obj.keys.contains("rawBody") {
            if let body = obj["body"] {
                if case .null = body {
                    response.bodyPreview = nil
                    response.bodyIsTruncated = false
                    response.rawBodySize = 0
                } else if let data = decodeBody(body) {
                    response.bodyPreview = data
                    response.bodyIsTruncated = false
                    response.rawBodySize = data.count
                }
            } else if let raw = obj["rawBody"], let data = decodeBody(raw) {
                response.bodyPreview = data
                response.bodyIsTruncated = false
                response.rawBodySize = data.count
            }
        }
    }

    static func responseFromRequestMapScriptResult(_ js: JSONValue, request: ProxyRequest) -> ProxyResponse? {
        guard case .object(let obj) = js else { return nil }

        let status = obj["statusCode"]?.intValue ?? 200
        var headers: [String: String] = [:]
        if let h = obj["headers"]?.objectValue {
            for (k, v) in h {
                headers[k] = v.stringValue ?? v.intValue.map(String.init) ?? ""
            }
        }
        removeHeaderCaseInsensitive("Content-Encoding", from: &headers)

        let bodyData: Data? = {
            if let body = obj["body"], case .null = body {
                return nil
            }
            if let body = obj["body"], let data = decodeBody(body) {
                return data
            }
            if let raw = obj["rawBody"], let data = decodeBody(raw) {
                return data
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
            rawBodySize: bodyData?.count
        )
    }

    private static func decodeBody(_ value: JSONValue) -> Data? {
        switch value {
        case .string(let s):
            return Data(s.utf8)
        case .array(let a):
            let bytes: [UInt8] = a.compactMap { v in
                if let i = v.intValue { return UInt8(clamping: i) }
                if case .number(let n) = v { return UInt8(clamping: Int(n)) }
                return nil
            }
            return Data(bytes)
        case .number(let n):
            return Data(String(n).utf8)
        case .bool(let b):
            return Data((b ? "true" : "false").utf8)
        case .object, .null:
            return nil
        }
    }

    private static func removeHeaderCaseInsensitive(_ name: String, from headers: inout [String: String]) {
        headers.keys
            .filter { $0.caseInsensitiveCompare(name) == .orderedSame }
            .forEach { headers.removeValue(forKey: $0) }
    }
}

