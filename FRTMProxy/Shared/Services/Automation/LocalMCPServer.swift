import Darwin
import Foundation

final class LocalMCPServer: @unchecked Sendable {
    typealias Handler = @Sendable (Data) async -> Data?

    private static let listenBacklog: Int32 = 8

    let socketURL: URL
    private let maximumRequestBytes: Int
    private let maximumClients: Int
    private let handler: Handler
    private let listenerQueue = DispatchQueue(label: "com.frtmproxy.mcp-listener", qos: .utility)
    private let lifecycleLock = NSLock()
    private let stateLock = NSLock()
    private var listener: DispatchSourceRead?
    private var listenerDescriptor: Int32 = -1
    private var listenerID: UUID?
    private var clients: [UUID: ClientConnection] = [:]

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
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
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
        guard configureNonBlocking(descriptor) else {
            let configurationError = errno
            close(descriptor)
            throw LocalMCPServerError.socketCreation(configurationError)
        }
        var ownsSocketPath = false

        do {
            try bind(descriptor: descriptor)
            ownsSocketPath = true
            guard Darwin.listen(descriptor, Self.listenBacklog) == 0 else {
                throw LocalMCPServerError.listen(errno)
            }
            chmod(socketURL.path, S_IRUSR | S_IWUSR)
        } catch {
            close(descriptor)
            if ownsSocketPath { unlink(socketURL.path) }
            throw error
        }

        let identifier = UUID()
        listenerDescriptor = descriptor
        listenerID = identifier
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: listenerQueue)
        source.setEventHandler { [weak self] in
            self?.acceptClients(listenerID: identifier, descriptor: descriptor)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        listener = source
        source.activate()
    }

    func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        stateLock.lock()
        let source = listener
        let activeClients = Array(clients.values)
        let wasRunning = listenerDescriptor >= 0
        listener = nil
        listenerDescriptor = -1
        listenerID = nil
        clients.removeAll()
        stateLock.unlock()

        source?.cancel()
        if source != nil {
            // Drain the listener queue before another start can reuse the old
            // descriptor number and be closed by the previous cancel handler.
            listenerQueue.sync {}
        }
        activeClients.forEach { $0.cancel() }
        if wasRunning {
            unlink(socketURL.path)
        }
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

    private func acceptClients(listenerID: UUID, descriptor: Int32) {
        while true {
            let clientDescriptor = accept(descriptor, nil, nil)
            if clientDescriptor < 0 {
                if errno == EINTR { continue }
                return
            }
            guard configureNonBlocking(clientDescriptor) else {
                close(clientDescriptor)
                continue
            }

            let clientID = UUID()
            let connection = ClientConnection(
                id: clientID,
                descriptor: clientDescriptor,
                maximumRequestBytes: maximumRequestBytes,
                handler: handler
            ) { [weak self] identifier in
                self?.clientDidClose(identifier)
            }

            stateLock.lock()
            let canAccept = self.listenerID == listenerID && clients.count < maximumClients
            if canAccept {
                clients[clientID] = connection
            }
            stateLock.unlock()

            if canAccept {
                connection.start()
            } else {
                connection.cancel()
            }
        }
    }

    private func clientDidClose(_ identifier: UUID) {
        stateLock.lock()
        clients.removeValue(forKey: identifier)
        stateLock.unlock()
    }

    private func configureNonBlocking(_ descriptor: Int32) -> Bool {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0 else { return false }
        return fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
    }
}

private final class ClientConnection: @unchecked Sendable {
    private static let readBufferSize = 8_192
    private static let maximumQueuedRequests = 64
    private static let writePollMilliseconds: Int32 = 100

    private let id: UUID
    private let descriptor: Int32
    private let maximumRequestBytes: Int
    private let handler: LocalMCPServer.Handler
    private let onClose: @Sendable (UUID) -> Void
    private let queue: DispatchQueue
    private let stateLock = NSLock()
    private var source: DispatchSourceRead?
    private var isCancelled = false
    private var pending = Data()
    private var requests: [Data] = []
    private var nextRequestIndex = 0
    private var queuedRequestBytes = 0
    private var isProcessing = false
    private var processingTask: Task<Void, Never>?

