import Darwin
import Foundation

final class LocalMCPServer: @unchecked Sendable {
    typealias Handler = @Sendable (Data) async -> Data?

    let socketURL: URL
    private let maximumRequestBytes: Int
    private let maximumClients: Int
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.frtmproxy.mcp-listener", qos: .utility)
    private let stateLock = NSLock()
    private var listener: DispatchSourceRead?
    private var listenerDescriptor: Int32 = -1
    private var clientCount = 0

    init(
        socketURL: URL,
        maximumRequestBytes: Int = AutomationLimits.defaults.maximumRequestBytes,
        maximumClients: Int = 4,
        handler: @escaping Handler
    ) {
        self.socketURL = socketURL
        self.maximumRequestBytes = maximumRequestBytes
        self.maximumClients = maximumClients
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard listenerDescriptor < 0 else { return }

        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try removeSocketIfStale()

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw LocalMCPServerError.socketCreation(errno) }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        var ownsSocketPath = false

        do {
            try bind(descriptor: descriptor)
            ownsSocketPath = true
            guard Darwin.listen(descriptor, 8) == 0 else {
                throw LocalMCPServerError.listen(errno)
            }
            chmod(socketURL.path, S_IRUSR | S_IWUSR)
        } catch {
            close(descriptor)
            if ownsSocketPath { unlink(socketURL.path) }
            throw error
        }

        listenerDescriptor = descriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        source.setCancelHandler { close(descriptor) }
        listener = source
        source.resume()
    }

    func stop() {
        stateLock.lock()
        guard listenerDescriptor >= 0 else {
            stateLock.unlock()
            return
        }
        let source = listener
        listener = nil
        listenerDescriptor = -1
        stateLock.unlock()
        source?.cancel()
        unlink(socketURL.path)
    }

    private func removeSocketIfStale() throws {
        guard FileManager.default.fileExists(atPath: socketURL.path) else { return }

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw LocalMCPServerError.socketCreation(errno) }
        defer { close(descriptor) }

        let bytes = Array(socketURL.path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw LocalMCPServerError.pathTooLong
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
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
        if result == 0 {
            throw LocalMCPServerError.bind(EADDRINUSE)
        }

        let connectionError = errno
        guard connectionError == ECONNREFUSED || connectionError == ENOENT else {
            throw LocalMCPServerError.bind(connectionError)
        }
        guard unlink(socketURL.path) == 0 || errno == ENOENT else {
            throw LocalMCPServerError.bind(errno)
        }
    }

    private func bind(descriptor: Int32) throws {
        let bytes = Array(socketURL.path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw LocalMCPServerError.pathTooLong
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + bytes.count)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, length)
            }
        }
        guard result == 0 else { throw LocalMCPServerError.bind(errno) }
    }

    private func acceptClients() {
        while true {
            let client = accept(listenerDescriptor, nil, nil)
            if client < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return
            }
            guard configureAcceptedClient(client), beginClient() else {
                close(client)
                continue
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.serve(client)
            }
        }
    }

    private func configureAcceptedClient(_ descriptor: Int32) -> Bool {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0 else { return false }
        return fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) == 0
    }

    private func serve(_ descriptor: Int32) {
        defer {
            close(descriptor)
            endClient()
        }
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)

        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count > 0 else { return }
            pending.append(contentsOf: buffer.prefix(count))
            guard pending.count <= maximumRequestBytes else { return }

            while let newline = pending.firstIndex(of: 0x0a) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                guard !line.isEmpty else { continue }

                let semaphore = DispatchSemaphore(value: 0)
                var response: Data?
                Task {
                    response = await handler(line)
                    semaphore.signal()
                }
                semaphore.wait()
                if var response {
                    response.append(0x0a)
                    response.withUnsafeBytes { rawBuffer in
                        guard let base = rawBuffer.baseAddress else { return }
                        _ = Darwin.send(descriptor, base, rawBuffer.count, MSG_NOSIGNAL)
                    }
                }
            }
        }
    }

    private func beginClient() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard clientCount < maximumClients else { return false }
        clientCount += 1
        return true
    }

    private func endClient() {
        stateLock.lock()
        clientCount = max(0, clientCount - 1)
        stateLock.unlock()
    }
}
