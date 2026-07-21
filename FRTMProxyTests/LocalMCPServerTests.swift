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
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                throw LocalMCPServerError.socketCreation(errno)
            }
            defer { close(descriptor) }

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
                throw CocoaError(.fileReadUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(.init(rawValue: errno) ?? .ECONNREFUSED)])
            }

            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            guard setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &timeout,
                socklen_t(MemoryLayout<timeval>.size)
            ) == 0 else {
                throw CocoaError(.fileReadUnknown)
            }

            var responses: [Data] = []
            for (index, request) in requests.enumerated() {
                if index > 0, let delay {
                    try await Task.sleep(for: delay)
                }

                var payload = request
                payload.append(0x0a)
                try payload.withUnsafeBytes { buffer in
                    guard let baseAddress = buffer.baseAddress,
                          Darwin.send(descriptor, baseAddress, buffer.count, MSG_NOSIGNAL) == buffer.count else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }

                var response = Data()
                var byte: UInt8 = 0
                var count = Darwin.read(descriptor, &byte, 1)
                while count == 1, byte != 0x0a {
                    response.append(byte)
                    count = Darwin.read(descriptor, &byte, 1)
                }
                if count < 0 {
                    throw CocoaError(.fileReadUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(.init(rawValue: errno) ?? .ETIMEDOUT)])
                }
                responses.append(response)
            }
            return responses
        }.value
    }
}
