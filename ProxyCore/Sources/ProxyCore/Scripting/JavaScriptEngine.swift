import Crypto
import Foundation
import JavaScriptCore

public enum JavaScriptEngineError: Error, CustomStringConvertible, Sendable {
    case invalidJSONPayload
    case javaScriptException(String)
    case promiseRejected(String)
    case fetchError(String)

    public var description: String {
        switch self {
        case .invalidJSONPayload:
            return "Invalid JSON payload"
        case .javaScriptException(let message):
            return "JavaScript exception: \(message)"
        case .promiseRejected(let message):
            return "JavaScript promise rejected: \(message)"
        case .fetchError(let message):
            return "Fetch error: \(message)"
        }
    }
}

/// A small JavaScriptCore-based runtime used for ProxyPin-style scripting.
///
/// Notes:
/// - JavaScriptCore is not thread-safe. We pin the JSContext to a dedicated serial queue.
/// - Async scripts are supported by awaiting returned Promises; `fetch()` is provided by a native bridge.
public final class JavaScriptEngine: @unchecked Sendable {
    public typealias Logger = @Sendable (String) -> Void

    private let baseDirectory: URL
    private let logger: Logger
    private let queue: DispatchQueue
    private let urlSession: URLSession

    // Only touched on `queue`.
    private var context: JSContext?

    public init(
        baseDirectory: URL,
        logger: @escaping Logger = { _ in }
    ) {
        self.baseDirectory = baseDirectory
        self.logger = logger
        self.queue = DispatchQueue(label: "ProxyCore.JavaScriptEngine")

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 30
        self.urlSession = URLSession(configuration: cfg)
    }

    // MARK: - Public API

    public func evalOnRequest(script: String, context: JSONValue, request: JSONValue) async throws -> JSONValue? {
        let requestJSON = try Self.jsonString(request)
        let contextJSON = try Self.jsonString(context)

        let js = """
        var request = \(requestJSON);
        var context = \(contextJSON);
        request['scriptContext'] = context;
        \(script)
        (typeof onRequest === 'function') ? onRequest(context, request) : request;
        """

        return try await evaluateToJSONValue(js)
    }

    public func evalOnResponse(script: String, context: JSONValue, request: JSONValue, response: JSONValue) async throws -> JSONValue? {
        let requestJSON = try Self.jsonString(request)
        let responseJSON = try Self.jsonString(response)
        let contextJSON = try Self.jsonString(context)

        let js = """
        var request = \(requestJSON);
        var response = \(responseJSON);
        var context = \(contextJSON);
        response['scriptContext'] = context;
        \(script)
        (typeof onResponse === 'function') ? onResponse(context, request, response) : response;
        """

        return try await evaluateToJSONValue(js)
    }

    // MARK: - Internals

