import Foundation
import XCTest
import NIO
import NIOHTTP1
@testable import ProxyCore

final class ReplayHTTPIntegrationTests: XCTestCase {
    func testReplayHTTPCanInjectPacketLossViaTrafficProfile() async throws {
        let upstreamGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try upstreamGroup.syncShutdownGracefully()) }

        let upstreamBody = Data("upstream".utf8)
        let upstreamServer = try await startHTTPServer(group: upstreamGroup, handler: FixedResponseHTTPHandler(body: upstreamBody))
        defer { try? upstreamServer.close().wait() }

        let upstreamPort = upstreamServer.localAddress!.port!

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("ProxyCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let config = ProxyConfiguration(
            listenHost: "127.0.0.1",
            listenPort: 0,
            enableMITM: false,
            enableHTTP2: false,
            paths: ProxyConfiguration.Paths(baseDirectory: tmpDir)
        )

        let engine = try ProxyEngine(configuration: config)
        try await engine.start()
        defer { Task { await engine.stop() } }

        // Deterministic: packetLoss=1.0 always injects.
        await engine.setTrafficProfile(TrafficProfile(
            id: "traffic.packet_loss_test",
            latencyMs: 0,
            jitterMs: 0,
            downstreamKbps: 0,
            upstreamKbps: 0,
            packetLoss: 1.0
        ))

        let requestID = "test-replay-\(UUID().uuidString)"

        _ = try await engine.replayHTTP(
            requestID: requestID,
            method: "GET",
            url: "http://127.0.0.1:\(upstreamPort)/",
            headers: [:],
            body: nil
        )

        let captured = try await awaitResponse(engine: engine, requestID: requestID, timeoutSeconds: 5)

        XCTAssertEqual(captured.statusCode, 598)
        XCTAssertEqual(String(data: captured.bodyPreview ?? Data(), encoding: .utf8), "Simulated packet loss (traffic profile)")
    }
}

private enum AwaitResponseError: Error {
    case timeout
    case streamEnded
}

private func awaitResponse(engine: ProxyEngine, requestID: String, timeoutSeconds: Int) async throws -> ProxyResponse {
    try await withThrowingTaskGroup(of: ProxyResponse.self) { group in
        group.addTask {
            for await event in engine.events {
                if case .response(let response) = event, response.requestID == requestID {
                    return response
                }
            }
            throw AwaitResponseError.streamEnded
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
            throw AwaitResponseError.timeout
        }

        let response = try await group.next()!
        group.cancelAll()
        return response
    }
}

private final class FixedResponseHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let body: Data

    init(body: Data) {
        self.body = body
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head:
            break
        case .body:
            break
        case .end:
            var head = HTTPResponseHead(version: .http1_1, status: .ok)
            head.headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
            head.headers.add(name: "Content-Length", value: "\(body.count)")
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            var buf = context.channel.allocator.buffer(capacity: body.count)
            buf.writeBytes(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

private func startHTTPServer(group: EventLoopGroup, handler: ChannelHandler) async throws -> Channel {
    let bootstrap = ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .childChannelInitializer { channel in
            channel.pipeline.configureHTTPServerPipeline().flatMap {
                channel.pipeline.addHandler(handler)
            }
        }
        .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)

    return try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
}
