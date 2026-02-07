import Foundation
import XCTest
import NIO
import NIOHTTP1
@testable import ProxyCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class HTTPProxyRewriteIntegrationTests: XCTestCase {
    func testOnResponseInterceptorRewritesBodyOnWire() async throws {
        let upstreamGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try upstreamGroup.syncShutdownGracefully()) }

        let upstreamBody = Data("upstream".utf8)
        let upstreamServer = try await startHTTPServer(group: upstreamGroup, handler: FixedResponseHTTPHandler(body: upstreamBody))
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

        let rewritten = Data("rewritten".utf8)
        let engine = try ProxyEngine(configuration: config, interceptors: [
            ReplaceResponseBodyInterceptor(body: rewritten)
        ])
        try await engine.start()
        defer { Task { await engine.stop() } }

        let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try clientGroup.syncShutdownGracefully()) }

        let responseBody = try await fetchViaHTTPProxy(
            group: clientGroup,
            proxyPort: proxyPort,
            absoluteURL: "http://127.0.0.1:\(upstreamPort)/"
        )

        XCTAssertEqual(responseBody, rewritten)
    }

    func testOnRequestInterceptorRewritesBodyOnWire() async throws {
        let upstreamGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try upstreamGroup.syncShutdownGracefully()) }

        let upstreamServer = try await startHTTPServer(group: upstreamGroup, handler: EchoRequestBodyHTTPHandler())
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

        let modified = Data("modified".utf8)
        let engine = try ProxyEngine(configuration: config, interceptors: [
            ReplaceRequestBodyInterceptor(body: modified)
        ])
        try await engine.start()
        defer { Task { await engine.stop() } }

        let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try clientGroup.syncShutdownGracefully()) }

        let responseBody = try await fetchViaHTTPProxy(
            group: clientGroup,
            proxyPort: proxyPort,
            absoluteURL: "http://127.0.0.1:\(upstreamPort)/echo",
            method: .POST,
            body: Data("original".utf8)
        )

        XCTAssertEqual(responseBody, modified)
    }
}

private struct ReplaceResponseBodyInterceptor: ProxyInterceptor {
    let body: Data

    func onResponse(request: ProxyRequest, response: ProxyResponse) async -> ProxyResponse? {
        var updated = response
        updated.bodyPreview = body
        updated.bodyIsTruncated = false
        updated.rawBodySize = body.count
        return updated
    }
}

private struct ReplaceRequestBodyInterceptor: ProxyInterceptor {
    let body: Data

    func onRequest(_ request: ProxyRequest) async -> ProxyRequest? {
        var updated = request
        updated.bodyPreview = body
        updated.bodyIsTruncated = false
        updated.rawBodySize = body.count
        return updated
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

private final class EchoRequestBodyHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var body = Data()

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
            var head = HTTPResponseHead(version: .http1_1, status: .ok)
            head.headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
            head.headers.add(name: "Content-Length", value: "\(body.count)")
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            var out = context.channel.allocator.buffer(capacity: body.count)
            out.writeBytes(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(out))), promise: nil)
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

private func fetchViaHTTPProxy(
    group: EventLoopGroup,
    proxyPort: Int,
    absoluteURL: String,
    method: HTTPMethod = .GET,
    body: Data? = nil
) async throws -> Data {
    let promise = group.next().makePromise(of: Data.self)

    let bootstrap = ClientBootstrap(group: group)
        .channelInitializer { channel in
            channel.pipeline.addHTTPClientHandlers().flatMap {
                channel.pipeline.addHandler(HTTPProxyFetchClientHandler(
                    method: method,
                    absoluteURL: absoluteURL,
                    body: body,
                    completion: promise
                ))
            }
        }

    let channel = try await bootstrap.connect(host: "127.0.0.1", port: proxyPort).get()
    defer { try? channel.close().wait() }

    return try await promise.futureResult.get()
}

private final class HTTPProxyFetchClientHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let method: HTTPMethod
    private let absoluteURL: String
    private let body: Data?
    private let completion: EventLoopPromise<Data>

    private var responseBody = Data()

    init(method: HTTPMethod, absoluteURL: String, body: Data?, completion: EventLoopPromise<Data>) {
        self.method = method
        self.absoluteURL = absoluteURL
        self.body = body
        self.completion = completion
    }

    func channelActive(context: ChannelHandlerContext) {
        var head = HTTPRequestHead(version: .http1_1, method: method, uri: absoluteURL)
        if let url = URL(string: absoluteURL), let host = url.host {
            if let port = url.port {
                head.headers.add(name: "Host", value: "\(host):\(port)")
            } else {
                head.headers.add(name: "Host", value: host)
            }
        }

        if let body, !body.isEmpty {
            head.headers.add(name: "Content-Length", value: "\(body.count)")
        }

        context.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
        if let body, !body.isEmpty {
            var buf = context.channel.allocator.buffer(capacity: body.count)
            buf.writeBytes(body)
            context.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buf))), promise: nil)
        }
        context.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head:
            responseBody.removeAll(keepingCapacity: true)
        case .body(var buf):
            if let bytes = buf.readBytes(length: buf.readableBytes) {
                responseBody.append(contentsOf: bytes)
            }
        case .end:
            completion.succeed(responseBody)
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        completion.fail(error)
        context.close(promise: nil)
    }
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

