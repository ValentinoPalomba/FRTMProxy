import Foundation
import NIO

/// When enabled, the local proxy behaves like a raw TCP forwarder to another proxy instance.
/// This is used to implement ProxyPin-style "remote forward": no local interception/capture.
final class RemoteForwardHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let remoteHost: String
    private let remotePort: Int
    private let group: EventLoopGroup
    private let eventBus: ProxyEventBus

    private var remoteChannel: Channel?
    private var pendingClientBytes: ByteBuffer?
    private var isConnecting = false

    init(remoteHost: String, remotePort: Int, group: EventLoopGroup, eventBus: ProxyEventBus) {
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.group = group
        self.eventBus = eventBus
    }

    func channelActive(context: ChannelHandlerContext) {
        // Connect eagerly so the first bytes can be forwarded immediately.
        connectIfNeeded(clientContext: context)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)

        if let remoteChannel {
            remoteChannel.eventLoop.execute {
                remoteChannel.writeAndFlush(buffer, promise: nil)
            }
            return
        }

        // Not connected yet; buffer and connect.
        if pendingClientBytes == nil {
            pendingClientBytes = buffer
        } else {
            pendingClientBytes?.writeBuffer(&buffer)
        }

        connectIfNeeded(clientContext: context)
    }

    func channelInactive(context: ChannelHandlerContext) {
        remoteChannel?.close(promise: nil)
        context.fireChannelInactive()
    }

    private func connectIfNeeded(clientContext: ChannelHandlerContext) {
        guard !isConnecting, remoteChannel == nil else { return }
        isConnecting = true

        let clientChannel = clientContext.channel
        eventBus.emit(.log("[ProxyCore] Remote forward -> \(remoteHost):\(remotePort)\n"))

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(RelayHandler(peer: clientChannel))
            }

        bootstrap.connect(host: remoteHost, port: remotePort).whenComplete { result in
            self.isConnecting = false

            switch result {
            case .success(let remote):
                self.remoteChannel = remote

                // Swap this handler out for a pure relay.
                clientChannel.pipeline.addHandler(RelayHandler(peer: remote)).flatMap {
                    clientChannel.pipeline.removeHandler(self)
                }.whenComplete { _ in
                    if var pending = self.pendingClientBytes {
                        self.pendingClientBytes = nil
                        remote.eventLoop.execute {
                            remote.writeAndFlush(pending, promise: nil)
                        }
                    }
                }

            case .failure(let error):
                self.eventBus.emit(.log("[ProxyCore] Remote forward connect failed: \(error)\n"))
                clientChannel.close(promise: nil)
            }
        }
    }
}

