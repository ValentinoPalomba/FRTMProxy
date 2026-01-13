import Foundation

struct TrafficProfile: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let description: String
    let systemImageName: String
    let latencyMs: Int
    let jitterMs: Int
    let downstreamKbps: Int
    let upstreamKbps: Int
    let packetLoss: Double

    var isDisabled: Bool {
        id == TrafficProfileLibrary.disabled.id
    }

    var summary: String {
        var pieces: [String] = []
        if latencyMs > 0 {
            pieces.append("\(latencyMs)ms ±\(jitterMs)ms latency")
        }
        if downstreamKbps > 0 || upstreamKbps > 0 {
            pieces.append("↓\(downstreamKbps)kbps / ↑\(upstreamKbps)kbps")
        }
        if packetLoss > 0 {
            pieces.append("\(Int(packetLoss * 100))% packet loss")
        }
        return pieces.isEmpty ? "No throttling applied" : pieces.joined(separator: " · ")
    }
}

enum TrafficProfileLibrary {
    static let disabled = TrafficProfile(
        id: "traffic.off",
        name: "No profile",
        description: "Use real network conditions.",
        systemImageName: "bolt.horizontal.circle",
        latencyMs: 0,
        jitterMs: 0,
        downstreamKbps: 0,
        upstreamKbps: 0,
        packetLoss: 0
    )

    static let presets: [TrafficProfile] = [
        disabled,
        TrafficProfile(
            id: "traffic.3g",
            name: "3G Urban",
            description: "High latency, low throughput uplink/downlink.",
            systemImageName: "antenna.radiowaves.left.and.right",
            latencyMs: 320,
            jitterMs: 60,
            downstreamKbps: 750,
            upstreamKbps: 330,
            packetLoss: 0.02
        ),
        TrafficProfile(
            id: "traffic.lte_congested",
            name: "LTE (congested)",
            description: "Simulates peak hour cellular congestion.",
            systemImageName: "cellularbars",
            latencyMs: 160,
            jitterMs: 40,
            downstreamKbps: 3000,
            upstreamKbps: 1200,
            packetLoss: 0.03
        ),
        TrafficProfile(
            id: "traffic.high_latency_vpn",
            name: "High Latency VPN",
            description: "Remote tunnel with multiple hops.",
            systemImageName: "lock.shield",
            latencyMs: 650,
            jitterMs: 120,
            downstreamKbps: 5000,
            upstreamKbps: 2000,
            packetLoss: 0.01
        ),
        TrafficProfile(
            id: "traffic.packet_loss",
            name: "Packet loss 8%",
            description: "Unstable Wi-Fi with aggressive loss.",
            systemImageName: "exclamationmark.triangle",
            latencyMs: 120,
            jitterMs: 30,
            downstreamKbps: 8000,
            upstreamKbps: 4000,
            packetLoss: 0.08
        )
    ]

    static func profile(with id: String?) -> TrafficProfile {
        guard
            let id,
            let profile = presets.first(where: { $0.id == id })
        else {
            return disabled
        }
        return profile
    }
}
