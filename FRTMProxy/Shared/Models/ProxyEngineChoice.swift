import Foundation

enum ProxyEngineChoice: String, CaseIterable, Identifiable, Codable {
    case mitmproxy = "engine.mitmproxy"
    case swiftNIO = "engine.swiftnio"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mitmproxy:
            return "mitmproxy (bundled)"
        case .swiftNIO:
            return "SwiftNIO (native)"
        }
    }

    static func engine(with id: String?) -> ProxyEngineChoice {
        guard
            let id,
            let choice = ProxyEngineChoice(rawValue: id)
        else {
            return .mitmproxy
        }
        return choice
    }
}

