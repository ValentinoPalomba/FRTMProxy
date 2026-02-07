import Foundation
import XCTest
import NIO
import NIOHTTP1
@testable import ProxyCore

final class ReportServerInterceptorTests: XCTestCase {
    func testReportServerInterceptorPostsEntryJSON() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }

        let received = group.next().makePromise(of: Data.self)
        let server = try await startHTTPServer(group: group, handler: CaptureBodyHTTPHandler(completion: received))
        defer { try? server.close().wait() }

        let port = server.localAddress!.port!

        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ProxyCoreReportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let cfg: [[String: Any]] = [[
            "name": "test",
            "matchUrl": "example.com/*",
            "serverUrl": "http://127.0.0.1:\(port)/report",
            "enabled": true,
            "compression": "none",
        ]]
        let cfgData = try JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys])
        try cfgData.write(to: base.appending(path: "report_servers.json", directoryHint: .notDirectory), options: [.atomic])

        let store = ReportServerStore(baseDirectory: base)
        try await store.loadIfPresent()

        let interceptor = ReportServerInterceptor(store: store)

        let req = ProxyRequest(
            id: "req-1",
            timestamp: Date(timeIntervalSince1970: 1),
            httpVersion: .http1_1,
            method: "GET",
            url: "http://example.com/hello",
            headers: ["User-Agent": "ProxyCoreTests"],
            bodyPreview: nil,
            bodyIsTruncated: false,
            rawBodySize: 0,
            client: nil,
            serverIP: "127.0.0.1",
            processInfo: nil
        )

        let res = ProxyResponse(
            requestID: req.id,
            timestamp: Date(timeIntervalSince1970: 2),
            httpVersion: .http1_1,
            statusCode: 200,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            bodyPreview: Data("ok".utf8),
            bodyIsTruncated: false,
            rawBodySize: 2
        )

        _ = await interceptor.onResponse(request: req, response: res)

        let body = try await received.futureResult.get()
        let decoded = try JSONDecoder().decode(ReportHarEntry.self, from: body)

        XCTAssertEqual(decoded.id, req.id)
        XCTAssertEqual(decoded.request.url, req.url)
        XCTAssertEqual(decoded.response.status, 200)
    }
}

private final class CaptureBodyHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let completion: EventLoopPromise<Data>
    private var body = Data()

    init(completion: EventLoopPromise<Data>) {
        self.completion = completion
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head:
            body.removeAll(keepingCapacity: true)
        case .body(var buf):
            if let bytes = buf.readBytes(length: buf.readableBytes) {
                body.append(contentsOf: bytes)
            }
        case .end:
            completion.succeed(body)

            var head = HTTPResponseHead(version: .http1_1, status: .ok)
            head.headers.add(name: "Content-Length", value: "0")
            context.write(wrapOutboundOut(.head(head)), promise: nil)
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

