import Foundation

public struct RequestRewriteInterceptor: ProxyInterceptor {
    public let store: RequestRewriteStore
    public let baseDirectory: URL

    public init(store: RequestRewriteStore, baseDirectory: URL) {
        self.store = store
        self.baseDirectory = baseDirectory
    }

    public var priority: Int { -700 }

    public func onRequest(_ request: ProxyRequest) async -> ProxyRequest? {
        var req = request

        if let match = await store.match(url: req.url, method: req.method, allowedTypes: [.requestReplace, .requestUpdate]) {
            switch match.rule.type {
            case .requestReplace:
                for item in match.items where item.enabled {
                    applyReplaceRequest(&req, item: item)
                }
            case .requestUpdate:
                for item in match.items where item.enabled {
                    applyUpdateRequest(&req, item: item)
                }
            default:
                break
            }
        }

        // Optional redirect support (ProxyPin exposes this separately; we apply it last).
        if let redirect = await store.resolveRedirect(url: req.url) {
            req.url = redirect
        }

        return req
    }

    public func onResponse(request: ProxyRequest, response: ProxyResponse) async -> ProxyResponse? {
        var res = response

        if let match = await store.match(url: request.url, method: request.method, allowedTypes: [.responseReplace, .responseUpdate]) {
            switch match.rule.type {
            case .responseReplace:
                for item in match.items where item.enabled {
                    applyReplaceResponse(&res, item: item)
                }
            case .responseUpdate:
                for item in match.items where item.enabled {
                    applyUpdateResponse(&res, item: item)
                }
            default:
                break
            }
        }

        return res
    }

    private func applyReplaceRequest(_ req: inout ProxyRequest, item: RequestRewriteStore.RewriteItem) {
        switch item.type {
        case .replaceRequestLine:
            if let m = item.method, !m.isEmpty {
                req.method = m
            }
            guard let comps = URLComponents(string: req.url) else { return }
            var updated = comps
            if let path = item.path, !path.isEmpty {
                updated.percentEncodedPath = path
            }
            if let q = item.queryParam {
                updated.percentEncodedQuery = q.isEmpty ? nil : q
            }
            req.url = updated.string ?? req.url

        case .replaceRequestHeader:
            if let headers = item.headers {
                for (k, v) in headers {
                    req.headers[k] = v
                }
            }

        case .replaceRequestBody:
            if let bodyType = item.bodyType?.lowercased(), bodyType == "file", let path = item.bodyFile {
                if let data = readFileBytes(path) {
                    req.bodyPreview = data
                    req.bodyIsTruncated = false
                    req.rawBodySize = data.count
                }
                return
            }
            if let body = item.body {
                let data = Data(body.utf8)
                req.bodyPreview = data
                req.bodyIsTruncated = false
                req.rawBodySize = data.count
            }

        default:
            break
        }
    }

    private func applyUpdateRequest(_ req: inout ProxyRequest, item: RequestRewriteStore.RewriteItem) {
        switch item.type {
        case .addQueryParam, .removeQueryParam, .updateQueryParam:
            updateQuery(&req, item: item)
        default:
            applyUpdateMessage(&req.headers, body: &req.bodyPreview, item: item)
        }
    }

    private func applyReplaceResponse(_ res: inout ProxyResponse, item: RequestRewriteStore.RewriteItem) {
        switch item.type {
        case .replaceResponseStatus:
            if let code = item.statusCode {
                res.statusCode = code
            }

        case .replaceResponseHeader:
            if let headers = item.headers {
                for (k, v) in headers {
                    res.headers[k] = v
                }
            }

        case .replaceResponseBody:
            if let bodyType = item.bodyType?.lowercased(), bodyType == "file", let path = item.bodyFile {
                if let data = readFileBytes(path) {
                    res.bodyPreview = data
                    res.bodyIsTruncated = false
                    res.rawBodySize = data.count
                }
                return
            }
            if let body = item.body {
                let data = Data(body.utf8)
                res.bodyPreview = data
                res.bodyIsTruncated = false
                res.rawBodySize = data.count
            }

        default:
            break
        }
    }

    private func applyUpdateResponse(_ res: inout ProxyResponse, item: RequestRewriteStore.RewriteItem) {
        applyUpdateMessage(&res.headers, body: &res.bodyPreview, item: item)
    }