    init(
        id: UUID,
        descriptor: Int32,
        maximumRequestBytes: Int,
        handler: @escaping LocalMCPServer.Handler,
        onClose: @escaping @Sendable (UUID) -> Void
    ) {
        self.id = id
        self.descriptor = descriptor
        self.maximumRequestBytes = maximumRequestBytes
        self.handler = handler
        self.onClose = onClose
        self.queue = DispatchQueue(label: "com.frtmproxy.mcp-client-\(id.uuidString)", qos: .utility)
    }

    func start() {
        stateLock.lock()
        guard !isCancelled, source == nil else {
            stateLock.unlock()
            return
        }
        let readSource = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.readAvailableBytes()
        }
        readSource.setCancelHandler { [descriptor, id, onClose] in
            close(descriptor)
            onClose(id)
        }
        source = readSource
        readSource.activate()
        stateLock.unlock()
    }

    func cancel() {
        stateLock.lock()
        guard !isCancelled else {
            stateLock.unlock()
            return
        }
        isCancelled = true
        let readSource = source
        stateLock.unlock()

        _ = shutdown(descriptor, SHUT_RDWR)
        if let readSource {
            readSource.cancel()
        } else {
            close(descriptor)
            onClose(id)
        }
        queue.async { [weak self] in
            self?.processingTask?.cancel()
            self?.processingTask = nil
            self?.requests.removeAll()
            self?.nextRequestIndex = 0
            self?.queuedRequestBytes = 0
            self?.pending.removeAll()
        }
    }

    private func readAvailableBytes() {
        var buffer = [UInt8](repeating: 0, count: Self.readBufferSize)
        while !cancelled {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                pending.append(contentsOf: buffer.prefix(count))
                guard extractRequests() else {
                    cancel()
                    return
                }
                continue
            }
            if count == 0 {
                cancel()
                return
            }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            cancel()
            return
        }
    }

    private func extractRequests() -> Bool {
        while let newline = pending.firstIndex(of: 0x0a) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            guard line.count <= maximumRequestBytes else { return false }
            if !line.isEmpty {
                let pendingRequestCount = requests.count - nextRequestIndex
                let (nextByteCount, overflow) = queuedRequestBytes.addingReportingOverflow(line.count)
                let maximumQueuedBytes = maximumRequestBytes.multipliedReportingOverflow(by: 2)
                guard pendingRequestCount < Self.maximumQueuedRequests,
                      !overflow,
                      !maximumQueuedBytes.overflow,
                      nextByteCount <= maximumQueuedBytes.partialValue else {
                    return false
                }
                requests.append(line)
                queuedRequestBytes = nextByteCount
            }
        }
        guard pending.count <= maximumRequestBytes else { return false }
        processNextRequest()
        return true
    }

    private func processNextRequest() {
        guard !cancelled, !isProcessing, nextRequestIndex < requests.count else { return }
        isProcessing = true
        let request = requests[nextRequestIndex]
        nextRequestIndex += 1
        queuedRequestBytes -= request.count
        compactProcessedRequestsIfNeeded()
        let handler = handler
        processingTask = Task { [weak self] in
            let response = await handler(request)
            self?.queue.async { [weak self] in
                self?.finishRequest(response)
            }
        }
    }

    private func compactProcessedRequestsIfNeeded() {
        guard nextRequestIndex >= 32, nextRequestIndex * 2 >= requests.count else { return }
        requests.removeFirst(nextRequestIndex)
        nextRequestIndex = 0
    }

    private func finishRequest(_ response: Data?) {
        guard !cancelled else { return }
        processingTask = nil
        if var response {
            response.append(0x0a)
            guard sendAll(response) else {
                cancel()
                return
            }
        }
        isProcessing = false
        processNextRequest()
    }

    private func sendAll(_ data: Data) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return true }
            var bytesSent = 0
            while bytesSent < rawBuffer.count, !cancelled {
                let result = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: bytesSent),
                    rawBuffer.count - bytesSent,
                    MSG_NOSIGNAL
                )
                if result > 0 {
                    bytesSent += result
                    continue
                }
                if result < 0, errno == EINTR { continue }
                if result < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    guard waitUntilWritable() else { return false }
                    continue
                }
                return false
            }
            return bytesSent == rawBuffer.count
        }
    }

    private func waitUntilWritable() -> Bool {
        var descriptorState = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        while !cancelled {
            let result = poll(&descriptorState, 1, Self.writePollMilliseconds)
            if result > 0 {
                return descriptorState.revents & Int16(POLLOUT) != 0
            }
            if result == 0 { continue }
            if errno == EINTR { continue }
            return false
        }
        return false
    }

    private var cancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isCancelled
    }
}
