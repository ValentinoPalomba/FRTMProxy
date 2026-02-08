import Foundation
import NIO
import NIOConcurrencyHelpers

/// Runtime traffic shaping settings (latency / bandwidth / packet loss).
///
/// This is intentionally small and "engine-native" so the app UI can map its own `TrafficProfile`
/// model to this struct without coupling.
public struct TrafficProfile: Sendable, Equatable, Codable {
    public var id: String
    public var latencyMs: Int
    public var jitterMs: Int
    public var downstreamKbps: Int
    public var upstreamKbps: Int
    public var packetLoss: Double

    public init(
        id: String,
        latencyMs: Int,
        jitterMs: Int,
        downstreamKbps: Int,
        upstreamKbps: Int,
        packetLoss: Double
    ) {
        self.id = id
        self.latencyMs = max(latencyMs, 0)
        self.jitterMs = max(jitterMs, 0)
        self.downstreamKbps = max(downstreamKbps, 0)
        self.upstreamKbps = max(upstreamKbps, 0)
        self.packetLoss = min(max(packetLoss, 0), 1)
    }

    public static let disabled = TrafficProfile(
        id: "traffic.off",
        latencyMs: 0,
        jitterMs: 0,
        downstreamKbps: 0,
        upstreamKbps: 0,
        packetLoss: 0
    )

    public var isEnabled: Bool {
        id != Self.disabled.id
            && (latencyMs > 0 || jitterMs > 0 || downstreamKbps > 0 || upstreamKbps > 0 || packetLoss > 0)
    }
}

public enum TrafficDirection: Sendable {
    case uplink
    case downlink
}

/// Thread-safe storage + helpers to turn a profile into event-loop friendly delays.
public final class TrafficProfileController: @unchecked Sendable {
    private let lock = NIOLock()
    private var profile: TrafficProfile

    public init(initial: TrafficProfile = .disabled) {
        self.profile = initial
    }

    public func update(_ profile: TrafficProfile) {
        lock.withLock {
            self.profile = profile
        }
    }

    public func snapshot() -> TrafficProfile {
        lock.withLock { profile }
    }

    public func profileHeaderValue() -> String? {
        let p = snapshot()
        return p.isEnabled ? p.id : nil
    }

    public func shouldInjectPacketLoss() -> Bool {
        let p = snapshot()
        guard p.isEnabled, p.packetLoss > 0 else { return false }
        return Double.random(in: 0..<1) < p.packetLoss
    }

    /// Returns a future that completes after the simulated delay for the given direction.
    public func delayFuture(direction: TrafficDirection, byteCount: Int, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        let p = snapshot()
        guard p.isEnabled else {
            return eventLoop.makeSucceededFuture(())
        }

        let baseLatency = max(p.latencyMs, 0)
        let jitter = max(p.jitterMs, 0)
        let jitterDelta: Int
        if jitter > 0 {
            jitterDelta = Int.random(in: -jitter...jitter)
        } else {
            jitterDelta = 0
        }
        let latencyMs = max(0, baseLatency + jitterDelta)

        let kbpsLimit: Int
        switch direction {
        case .uplink:
            kbpsLimit = p.upstreamKbps
        case .downlink:
            kbpsLimit = p.downstreamKbps
        }

        var totalNs: Int64 = 0
        totalNs += Int64(latencyMs) * 1_000_000

        if kbpsLimit > 0, byteCount > 0 {
            // 1 kbps == 1000 bits/s -> 125 bytes/s
            let bytesPerSecond = Double(kbpsLimit) * 125.0
            let seconds = Double(byteCount) / max(bytesPerSecond, 1)
            totalNs += Int64(seconds * 1_000_000_000)
        }

        guard totalNs > 0 else {
            return eventLoop.makeSucceededFuture(())
        }

        return eventLoop.scheduleTask(in: .nanoseconds(totalNs)) {}.futureResult
    }
}

