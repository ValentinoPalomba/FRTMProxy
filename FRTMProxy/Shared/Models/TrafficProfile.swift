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
    let responseDelayMs: Int

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
        if responseDelayMs > 0 {
            pieces.append("+\(responseDelayMs)ms response delay")
        }
        return pieces.isEmpty ? "No throttling applied" : pieces.joined(separator: " · ")
    }
}

enum TrafficProfileLibrary {
    static let manualID = "traffic.manual"

    static let disabled = TrafficProfile(
        id: "traffic.off",
        name: "No profile",
        description: "Use real network conditions.",
        systemImageName: "bolt.horizontal.circle",
        latencyMs: 0,
        jitterMs: 0,
        downstreamKbps: 0,
        upstreamKbps: 0,
        packetLoss: 0,
        responseDelayMs: 0
    )

    static let defaultManual = manualProfile()

    private static let builtInPresets: [TrafficProfile] = [
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
            packetLoss: 0.02,
            responseDelayMs: 0
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
            packetLoss: 0.03,
            responseDelayMs: 0
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
            packetLoss: 0.01,
            responseDelayMs: 0
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
            packetLoss: 0.08,
            responseDelayMs: 0
        )
    ]

    static var presets: [TrafficProfile] {
        profiles(manualProfile: defaultManual)
    }

    static func manualProfile(
        latencyMs: Int = 0,
        jitterMs: Int = 0,
        downstreamKbps: Int = 0,
        upstreamKbps: Int = 0,
        packetLossPercent: Double = 0,
        responseDelayMs: Int = 0
    ) -> TrafficProfile {
        let safePacketLossPercent = min(max(packetLossPercent, 0), 100)
        return TrafficProfile(
            id: manualID,
            name: "Advanced (manual)",
            description: "Define exact latency, loss, bandwidth and response delay values.",
            systemImageName: "slider.horizontal.3",
            latencyMs: max(latencyMs, 0),
            jitterMs: max(jitterMs, 0),
            downstreamKbps: max(downstreamKbps, 0),
            upstreamKbps: max(upstreamKbps, 0),
            packetLoss: safePacketLossPercent / 100,
            responseDelayMs: max(responseDelayMs, 0)
        )
    }

    static func profiles(manualProfile: TrafficProfile = defaultManual) -> [TrafficProfile] {
        builtInPresets + [manualProfile]
    }

    static func profile(with id: String?, manualProfile: TrafficProfile = defaultManual) -> TrafficProfile {
        guard let id else {
            return disabled
        }
        if id == manualID {
            return manualProfile
        }
        if let profile = builtInPresets.first(where: { $0.id == id }) {
            return profile
        }
        return disabled
    }
}
