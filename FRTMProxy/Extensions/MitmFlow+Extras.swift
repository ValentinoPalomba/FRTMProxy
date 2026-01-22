import Foundation

extension MitmFlow {
    var formattedTimestamp: String {
        guard let timestamp else { return "" }
        let date = Date(timeIntervalSince1970: timestamp)
        return DateFormatter.cachedTime.string(from: date)
    }

    var clientIP: String {
        (client?.ip ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var isMapped: Bool {
        (response?.headers?["X-Map-Local"] ?? response?.headers?["x-map-local"]) != nil
    }

    var host: String {
        guard let urlString = request?.url,
              let url = URL(string: urlString) else {
            return ""
        }
        return url.host ?? urlString
    }
    
    var path: String {
        guard let urlString = request?.url,
              let url = URL(string: urlString) else {
            return ""
        }
        return url.path
    }
    
    var curlString: String? {
        guard let req = request else { return nil }
        var components: [String] = ["curl", "-X", req.method]
        components.append("\"\(req.url)\"")
        
        for (key, value) in req.headers {
            components.append("-H")
            components.append("\"\(key): \(value)\"")
        }
        
        if let body = req.body, !body.isEmpty {
            let escaped = body.replacingOccurrences(of: "\"", with: "\\\"")
            components.append("--data-binary")
            components.append("\"\(escaped)\"")
        }
        
        return components.joined(separator: " ")
    }
    
    var breakpointPhase: FlowBreakpointPhase? {
        breakpoint?.phase
    }
    
    var isBreakpointWaiting: Bool {
        breakpoint?.state == .waiting
    }
    
    var breakpointKey: String? {
        breakpoint?.key
    }
}
