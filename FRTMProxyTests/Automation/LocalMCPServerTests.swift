import Darwin
import Foundation
import Testing
@testable import FRTMProxy

@Suite("Local MCP server")
struct LocalMCPServerTests {
    @Test("Accepts repeated sequential requests")
    func repeatedSequentialRequests() async throws {
        let socketURL = URL(filePath: "/tmp/frtmproxy-mcp-\(UUID().uuidString).sock")
        let server = LocalMCPServer(socketURL: socketURL) { request in request }
        try server.start()
        defer { server.stop() }

        for index in 0..<20 {
            let request = Data("request-\(index)".utf8)
            let response = try await exchange(request, at: socketURL)
            #expect(response == request)
        }
    }

    @Test("Keeps persistent clients connected between requests")
    func persistentClient() async throws {
        let socketURL = URL(filePath: "/tmp/frtmproxy-mcp-\(UUID().uuidString).sock")
        let server = LocalMCPServer(socketURL: socketURL) { request in request }
        try server.start()
        defer { server.stop() }

        let requests = [Data("initialize".utf8), Data("tools/list".utf8)]
        let responses = try await exchange(requests, at: socketURL, delay: .milliseconds(100))

        #expect(responses == requests)
    }

    @Test("Processes pipelined requests in order")
    func orderedPipelinedRequests() async throws {
        let socketURL = URL(filePath: "/tmp/frtmproxy-mcp-\(UUID().uuidString).sock")
        let server = LocalMCPServer(socketURL: socketURL) { request in
            if request == Data("first".utf8) {
                try? await Task.sleep(for: .milliseconds(75))
            }
            return request
        }
        try server.start()
        defer { server.stop() }

        let requests = ["first", "second", "third"].map { Data($0.utf8) }
        let responses = try await exchangePipelined(requests, at: socketURL)

        #expect(responses == requests)
    }

    @Test("Writes a response larger than the socket buffer completely")
    func largeResponse() async throws {
        let socketURL = URL(filePath: "/tmp/frtmproxy-mcp-\(UUID().uuidString).sock")
        let expected = Data(repeating: 0x61, count: 2_000_000)
        let server = LocalMCPServer(socketURL: socketURL) { _ in expected }
        try server.start()
        defer { server.stop() }

        #expect(try await exchange(Data("large".utf8), at: socketURL) == expected)
    }

    @Test("Stop disconnects active clients and server can restart")
    func stopAndRestart() async throws {
        let socketURL = URL(filePath: "/tmp/frtmproxy-mcp-\(UUID().uuidString).sock")
        let server = LocalMCPServer(socketURL: socketURL) { request in
            if request == Data("connected".utf8) {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return nil
                }
            }
            return request
        }
        try server.start()

        let descriptor = try connect(to: socketURL)
        try sendLine(Data("connected".utf8), descriptor: descriptor)
        try await Task.sleep(for: .milliseconds(50))
        server.stop()

        var byte: UInt8 = 0
        let readCount = Darwin.read(descriptor, &byte, 1)
        close(descriptor)
        #expect(readCount == 0 || (readCount < 0 && errno != EAGAIN && errno != EWOULDBLOCK))

        try server.start()
        defer { server.stop() }
        #expect(try await exchange(Data("after-restart".utf8), at: socketURL) == Data("after-restart".utf8))
    }

    @Test("A second server cannot steal a live socket path")
    func liveSocketOwnership() async throws {
        let socketURL = URL(filePath: "/tmp/frtmproxy-mcp-\(UUID().uuidString).sock")
        let firstServer = LocalMCPServer(socketURL: socketURL) { request in request }
        let secondServer = LocalMCPServer(socketURL: socketURL) { request in request }
        try firstServer.start()
        defer { firstServer.stop() }

        #expect(throws: LocalMCPServerError.self) {
            try secondServer.start()
        }
        secondServer.stop()

        let request = Data("still-alive".utf8)
        #expect(try await exchange(request, at: socketURL) == request)
    }

    private func exchange(_ request: Data, at socketURL: URL) async throws -> Data {
        try await exchange([request], at: socketURL).first ?? Data()
    }

    private func exchange(
        _ requests: [Data],
        at socketURL: URL,
        delay: Duration? = nil
    ) async throws -> [Data] {
        try await Task.detached {
            let descriptor = try connect(to: socketURL)
            defer { close(descriptor) }

            var responses: [Data] = []
            for (index, request) in requests.enumerated() {
                if index > 0, let delay {
                    try await Task.sleep(for: delay)
                }
                try sendLine(request, descriptor: descriptor)
                responses.append(try readLine(descriptor: descriptor))
            }
            return responses
        }.value
    }

    private func exchangePipelined(_ requests: [Data], at socketURL: URL) async throws -> [Data] {
        try await Task.detached {
            let descriptor = try connect(to: socketURL)
            defer { close(descriptor) }

            for request in requests {
                try sendLine(request, descriptor: descriptor)
            }
            return try readLines(count: requests.count, descriptor: descriptor)
        }.value
    }

    private func connect(to socketURL: URL) throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw LocalMCPServerError.socketCreation(errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketURL.path.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + bytes.count)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, length)
            }
        }
        guard result == 0 else {
            let connectionError = errno
            close(descriptor)
            throw CocoaError(
                .fileReadUnknown,
                userInfo: [NSUnderlyingErrorKey: POSIXError(.init(rawValue: connectionError) ?? .ECONNREFUSED)]
            )
        }

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            close(descriptor)
            throw CocoaError(.fileReadUnknown)
        }
        return descriptor
    }

    private func sendLine(_ data: Data, descriptor: Int32) throws {
        var payload = data
        payload.append(0x0a)
        try payload.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let sent = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset,
                    MSG_NOSIGNAL
                )
                if sent > 0 {
                    offset += sent
                } else if sent < 0, errno == EINTR {
                    continue
                } else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
        }
    }

    private func readLine(descriptor: Int32) throws -> Data {
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                if let newline = buffer.prefix(count).firstIndex(of: 0x0a) {
                    response.append(contentsOf: buffer[..<newline])
                    return response
                }
                response.append(contentsOf: buffer.prefix(count))
                continue
            }
            if count < 0, errno == EINTR { continue }
            throw CocoaError(
                .fileReadUnknown,
                userInfo: [NSUnderlyingErrorKey: POSIXError(.init(rawValue: errno) ?? .ETIMEDOUT)]
            )
        }
    }

    private func readLines(count expectedCount: Int, descriptor: Int32) throws -> [Data] {
        var responses: [Data] = []
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while responses.count < expectedCount {
            while let newline = pending.firstIndex(of: 0x0a), responses.count < expectedCount {
                responses.append(Data(pending[..<newline]))
                pending.removeSubrange(...newline)
            }
            if responses.count == expectedCount { break }

            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                pending.append(contentsOf: buffer.prefix(count))
                continue
            }
            if count < 0, errno == EINTR { continue }
            throw CocoaError(
                .fileReadUnknown,
                userInfo: [NSUnderlyingErrorKey: POSIXError(.init(rawValue: errno) ?? .ETIMEDOUT)]
            )
        }
        return responses
    }
}
