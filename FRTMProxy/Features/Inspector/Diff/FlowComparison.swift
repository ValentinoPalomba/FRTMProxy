import Foundation

enum FlowComparison {
    enum Mode: String, CaseIterable, Sendable { case structure = "Structure", bytes = "Bytes" }
    struct Input: Equatable, Sendable {
        let a: MitmFlow
        let b: MitmFlow
        let section: DiffSection
        let mode: Mode
    }
    struct Row: Identifiable, Sendable {
        let id: String
        let a: String?
        let b: String?
    }
    struct Result: Sendable {
        let rows: [Row]
        let warning: String?
    }
    enum Failure: LocalizedError {
        case limit
        var errorDescription: String? { "Comparison limit exceeded (2 MiB per body, 50,000 nodes, depth 64, 4,000 changes, 256 KiB output, 8 MiB prepared paths/values, 1 million text search cells). Export the originals to compare larger bodies." }
    }

    static func compare(_ input: Input) throws -> Result {
        try Task.checkCancellation()
        let request = input.section == .requestBody || input.section == .requestHeaders
        let headers = input.section == .requestHeaders || input.section == .responseHeaders
        var warning: String?
        let left: [String: String], right: [String: String]
        if headers {
            let a = request ? input.a.request?.headerFields : input.a.response?.headerFields
            let b = request ? input.b.request?.headerFields : input.b.response?.headerFields
            if a == nil || b == nil { warning = "Legacy header dictionaries cannot recover duplicate occurrences." }
            left = try headerValues(a ?? fields(request ? input.a.request?.headers : input.a.response?.headers))
            right = try headerValues(b ?? fields(request ? input.b.request?.headers : input.b.response?.headers))
        } else {
            let a = request ? input.a.request?.body : input.a.response?.body
            let b = request ? input.b.request?.body : input.b.response?.body
            let truncatedA = request ? input.a.request?.bodyTruncated : input.a.response?.bodyTruncated
            let truncatedB = request ? input.b.request?.bodyTruncated : input.b.response?.bodyTruncated
            if input.mode == .bytes {
                func bytes(_ flow: MitmFlow, preview: String?) throws -> Data {
                    let reference = request ? flow.request?.originalBodyReference : flow.response?.originalBodyReference
                    if let reference {
                        return try CaptureBodyStore.load(reference: reference, flowID: flow.id,
                            phase: request ? "request" : "response", maximumBytes: 2 * 1024 * 1024)
                    }
                    warning = "Preview bytes only where the original is unavailable; decoded text may differ from wire bytes."
                    guard preview?.utf8.count ?? 0 <= 4 * ((2 * 1024 * 1024 + 2) / 3) else { throw Failure.limit }
                    if let preview, preview.hasPrefix("data:"), let comma = preview.firstIndex(of: ","),
                       preview[..<comma].hasSuffix(";base64"), let data = Data(base64Encoded: String(preview[preview.index(after: comma)...])) {
                        return data
                    }
                    return Data((preview ?? "").utf8)
                }
                let bytesA = try bytes(input.a, preview: a), bytesB = try bytes(input.b, preview: b)
                guard bytesA.count <= 2 * 1024 * 1024, bytesB.count <= 2 * 1024 * 1024 else { throw Failure.limit }
                var rows: [Row] = []
                let presentA = a != nil || (request ? input.a.request?.originalBodyReference : input.a.response?.originalBodyReference) != nil
                let presentB = b != nil || (request ? input.b.request?.originalBodyReference : input.b.response?.originalBodyReference) != nil
                if presentA != presentB { rows.append(.init(id: "body presence", a: presentA ? "present" : nil, b: presentB ? "present" : nil)) }
                if warning != nil, truncatedA == true || truncatedB == true {
                    warning = (warning ?? "") + " Captured preview is truncated; only loaded originals can establish byte equality."
                }
                for offset in stride(from: 0, to: max(bytesA.count, bytesB.count), by: 16) {
                    try Task.checkCancellation()
                    let a = offset < bytesA.count ? bytesA.subdata(in: offset..<min(offset + 16, bytesA.count)) : nil
                    let b = offset < bytesB.count ? bytesB.subdata(in: offset..<min(offset + 16, bytesB.count)) : nil
                    if a != b {
                        rows.append(.init(id: "byte \(offset)", a: a.map(hex), b: b.map(hex)))
                        guard rows.count <= 4_000 else { throw Failure.limit }
                    }
                }
                return try bounded(rows, warning: warning)
            }
            if truncatedA == true || truncatedB == true { warning = "Incomplete preview: equality here does not imply equal original bodies." }
            guard (a?.utf8.count ?? 0) <= 2 * 1024 * 1024, (b?.utf8.count ?? 0) <= 2 * 1024 * 1024 else { throw Failure.limit }
            let jsonA = a.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8), options: [.fragmentsAllowed]) }
            let jsonB = b.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8), options: [.fragmentsAllowed]) }
            guard let rootA = jsonA, let rootB = jsonB else { return try textChanges(a, b, warning: warning) }
            left = try bodyValues(rootA)
            right = try bodyValues(rootB)
        }
        var rows: [Row] = []
        for key in Set(left.keys).union(right.keys).sorted() {
            try Task.checkCancellation()
            if left[key] != right[key] {
                rows.append(.init(id: key, a: left[key], b: right[key]))
                guard rows.count <= 4_000 else { throw Failure.limit }
            }
        }
        return try bounded(rows, warning: warning)
    }

    private static func bounded(_ rows: [Row], warning: String?) throws -> Result {
        let size = rows.reduce(0) { $0 + $1.id.utf8.count + ($1.a?.utf8.count ?? 0) + ($1.b?.utf8.count ?? 0) }
        guard size <= 256 * 1024 else { throw Failure.limit }
        return Result(rows: rows, warning: warning)
    }
    private static func textChanges(_ a: String?, _ b: String?, warning: String?) throws -> Result {
        if a == b { return Result(rows: [], warning: warning) }
        if a == nil || b == nil { return try bounded([.init(id: "body", a: a, b: b)], warning: warning) }
        let linesA = (a ?? "").components(separatedBy: "\n"), linesB = (b ?? "").components(separatedBy: "\n")
        guard linesA.count <= 50_000, linesB.count <= 50_000 else { throw Failure.limit }
        var prefix = 0, suffix = 0
        while prefix < min(linesA.count, linesB.count), linesA[prefix] == linesB[prefix] {
            try Task.checkCancellation()
            prefix += 1
        }
        while suffix < min(linesA.count, linesB.count) - prefix,
              linesA[linesA.count - suffix - 1] == linesB[linesB.count - suffix - 1] {
            try Task.checkCancellation()
            suffix += 1
        }
        let middleA = Array(linesA[prefix..<(linesA.count - suffix)])
        let middleB = Array(linesB[prefix..<(linesB.count - suffix)])
        // ponytail: bound the stdlib edit search; export if the unmatched middle exceeds this budget.
        guard middleA.count * middleB.count <= 1_000_000 else { throw Failure.limit }
        try Task.checkCancellation()
        let changes = middleB.difference(from: middleA)
        guard changes.count <= 4_000 else { throw Failure.limit }
        var rows: [Row] = []
        for change in changes {
            try Task.checkCancellation()
            switch change {
            case let .remove(offset, line, _): rows.append(.init(id: "line A \(prefix + offset + 1)", a: line, b: nil))
            case let .insert(offset, line, _): rows.append(.init(id: "line B \(prefix + offset + 1)", a: nil, b: line))
            }
        }
        return try bounded(rows, warning: warning)
    }
    private static func hex(_ bytes: Data) -> String {
        bytes.map { let value = String($0, radix: 16); return value.count == 1 ? "0" + value : value }.joined(separator: " ")
    }
    private static func fields(_ dictionary: [String: String]?) -> [HTTPHeaderField] {
        (dictionary ?? [:]).sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
    }
    private static func headerValues(_ fields: [HTTPHeaderField]) throws -> [String: String] {
        var counts: [String: Int] = [:], values: [String: String] = [:]
        guard fields.count <= 4_000 else { throw Failure.limit }
        var size = 0
        for field in fields {
            try Task.checkCancellation()
            size += field.name.utf8.count + field.value.utf8.count
            guard size <= 256 * 1024 else { throw Failure.limit }
            let name = field.name.lowercased()
            let occurrence = counts[name, default: 0] + 1
            counts[name] = occurrence
            values["\(name)[\(occurrence)]"] = field.value
        }
        return values
    }
    private static func bodyValues(_ root: Any) throws -> [String: String] {
        var pending: [(String, Any, Int)] = [("$", root, 0)]
        var values: [String: String] = [:]
        var visited = 0
        var pathBytes = 1
        var valueBytes = 0
        func push(_ path: String, _ value: Any, _ depth: Int) throws {
            pathBytes += path.utf8.count
            guard pathBytes <= 8 * 1024 * 1024 else { throw Failure.limit }
            pending.append((path, value, depth))
        }
        while let (path, value, depth) = pending.popLast() {
            pathBytes -= path.utf8.count
            try Task.checkCancellation()
            visited += 1
            guard depth <= 64, visited + pending.count <= 50_000 else { throw Failure.limit }
            if let object = value as? [String: Any], !object.isEmpty {
                guard visited + pending.count + object.count <= 50_000 else { throw Failure.limit }
                for (key, child) in object {
                    let keyJSON = try JSONSerialization.data(withJSONObject: key, options: [.fragmentsAllowed])
                    try push(path + "[" + String(decoding: keyJSON, as: UTF8.self) + "]", child, depth + 1)
                }
            } else if let array = value as? [Any], !array.isEmpty {
                guard visited + pending.count + array.count <= 50_000 else { throw Failure.limit }
                for (index, child) in array.enumerated() { try push(path + "[\(index)]", child, depth + 1) }
            } else {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
                valueBytes += path.utf8.count + data.count
                guard valueBytes <= 8 * 1024 * 1024 else { throw Failure.limit }
                values[path] = String(decoding: data, as: UTF8.self)
            }
        }
        return values
    }
}
