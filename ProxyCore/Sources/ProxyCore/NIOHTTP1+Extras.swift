import Foundation
import NIOHTTP1

extension HTTPHeaders {
    func asFlatDictionary() -> [String: String] {
        var out: [String: String] = [:]
        for (name, value) in self {
            out[name] = value
        }
        return out
    }

    mutating func replaceOrAdd(name: String, value: String) {
        self.remove(name: name)
        self.add(name: name, value: value)
    }
}