    private func ensureContextLocked() {
        if context != nil { return }

        let ctx = JSContext()!

        // Capture and forward JS exceptions.
        ctx.exceptionHandler = { [logger] _, exception in
            if let exception {
                logger("[ProxyCore][JS] Unhandled exception: \(exception)\n")
            }
        }

        // console.log/info/warn/error -> logger
        let consoleBridge: @convention(block) (String, JSValue) -> Void = { [logger] level, args in
            let arr = (args.toObject() as? [Any]) ?? []
            let line = arr.map { String(describing: $0) }.joined(separator: " ")
            logger("[ProxyCore][JS][\(level)] \(line)\n")
        }
        ctx.setObject(consoleBridge, forKeyedSubscript: "__proxycore_console" as NSString)

        // md5(any) -> hex string
        let md5Bridge: @convention(block) (JSValue) -> String = { input in
            let data: Data = {
                if input.isString {
                    return Data((input.toString() ?? "").utf8)
                }
                if let arr = input.toObject() as? [Any] {
                    let bytes = arr.compactMap { ($0 as? NSNumber)?.uint8Value }
                    return Data(bytes)
                }
                return Data((input.toString() ?? "").utf8)
            }()
            let digest = Insecure.MD5.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        ctx.setObject(md5Bridge, forKeyedSubscript: "__proxycore_md5" as NSString)

        // File helpers (sync; JS wrappers provide async versions via Promise.resolve).
        let appSupportDir: @convention(block) () -> String = { [baseDirectory] in
            baseDirectory.path
        }
        ctx.setObject(appSupportDir, forKeyedSubscript: "__proxycore_getApplicationSupportDirectory" as NSString)

        let fileReadString: @convention(block) (String) -> String? = { [baseDirectory] path in
            let url = Self.resolveScriptPath(path, baseDirectory: baseDirectory)
            return try? String(contentsOf: url, encoding: .utf8)
        }
        ctx.setObject(fileReadString, forKeyedSubscript: "__proxycore_file_readAsStringSync" as NSString)

        let fileReadBytes: @convention(block) (String) -> [Int] = { [baseDirectory] path in
            let url = Self.resolveScriptPath(path, baseDirectory: baseDirectory)
            guard let data = try? Data(contentsOf: url) else { return [] }
            return data.map { Int($0) }
        }
        ctx.setObject(fileReadBytes, forKeyedSubscript: "__proxycore_file_readAsBytesSync" as NSString)

        let fileWriteString: @convention(block) (String, String, Bool) -> Bool = { [baseDirectory] path, content, append in
            let url = Self.resolveScriptPath(path, baseDirectory: baseDirectory)
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if append, let fh = try? FileHandle(forWritingTo: url) {
                    try fh.seekToEnd()
                    if let data = content.data(using: .utf8) {
                        try fh.write(contentsOf: data)
                    }
                    try fh.close()
                } else {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                }
                return true
            } catch {
                return false
            }
        }
        ctx.setObject(fileWriteString, forKeyedSubscript: "__proxycore_file_writeAsStringSync" as NSString)

        let fileExists: @convention(block) (String) -> Bool = { [baseDirectory] path in
            let url = Self.resolveScriptPath(path, baseDirectory: baseDirectory)
            return FileManager.default.fileExists(atPath: url.path)
        }
        ctx.setObject(fileExists, forKeyedSubscript: "__proxycore_file_existsSync" as NSString)

        let fileDelete: @convention(block) (String) -> Bool = { [baseDirectory] path in
            let url = Self.resolveScriptPath(path, baseDirectory: baseDirectory)
            do {
                try FileManager.default.removeItem(at: url)
                return true
            } catch {
                return false
            }
        }
        ctx.setObject(fileDelete, forKeyedSubscript: "__proxycore_file_deleteSync" as NSString)

        // fetch bridge: JS calls __proxycore_fetchStart(id, url, options)
        let fetchStart: @convention(block) (Double, String, JSValue) -> Void = { [weak self] idNum, url, options in
            guard let self else { return }
            let id = Int(idNum)
            self.startFetchLocked(id: id, url: url, options: options)
        }
        ctx.setObject(fetchStart, forKeyedSubscript: "__proxycore_fetchStart" as NSString)

        // Install JS helpers.
        ctx.evaluateScript(Self.polyfillJS)

        context = ctx
    }