    private func updateQuery(_ req: inout ProxyRequest, item: RequestRewriteStore.RewriteItem) {
        guard var comps = URLComponents(string: req.url) else { return }
        var items = comps.queryItems ?? []

        switch item.type {
        case .addQueryParam:
            guard let key = item.key, !key.isEmpty else { return }
            items.append(URLQueryItem(name: key, value: item.value ?? ""))

        case .removeQueryParam:
            guard let key = item.key, !key.isEmpty else { return }
            let valueRegex = item.value.flatMap { try? NSRegularExpression(pattern: $0, options: []) }
            items.removeAll { qi in
                guard qi.name == key else { return false }
                if let valueRegex, let v = qi.value {
                    let r = NSRange(v.startIndex..<v.endIndex, in: v)
                    return valueRegex.firstMatch(in: v, options: [], range: r) != nil
                }
                return true
            }

        case .updateQueryParam:
            guard let keyPattern = item.key, !keyPattern.isEmpty else { return }
            guard let regex = try? NSRegularExpression(pattern: keyPattern, options: []) else { return }
            let replacement = item.value ?? ""
            for i in items.indices {
                let line = "\(items[i].name)=\(items[i].value ?? "")"
                let r = NSRange(line.startIndex..<line.endIndex, in: line)
                if regex.firstMatch(in: line, options: [], range: r) != nil {
                    let replaced = regex.stringByReplacingMatches(in: line, options: [], range: r, withTemplate: replacement)
                    let parts = replaced.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    let newKey = parts.first.map(String.init) ?? items[i].name
                    let newValue = parts.count > 1 ? String(parts[1]) : ""
                    items[i] = URLQueryItem(name: newKey, value: newValue)
                    break
                }
            }

        default:
            break
        }

        comps.queryItems = items.isEmpty ? nil : items
        req.url = comps.string ?? req.url
    }

    private func applyUpdateMessage(_ headers: inout [String: String], body: inout Data?, item: RequestRewriteStore.RewriteItem) {
        switch item.type {
        case .updateBody:
            guard let key = item.key, let regex = try? NSRegularExpression(pattern: key, options: []) else { return }
            let replacement = item.value ?? ""
            guard let bodyData = body, let bodyString = String(data: bodyData, encoding: .utf8) else { return }
            let r = NSRange(bodyString.startIndex..<bodyString.endIndex, in: bodyString)
            let updated = regex.stringByReplacingMatches(in: bodyString, options: [], range: r, withTemplate: replacement)
            body = Data(updated.utf8)

            // Best-effort: ensure downstream doesn't treat this as compressed.
            headers.removeValue(forKey: "Content-Encoding")
            headers.removeValue(forKey: "content-encoding")

        case .addHeader:
            guard let key = item.key, !key.isEmpty else { return }
            headers[key] = item.value ?? ""

        case .removeHeader:
            guard let key = item.key, !key.isEmpty else { return }
            if let pattern = item.value, !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                // Only remove if the value matches the regex.
                let current = headers.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })
                if let currentValue = current?.value {
                    let r = NSRange(currentValue.startIndex..<currentValue.endIndex, in: currentValue)
                    guard regex.firstMatch(in: currentValue, options: [], range: r) != nil else { return }
                } else {
                    return
                }
            }
            headers.keys.filter { $0.caseInsensitiveCompare(key) == .orderedSame }.forEach { headers.removeValue(forKey: $0) }

        case .updateHeader:
            guard let keyPattern = item.key, !keyPattern.isEmpty else { return }
            guard let regex = try? NSRegularExpression(pattern: keyPattern, options: [.caseInsensitive]) else { return }
            let replacement = item.value ?? ""

            // ProxyPin semantics: match against "Name: Value" lines and allow renaming.
            for (name, value) in headers {
                let line = "\(name): \(value)"
                let r = NSRange(line.startIndex..<line.endIndex, in: line)
                if regex.firstMatch(in: line, options: [], range: r) != nil {
                    let replaced = regex.stringByReplacingMatches(in: line, options: [], range: r, withTemplate: replacement)
                    let parts = replaced.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    let newName = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
                    let newValue = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                    headers.removeValue(forKey: name)
                    headers[newName] = newValue
                    break
                }
            }

        default:
            break
        }
    }

    private func readFileBytes(_ path: String) -> Data? {
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = resolveRelativeURL(path, under: baseDirectory)
        }
        return try? Data(contentsOf: url)
    }
}

