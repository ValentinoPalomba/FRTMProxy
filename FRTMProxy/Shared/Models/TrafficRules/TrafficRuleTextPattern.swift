import Foundation

/// A reusable string predicate shared by the Swift UI and the bridge contract.
/// Invalid regular expressions are reported by `validationError` and never match.
struct TrafficRuleTextPattern: Codable, Hashable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case exact
        case wildcard
        case regularExpression
    }

    var value: String
    var mode: Mode
    var isCaseSensitive: Bool

    init(value: String, mode: Mode = .exact, isCaseSensitive: Bool = true) {
        self.value = value
        self.mode = mode
        self.isCaseSensitive = isCaseSensitive
    }

    var validationError: String? {
        guard mode == .regularExpression else { return nil }
        do {
            _ = try NSRegularExpression(pattern: value, options: expressionOptions)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func matches(_ candidate: String) -> Bool {
        switch mode {
        case .exact:
            return candidate.compare(
                value,
                options: isCaseSensitive ? [] : [.caseInsensitive]
            ) == .orderedSame
        case .wildcard:
            return regularExpressionMatches(candidate, pattern: wildcardExpression)
        case .regularExpression:
            return regularExpressionMatches(candidate, pattern: value)
        }
    }

    private var expressionOptions: NSRegularExpression.Options {
        isCaseSensitive ? [] : [.caseInsensitive]
    }

    private var wildcardExpression: String {
        let escaped = NSRegularExpression.escapedPattern(for: value)
        return "^" + escaped
            .replacing("\\*", with: ".*")
            .replacing("\\?", with: ".") + "$"
    }

    private func regularExpressionMatches(_ candidate: String, pattern: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: expressionOptions) else {
            return false
        }
        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
        return expression.firstMatch(in: candidate, range: range) != nil
    }
}
