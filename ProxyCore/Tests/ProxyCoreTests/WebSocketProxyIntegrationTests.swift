import Foundation
import XCTest
import NIO
import NIOHTTP1
import NIOWebSocket
@testable import ProxyCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class WebSocketProxyIntegrationTests: XCTestCase {
    func testWebSocketUpgradeAndRelayThroughProxy() async throws {
        let upstreamGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try upstreamGroup.syncShutdownGracefully()) }

        let upstreamServer = try await startWebSocketEchoServer(group: upstreamGroup)
        defer { try? upstreamServer.close().wait() }

        let upstreamPort = upstreamServer.localAddress!.port!

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("ProxyCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let proxyPort = try pickUnusedLocalPort()
        let config = ProxyConfiguration(
            listenHost: "127.0.0.1",
            listenPort: proxyPort,
            enableMITM: false,
            enableHTTP2: false,
            paths: ProxyConfiguration.Paths(baseDirectory: tmpDir)
        )

        let engine = try ProxyEngine(configuration: config)
        try await engine.start()
        defer { Task { await engine.stop() } }

        let wsCaptured = XCTestExpectation(description: "Proxy captures WebSocket message")
        let eventCollector = Task {
            for await ev in engine.events {
                if case .webSocketMessage(let msg) = ev {
                    if String(data: msg.data, encoding: .utf8) == "hello" {
                        wsCaptured.fulfill()
                        break
                    }
                }
            }
        }
        defer { eventCollector.cancel() }

        let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try clientGroup.syncShutdownGracefully()) }

        let done = clientGroup.next().makePromise(of: Void.self)

        let bootstrap = ClientBootstrap(group: clientGroup).channelInitializer { channel in
            channel.pipeline.addHTTPClientHandlers().flatMap {
                channel.pipeline.addHandler(WebSocketThroughProxyClientHandler(
                    upstreamHost: "127.0.0.1",
                    upstreamPort: upstreamPort,
                    completion: done
                ))
            }
        }

        let clientChannel = try await bootstrap.connect(host: "127.0.0.1", port: proxyPort).get()
        defer { try? clientChannel.close().wait() }

        try await done.futureResult.get()
        await fulfillment(of: [wsCaptured], timeout: 5.0)
    }
}

private final class WebSocketThroughProxyClientHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let upstreamHost: String
    private let upstreamPort: Int
    private let completion: EventLoopPromise<Void>

    private var saw101 = false

    init(upstreamHost: String, upstreamPort: Int, completion: EventLoopPromise<Void>) {
        self.upstreamHost = upstreamHost
        self.upstreamPort = upstreamPort
        self.completion = completion
    }

    func channelActive(context: ChannelHandlerContext) {
        // Absolute-form request to an HTTP proxy.
        let uri = "http://\(upstreamHost):\(upstreamPort)/"

        var head = HTTPRequestHead(version: .http1_1, method: .GET, uri: uri)
        head.headers.add(name: "Host", value: "\(upstreamHost):\(upstreamPort)")
        head.headers.add(name: "Connection", value: "Upgrade")
        head.headers.add(name: "Upgrade", value: "websocket")
        head.headers.add(name: "Sec-WebSocket-Version", value: "13")
        head.headers.add(name: "Sec-WebSocket-Key", value: "dGhlIHNhbXBsZSBub25jZQ==")

        context.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
        context.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            saw101 = head.status.code == 101
            if !saw101 {
                completion.fail(ChannelError.ioOnClosedChannel)
                context.close(promise: nil)
            }
        case .body:
            break
        case .end:
            if saw101 {
                upgradeToWebSocket(context: context)
            }
        }
    }

    private func upgradeToWebSocket(context: ChannelHandlerContext) {
        let channel = context.channel
        let pipeline = channel.pipeline

        // Remove HTTP client handlers and install websocket codecs.
        let fut = pipeline.removeHTTP1ClientPipelineHandlersIfPresent().flatMap {
            pipeline.removeHandler(self)
        }.flatMap {
            pipeline.eventLoop.makeCompletedFuture {
                try pipeline.syncOperations.addHandler(ByteToMessageHandler(WebSocketFrameDecoder(maxFrameSize: 1 << 20)))
                try pipeline.syncOperations.addHandler(WebSocketFrameEncoder())
                try pipeline.syncOperations.addHandler(NIOWebSocketFrameAggregator(
                    minNonFinalFragmentSize: 1,
                    maxAccumulatedFrameCount: 128,
                    maxAccumulatedFrameSize: 1 << 20
                ))
                try pipeline.syncOperations.addHandler(WebSocketTestClientFrameHandler(completion: self.completion))
            }
        }

        fut.whenSuccess {
            // Send a single text frame (masked, because we're the websocket client).
            var buf = channel.allocator.buffer(capacity: 5)
            buf.writeString("hello")
            let frame = WebSocketFrame(fin: true, opcode: .text, maskKey: [1, 2, 3, 4], data: buf)
            channel.writeAndFlush(NIOAny(frame), promise: nil)
        }

        fut.whenFailure { error in
            self.completion.fail(error)
            context.close(promise: nil)
        }
    }
}

private final class WebSocketTestClientFrameHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame

    private let completion: EventLoopPromise<Void>

    init(completion: EventLoopPromise<Void>) {
        self.completion = completion
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        guard frame.opcode == .text else { return }

        var payload = frame.unmaskedData
        let s = payload.readString(length: payload.readableBytes) ?? ""
        if s == "hello" {
            completion.succeed(())
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        completion.fail(error)
        context.close(promise: nil)
    }
}

private final class WebSocketEchoHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .text, .binary:
            let unmasked = frame.unmaskedData
            let out = WebSocketFrame(fin: true, opcode: frame.opcode, data: unmasked)
            context.writeAndFlush(NIOAny(out), promise: nil)
        case .connectionClose:
            context.close(promise: nil)
        default:
            break
        }
    }
}

private func startWebSocketEchoServer(group: EventLoopGroup) async throws -> Channel {
    let upgrader = NIOWebSocketServerUpgrader(
        shouldUpgrade: { channel, head in
            channel.eventLoop.makeSucceededFuture([:])
        },
        upgradePipelineHandler: { channel, _ in
            // NIOWebSocketServerUpgrader already adds WebSocketFrameEncoder + WebSocketFrameDecoder.
            channel.pipeline.addHandler(NIOWebSocketFrameAggregator(
                minNonFinalFragmentSize: 1,
                maxAccumulatedFrameCount: 128,
                maxAccumulatedFrameSize: 1 << 20
            )).flatMap {
                channel.pipeline.addHandler(WebSocketEchoHandler())
            }
        }
    )

    let upgradeConfig: NIOHTTPServerUpgradeSendableConfiguration = (
        upgraders: [upgrader],
        completionHandler: { _ in }
    )

    let bootstrap = ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .childChannelInitializer { channel in
            channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: upgradeConfig)
        }
        .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)

    return try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
}

private func pickUnusedLocalPort() throws -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw NSError(domain: "ProxyCoreTests", code: 1) }
    defer { _ = close(fd) }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(0).bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    var a = addr
    let bindResult = withUnsafePointer(to: &a) { ptr -> Int32 in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else { throw NSError(domain: "ProxyCoreTests", code: 2) }

    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    var out = sockaddr_in()
    let nameResult = withUnsafeMutablePointer(to: &out) { ptr -> Int32 in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            getsockname(fd, sa, &len)
        }
    }
    guard nameResult == 0 else { throw NSError(domain: "ProxyCoreTests", code: 3) }

    return Int(UInt16(bigEndian: out.sin_port))
}
