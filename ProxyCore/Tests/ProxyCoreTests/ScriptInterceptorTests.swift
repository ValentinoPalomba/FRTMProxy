import Foundation
import XCTest
import NIO
import NIOHTTP1
@testable import ProxyCore

final class ScriptInterceptorTests: XCTestCase {
    func testScriptOnRequestMutatesHeadersAndPersistsSession() async throws {
        let base = try makeTempBaseDir()

        let scriptPath = "/scripts/test.js"
        let script = """
        async function onRequest(context, request) {
          context.session.count = (context.session.count || 0) + 1;
          request.headers["X-Count"] = "" + context.session.count;
          request.headers["X-Test"] = "1";
          return request;
        }

        async function onResponse(context, request, response) {
          return response;
        }
        """

        try writeScriptConfig(baseDirectory: base, match: "example.com/*", scriptPath: scriptPath, script: script)

        let store = ScriptStore(baseDirectory: base)
        try await store.loadIfPresent()

        let interceptor = ScriptInterceptor(store: store, baseDirectory: base)

        let req1 = ProxyRequest(id: UUID().uuidString, httpVersion: .http1_1, method: "GET", url: "http://example.com/one", headers: [:])
        let out1 = await interceptor.onRequest(req1)
        XCTAssertEqual(out1?.headers["X-Test"], "1")
        XCTAssertEqual(out1?.headers["X-Count"], "1")

        let req2 = ProxyRequest(id: UUID().uuidString, httpVersion: .http1_1, method: "GET", url: "http://example.com/two", headers: [:])
        let out2 = await interceptor.onRequest(req2)
        XCTAssertEqual(out2?.headers["X-Count"], "2")
    }

    func testScriptOnRequestCanFetchAndRewriteBody() async throws {
        let upstreamGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try upstreamGroup.syncShutdownGracefully()) }

        let upstreamBody = Data("from-fetch".utf8)
        let upstreamServer = try await startHTTPServer(group: upstreamGroup, handler: FixedResponseHTTPHandler(body: upstreamBody))
        defer { try? upstreamServer.close().wait() }
        let upstreamPort = upstreamServer.localAddress!.port!

        let base = try makeTempBaseDir()

        let scriptPath = "/scripts/fetch.js"
        let script = """
        async function onRequest(context, request) {
          request.method = "POST";
          request.headers["Content-Type"] = "text/plain; charset=utf-8";
          request.body = await fetch("http://127.0.0.1:\(upstreamPort)/").then(r => r.text());
          return request;
        }

        async function onResponse(context, request, response) {
          return response;
        }
        """

        try writeScriptConfig(baseDirectory: base, match: "example.com/*", scriptPath: scriptPath, script: script)

        let store = ScriptStore(baseDirectory: base)
        try await store.loadIfPresent()

        let interceptor = ScriptInterceptor(store: store, baseDirectory: base)

        let req = ProxyRequest(id: UUID().uuidString, httpVersion: .http1_1, method: "GET", url: "http://example.com/fetch", headers: [:])
        let out = await interceptor.onRequest(req)

        XCTAssertEqual(out?.method, "POST")
        XCTAssertEqual(out?.headers["Content-Type"], "text/plain; charset=utf-8")
        XCTAssertEqual(out?.bodyPreview, upstreamBody)
    }
}

// MARK: - Helpers

private func makeTempBaseDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ProxyCoreScriptTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func writeScriptConfig(baseDirectory: URL, match: String, scriptPath: String, script: String) throws {
    let scriptsDir = baseDirectory.appending(path: "scripts", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)

    let fileURL = resolveRelativeURL(scriptPath, under: baseDirectory)
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try script.write(to: fileURL, atomically: true, encoding: .utf8)

    let cfg: [String: Any] = [
        "enabled": true,
        "list": [
            [
                "enabled": true,
                "name": "test",
                "url": match,
                "scriptPath": scriptPath,
            ]
        ]
    ]
    let data = try JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: baseDirectory.appending(path: "script.json", directoryHint: .notDirectory), options: [.atomic])
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

