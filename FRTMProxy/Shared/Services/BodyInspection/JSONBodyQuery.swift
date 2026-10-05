import Foundation

enum JSONBodyQuery {
    enum Mode: String, CaseIterable, Sendable { case path = "JSONPath", keyValue = "Key / Value" }
    struct Result: Equatable, Sendable { let text: String; let count: Int }
    enum Failure: LocalizedError {
        case invalidJSON, unsupportedPath, limit
        var errorDescription: String? {
            switch self {
            case .invalidJSON: "The captured preview is not complete, valid JSON."
            case .unsupportedPath: "Supported: $, .field, [index], [*], .* and [\"quoted key\"]. Filters, slices and recursive descent are not supported."
            case .limit: "Query limit exceeded. Narrow the selection (256 selections per step, 50,000 visited nodes, 256 KiB output)."
            }
        }
    }
    private enum Step { case member(String), index(Int), wildcard }

    static func evaluate(body: String, query: String, mode: Mode) throws -> Result {
        guard body.utf8.count <= 2 * 1024 * 1024, query.utf8.count <= 1024 else { throw Failure.limit }
        try Task.checkCancellation()
        guard let root = try? JSONSerialization.jsonObject(with: Data(body.utf8), options: [.fragmentsAllowed]) else {
            throw Failure.invalidJSON
        }
        let matches: [Any]
        switch mode {
        case .path:
            var current: [Any] = [root]
            var visited = 0
            for step in try parse(query) {
                var next: [Any] = []
                for value in current {
                    try Task.checkCancellation()
                    visited += 1
                    guard visited <= 50_000 else { throw Failure.limit }
                    switch step {
                    case let .member(key):
                        if let object = value as? [String: Any], let child = object[key] { next.append(child) }
                    case let .index(index):
                        if let array = value as? [Any], array.indices.contains(index) { next.append(array[index]) }
                    case .wildcard:
                        if let array = value as? [Any] {
                            guard next.count + array.count <= 256 else { throw Failure.limit }
                            next += array
                        } else if let object = value as? [String: Any] {
                            guard next.count + object.count <= 256 else { throw Failure.limit }
                            next += object.keys.sorted().compactMap { object[$0] }
                        }
                    }
                    guard next.count <= 256 else { throw Failure.limit }
                }
                current = next
            }
            matches = current
        case .keyValue:
            var stack: [(path: String, key: String?, value: Any)] = [("$", nil, root)]
            var found: [Any] = []
            var visited = 0
            while let item = stack.popLast() {
                try Task.checkCancellation()
                visited += 1
                guard visited + stack.count <= 50_000 else { throw Failure.limit }
                let object = item.value as? [String: Any]
                let array = item.value as? [Any]
                var scalarMatches = false
                if object == nil && array == nil {
                    let encoded = try JSONSerialization.data(withJSONObject: item.value, options: [.fragmentsAllowed])
                    scalarMatches = String(decoding: encoded, as: UTF8.self).localizedStandardContains(query)
                }
                if item.key?.localizedStandardContains(query) == true || scalarMatches {
                    found.append(["path": item.path, "value": item.value])
                    guard found.count <= 256 else { throw Failure.limit }
                }
                if let object {
                    guard visited + stack.count + object.count <= 50_000 else { throw Failure.limit }
                    for key in object.keys.sorted().reversed() {
                        if let value = object[key] {
                            let encoded = try JSONSerialization.data(withJSONObject: key, options: [.fragmentsAllowed])
                            stack.append((item.path + "[" + String(decoding: encoded, as: UTF8.self) + "]", key, value))
                        }
                    }
                } else if let array {
                    guard visited + stack.count + array.count <= 50_000 else { throw Failure.limit }
                    for index in array.indices.reversed() { stack.append((item.path + "[\(index)]", nil, array[index])) }
                }
            }
            matches = found
        }
        try Task.checkCancellation()
        let output = try JSONSerialization.data(withJSONObject: matches, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        guard output.count <= 256 * 1024 else { throw Failure.limit }
        return Result(text: String(decoding: output, as: UTF8.self), count: matches.count)
    }

    private static func parse(_ query: String) throws -> [Step] {
        let characters = Array(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard characters.first == "$" else { throw Failure.unsupportedPath }
        var index = 1
        var steps: [Step] = []
        while index < characters.count {
            guard steps.count < 64 else { throw Failure.limit }
            if characters[index] == "." {
                index += 1
                if index < characters.count, characters[index] == "*" {
                    steps.append(.wildcard); index += 1
                } else {
                    let start = index
                    while index < characters.count, characters[index] != ".", characters[index] != "[" { index += 1 }
                    let name = String(characters[start..<index])
                    guard !name.isEmpty, name.first?.isNumber != true,
                          name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { throw Failure.unsupportedPath }
                    steps.append(.member(name))
                }
            } else if characters[index] == "[" {
                index += 1
                guard index < characters.count else { throw Failure.unsupportedPath }
                if characters[index] == "\"" {
                    let start = index
                    index += 1
                    var escaped = false
                    while index < characters.count {
                        let char = characters[index]
                        index += 1
                        if escaped { escaped = false }
                        else if char == "\\" { escaped = true }
                        else if char == "\"" { break }
                    }
                    let literal = String(characters[start..<index])
                    guard let name = try? JSONDecoder().decode(String.self, from: Data(literal.utf8)) else { throw Failure.unsupportedPath }
                    steps.append(.member(name))
                } else {
                    let start = index
                    while index < characters.count, characters[index] != "]" { index += 1 }
                    let token = String(characters[start..<index])
                    if token == "*" { steps.append(.wildcard) }
                    else if !token.isEmpty, token.utf8.allSatisfy({ (48...57).contains($0) }),
                            (token == "0" || !token.hasPrefix("0")), let number = Int(token) { steps.append(.index(number)) }
                    else { throw Failure.unsupportedPath }
                }
                guard index < characters.count, characters[index] == "]" else { throw Failure.unsupportedPath }
                index += 1
            } else { throw Failure.unsupportedPath }
        }
        return steps
    }
}
