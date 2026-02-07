import Foundation

extension JSONValue {
    /// Convert to a Foundation object compatible with `JSONSerialization`.
    func toFoundationObject() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .number(let n):
            return n
        case .string(let s):
            return s
        case .array(let a):
            return a.map { $0.toFoundationObject() }
        case .object(let o):
            return o.mapValues { $0.toFoundationObject() }
        }
    }

    /// Convert from a Foundation object produced by `JSONSerialization` or `JavaScriptCore`.
    static func fromFoundationObject(_ obj: Any) -> JSONValue? {
        if obj is NSNull {
            return .null
        }

        if let b = obj as? Bool {
            return .bool(b)
        }

        if let n = obj as? NSNumber {
            // Distinguish Bool vs number (NSNumber can represent either).
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        }

        if let s = obj as? String {
            return .string(s)
        }

        if let arr = obj as? [Any] {
            return .array(arr.compactMap { JSONValue.fromFoundationObject($0) })
        }

        if let dict = obj as? [String: Any] {
            var out: [String: JSONValue] = [:]
            out.reserveCapacity(dict.count)
            for (k, v) in dict {
                out[k] = JSONValue.fromFoundationObject(v) ?? .null
            }
            return .object(out)
        }

        // JavaScriptCore can bridge dictionaries as NSDictionary/NSArray.
        if let dict = obj as? NSDictionary {
            var out: [String: JSONValue] = [:]
            out.reserveCapacity(dict.count)
            for (k, v) in dict {
                guard let key = k as? String else { continue }
                out[key] = JSONValue.fromFoundationObject(v) ?? .null
            }
            return .object(out)
        }

        if let arr = obj as? NSArray {
            return .array(arr.compactMap { JSONValue.fromFoundationObject($0) })
        }

        return nil
    }
}
