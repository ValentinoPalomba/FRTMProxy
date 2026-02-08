import Foundation
import NIO

/// Minimal SOCKS5 server handshake (no-auth) that upgrades the pipeline into a CONNECT-style tunnel.
///
/// Parity with ProxyPin: no-auth, CONNECT, IPv4 at minimum.
final class Socks5HandshakeHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private enum State {
        case greeting
        case connect
        case connected
    }

    private let configuration: ProxyConfiguration
    private let eventBus: ProxyEventBus
    private let interceptors: [any ProxyInterceptor]
    private let certificateAuthority: CertificateAuthority
    private let processInfoProvider: ProcessInfoProvider
    private let trafficController: TrafficProfileController
    private let group: EventLoopGroup

    private var state: State = .greeting
    private var buffer: ByteBuffer?

    init(
        configuration: ProxyConfiguration,
        eventBus: ProxyEventBus,
        interceptors: [any ProxyInterceptor],
        certificateAuthority: CertificateAuthority,
        processInfoProvider: ProcessInfoProvider,
        trafficController: TrafficProfileController,
        group: EventLoopGroup
    ) {
        self.configuration = configuration
        self.eventBus = eventBus
        self.interceptors = interceptors
        self.certificateAuthority = certificateAuthority
        self.processInfoProvider = processInfoProvider
        self.trafficController = trafficController
        self.group = group
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var inbound = unwrapInboundIn(data)
        if buffer == nil {
            buffer = inbound
        } else {
            buffer?.writeBuffer(&inbound)
        }

        guard buffer != nil else { return }
        processBuffer(context: context)
    }

    private func processBuffer(context: ChannelHandlerContext) {
        while true {
            switch state {
            case .greeting:
                guard var buf = buffer else { return }
                // VER, NMETHODS, METHODS...
                guard buf.readableBytes >= 2 else { buffer = buf; return }
                guard let ver: UInt8 = buf.getInteger(at: buf.readerIndex) else { buffer = buf; return }
                guard ver == 0x05 else {
                    writeGreetingResponse(context: context, method: 0xFF)
                    context.close(promise: nil)
                    return
                }
                guard let nmethods: UInt8 = buf.getInteger(at: buf.readerIndex + 1) else { buffer = buf; return }
                let methodsCount = Int(nmethods)
                guard buf.readableBytes >= 2 + methodsCount else { buffer = buf; return }

                buf.moveReaderIndex(forwardBy: 2)
                let methods = buf.readBytes(length: methodsCount) ?? []
                buffer = buf

                if methods.contains(0x00) {
                    writeGreetingResponse(context: context, method: 0x00) // no-auth
                    state = .connect
                    continue
                } else {
                    writeGreetingResponse(context: context, method: 0xFF) // no acceptable methods
                    context.close(promise: nil)
                    return
                }

            case .connect:
                guard var buf = buffer else { return }
                // VER, CMD, RSV, ATYP
                guard buf.readableBytes >= 4 else { buffer = buf; return }
                guard let ver: UInt8 = buf.getInteger(at: buf.readerIndex) else { buffer = buf; return }
                guard ver == 0x05 else {
                    context.close(promise: nil)
                    return
                }
                let cmd: UInt8 = buf.getInteger(at: buf.readerIndex + 1) ?? 0
                // Skip RSV (idx+2)
                let atyp: UInt8 = buf.getInteger(at: buf.readerIndex + 3) ?? 0

                guard cmd == 0x01 else {
                    writeConnectResponse(context: context, rep: 0x07) // command not supported
                    context.close(promise: nil)
                    return
                }

                // Compute variable address length.
                let addrStart = buf.readerIndex + 4
                var host: String = ""
                var addrTotalLength: Int = 0
                switch atyp {
                case 0x01: // IPv4
                    addrTotalLength = 4
                    guard buf.readableBytes >= 4 + addrTotalLength + 2 else { buffer = buf; return }
                    let b0: UInt8 = buf.getInteger(at: addrStart) ?? 0
                    let b1: UInt8 = buf.getInteger(at: addrStart + 1) ?? 0
                    let b2: UInt8 = buf.getInteger(at: addrStart + 2) ?? 0
                    let b3: UInt8 = buf.getInteger(at: addrStart + 3) ?? 0
                    host = "\(b0).\(b1).\(b2).\(b3)"

                case 0x03: // Domain
                    guard buf.readableBytes >= 5 else { buffer = buf; return }
                    let len: UInt8 = buf.getInteger(at: addrStart) ?? 0
                    addrTotalLength = 1 + Int(len)
                    guard buf.readableBytes >= 4 + addrTotalLength + 2 else { buffer = buf; return }
                    if let bytes = buf.getBytes(at: addrStart + 1, length: Int(len)),
                       let s = String(bytes: bytes, encoding: .utf8) {
                        host = s
                    } else {
                        host = ""
                    }

                case 0x04: // IPv6
                    addrTotalLength = 16
                    guard buf.readableBytes >= 4 + addrTotalLength + 2 else { buffer = buf; return }
                    if let bytes = buf.getBytes(at: addrStart, length: 16) {
                        host = Self.formatIPv6(bytes)
                    }

                default:
                    writeConnectResponse(context: context, rep: 0x08) // address type not supported
                    context.close(promise: nil)
                    return
                }

                let portIndex = addrStart + addrTotalLength
                let p0: UInt8 = buf.getInteger(at: portIndex) ?? 0
                let p1: UInt8 = buf.getInteger(at: portIndex + 1) ?? 0
                let port = Int(UInt16(p0) << 8 | UInt16(p1))

                // Consume the whole request.
                buf.moveReaderIndex(forwardBy: 4 + addrTotalLength + 2)
                let leftover = buf.readSlice(length: buf.readableBytes)
                buffer = nil

                eventBus.emit(.log("[ProxyCore] SOCKS5 CONNECT \(host):\(port)\n"))

                // Reply success.
                writeConnectResponse(context: context, rep: 0x00)

                // Upgrade to a CONNECT-style tunnel handler (raw bytes, optional MITM).
                let requestID = Self.makeRequestID()
                let tunnel = ConnectTunnelHandler(
                    configuration: configuration,
                    eventBus: eventBus,
                    interceptors: interceptors,
                    certificateAuthority: certificateAuthority,
                    processInfoProvider: processInfoProvider,
                    trafficController: trafficController,
                    group: group,
                    targetHost: host,
                    targetPort: port,
                    connectRequestID: requestID
                )

                let pipeline = context.channel.pipeline
                pipeline.addHandler(tunnel, position: .last).flatMap {
                    pipeline.removeHandler(self)
                }.whenComplete { _ in
                    if let leftover {
                        context.channel.pipeline.fireChannelRead(leftover)
                        context.channel.pipeline.fireChannelReadComplete()
                    }
                }

                state = .connected
                return

            case .connected:
                return
            }
        }
    }

    private func writeGreetingResponse(context: ChannelHandlerContext, method: UInt8) {
        var out = context.channel.allocator.buffer(capacity: 2)
        out.writeInteger(UInt8(0x05))
        out.writeInteger(method)
        context.writeAndFlush(self.wrapOutboundOut(out), promise: nil)
    }

    private func writeConnectResponse(context: ChannelHandlerContext, rep: UInt8) {
        // VER, REP, RSV, ATYP, BND.ADDR, BND.PORT
        var out = context.channel.allocator.buffer(capacity: 10)
        out.writeInteger(UInt8(0x05))
        out.writeInteger(rep)
        out.writeInteger(UInt8(0x00))
        out.writeInteger(UInt8(0x01)) // IPv4
        out.writeBytes([0, 0, 0, 0])  // 0.0.0.0
        out.writeInteger(UInt16(0))
        context.writeAndFlush(self.wrapOutboundOut(out), promise: nil)
    }

    private static func formatIPv6(_ bytes: [UInt8]) -> String {
        precondition(bytes.count == 16)
        var parts: [String] = []
        parts.reserveCapacity(8)
        for i in stride(from: 0, to: 16, by: 2) {
            let part = UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
            parts.append(String(part, radix: 16))
        }
        return parts.joined(separator: ":")
    }

    private static func makeRequestID() -> String {
        let t = UInt64(Date().timeIntervalSince1970 * 1000)
        let r = UInt64.random(in: 0..<UInt64.max)
        return String((t ^ r), radix: 36)
    }
}