    private func startFetchLocked(id: Int, url: String, options: JSValue) {
        guard let requestURL = URL(string: url) else {
            resolveFetchLocked(id: id, result: nil, error: "Invalid URL: \(url)")
            return
        }

        var req = URLRequest(url: requestURL)
        req.timeoutInterval = 30

        if let dict = options.toObject() as? [String: Any] {
            if let method = dict["method"] as? String, !method.isEmpty {
                req.httpMethod = method.uppercased()
            }
            if let headers = dict["headers"] as? [String: Any] {
                for (k, v) in headers {
                    if let s = v as? String {
                        req.setValue(s, forHTTPHeaderField: k)
                    } else if let arr = v as? [Any] {
                        let joined = arr.map { String(describing: $0) }.joined(separator: ", ")
                        req.setValue(joined, forHTTPHeaderField: k)
                    } else {
                        req.setValue(String(describing: v), forHTTPHeaderField: k)
                    }
                }
            }
            if let body = dict["body"] {
                if let s = body as? String {
                    req.httpBody = Data(s.utf8)
                } else if let arr = body as? [Any] {
                    let bytes = arr.compactMap { ($0 as? NSNumber)?.uint8Value }
                    req.httpBody = Data(bytes)
                } else {
                    req.httpBody = Data(String(describing: body).utf8)
                }
            }
        }

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await self.urlSession.data(for: req)
                let http = response as? HTTPURLResponse

                let headers: [String: String] = {
                    var out: [String: String] = [:]
                    if let http {
                        for (k, v) in http.allHeaderFields {
                            if let ks = k as? String {
                                out[ks] = String(describing: v)
                            }
                        }
                    }
                    return out
                }()

                let status = http?.statusCode ?? 0
                let statusText = HTTPURLResponse.localizedString(forStatusCode: status)

                var raw: [String: Any] = [
                    "url": url,
                    "status": status,
                    "statusText": statusText,
                    "headers": headers,
                ]

                if let s = String(data: data, encoding: .utf8) {
                    raw["bodyText"] = s
                } else {
                    raw["bodyBase64"] = data.base64EncodedString()
                    raw["bodyText"] = data.base64EncodedString()
                }

                let bodyText = raw["bodyText"] as? String ?? ""
                let bodyBase64 = raw["bodyBase64"] as? String

                self.queue.async {
                    self.ensureContextLocked()
                    var payload: [String: Any] = [
                        "url": url,
                        "status": status,
                        "statusText": statusText,
                        "headers": headers,
                        "bodyText": bodyText,
                    ]
                    if let bodyBase64 {
                        payload["bodyBase64"] = bodyBase64
                    }
                    self.resolveFetchLocked(id: id, result: payload, error: nil)
                }
            } catch {
                self.queue.async {
                    self.ensureContextLocked()
                    self.resolveFetchLocked(id: id, result: nil, error: String(describing: error))
                }
            }
        }
    }

    private func resolveFetchLocked(id: Int, result: [String: Any]?, error: String?) {
        guard let ctx = context else { return }

        if let error, !error.isEmpty {
            ctx.objectForKeyedSubscript("__proxycore_fetchReject")?.call(withArguments: [id, error])
            return
        }

        ctx.objectForKeyedSubscript("__proxycore_fetchResolve")?.call(withArguments: [id, result ?? [:]])
    }

    private func evaluateToJSONValue(_ script: String) async throws -> JSONValue? {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.ensureContextLocked()
                guard let ctx = self.context else {
                    cont.resume(returning: nil)
                    return
                }

                ctx.exception = nil
                let result = ctx.evaluateScript(script)
                if let exc = ctx.exception {
                    ctx.exception = nil
                    cont.resume(throwing: JavaScriptEngineError.javaScriptException(exc.toString() ?? String(describing: exc)))
                    return
                }
                guard let result else {
                    cont.resume(returning: nil)
                    return
                }

                self.resolveToJSONValueLocked(result, context: ctx, depth: 0) { resolved in
                    switch resolved {
                    case .success(let json):
                        cont.resume(returning: json)
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
            }
        }
    }

    private func resolveToJSONValueLocked(
        _ value: JSValue,
        context ctx: JSContext,
        depth: Int,
        completion: @escaping (Result<JSONValue?, Error>) -> Void
    ) {
        if depth > 8 {
            completion(jsonValueFromJSValueLocked(value))
            return
        }

        let isPromise = ctx
            .objectForKeyedSubscript("__proxycore_isPromise")?
            .call(withArguments: [value])?
            .toBool() ?? false

        guard isPromise else {
            completion(jsonValueFromJSValueLocked(value))
            return
        }

        let resolve: @convention(block) (JSValue) -> Void = { resolved in
            self.resolveToJSONValueLocked(resolved, context: ctx, depth: depth + 1, completion: completion)
        }

        let reject: @convention(block) (JSValue) -> Void = { err in
            completion(.failure(JavaScriptEngineError.promiseRejected(err.toString() ?? String(describing: err))))
        }

        _ = value.invokeMethod("then", withArguments: [resolve])
        _ = value.invokeMethod("catch", withArguments: [reject])
    }

    private func jsonValueFromJSValueLocked(_ value: JSValue) -> Result<JSONValue?, Error> {
        if value.isNull || value.isUndefined {
            return .success(nil)
        }

        let obj = value.toObject() ?? NSNull()
        guard var json = JSONValue.fromFoundationObject(obj) else {
            return .failure(JavaScriptEngineError.invalidJSONPayload)
        }

        // ProxyPin compatibility: if JS returns a JSON string, decode it.
        if case .string(let s) = json {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                if let data = trimmed.data(using: .utf8),
                   let any = try? JSONSerialization.jsonObject(with: data),
                   let decoded = JSONValue.fromFoundationObject(any) {
                    json = decoded
                }
            }
        }

        return .success(json)
    }

    private static func jsonString(_ value: JSONValue) throws -> String {
        let obj = value.toFoundationObject()
        guard JSONSerialization.isValidJSONObject(obj) else { throw JavaScriptEngineError.invalidJSONPayload }
        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        return String(decoding: data, as: UTF8.self)
    }

    private static func resolveScriptPath(_ path: String, baseDirectory: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        if path.hasPrefix("~") {
            let expanded = (path as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        // Treat as relative to the ProxyCore base directory (ProxyPin-style).
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        return baseDirectory.appending(path: trimmed)
    }

    private static let polyfillJS: String = """
    function __proxycore_isPromise(x) { return x && typeof x.then === 'function'; }

    // console
    var console = {
      log: function() { __proxycore_console('log', Array.prototype.slice.call(arguments)); },
      info: function() { __proxycore_console('info', Array.prototype.slice.call(arguments)); },
      warn: function() { __proxycore_console('warn', Array.prototype.slice.call(arguments)); },
      error: function() { __proxycore_console('error', Array.prototype.slice.call(arguments)); },
    };

    // md5 bridge
    function md5(input) { return __proxycore_md5(input); }

    // File bridge (ProxyPin-compatible surface, best-effort).
    function getApplicationSupportDirectory() {
      return __proxycore_getApplicationSupportDirectory();
    }

    function File(path) {
      return {
        path: path,
        readAsString: function() { return Promise.resolve(__proxycore_file_readAsStringSync(this.path)); },
        readAsStringSync: function() { return __proxycore_file_readAsStringSync(this.path); },
        readAsBytes: function() { return Promise.resolve(__proxycore_file_readAsBytesSync(this.path)); },
        readAsBytesSync: function() { return __proxycore_file_readAsBytesSync(this.path); },
        writeAsString: function(content, append) { return Promise.resolve(__proxycore_file_writeAsStringSync(this.path, String(content), !!append)); },
        writeAsStringSync: function(content, append) { return __proxycore_file_writeAsStringSync(this.path, String(content), !!append); },
        exists: function() { return Promise.resolve(__proxycore_file_existsSync(this.path)); },
        existsSync: function() { return __proxycore_file_existsSync(this.path); },
        delete: function() { return Promise.resolve(__proxycore_file_deleteSync(this.path)); },
        deleteSync: function() { return __proxycore_file_deleteSync(this.path); },
      };
    }

    // fetch bridge
    var __proxycore_next_fetch_id = 1;
    var __proxycore_fetch_promises = {};

    function __proxycore_fetchResolve(id, raw) {
      var p = __proxycore_fetch_promises[id];
      if (!p) return;
      delete __proxycore_fetch_promises[id];
      p.resolve(raw);
    }

    function __proxycore_fetchReject(id, error) {
      var p = __proxycore_fetch_promises[id];
      if (!p) return;
      delete __proxycore_fetch_promises[id];
      p.reject(error);
    }

    function __proxycore_wrapResponse(raw) {
      var bodyText = raw.bodyText || "";
      return {
        ok: raw.status >= 200 && raw.status < 300,
        status: raw.status,
        statusText: raw.statusText || "",
        url: raw.url || "",
        headers: raw.headers || {},
        text: function() { return Promise.resolve(bodyText); },
        json: function() { return Promise.resolve(JSON.parse(bodyText)); },
      };
    }

    function fetch(url, options) {
      return new Promise(function(resolve, reject) {
        var id = __proxycore_next_fetch_id++;
        __proxycore_fetch_promises[id] = { resolve: resolve, reject: reject };
        __proxycore_fetchStart(id, String(url), options || {});
      }).then(function(raw) {
        return __proxycore_wrapResponse(raw);
      });
    }
    """
}
