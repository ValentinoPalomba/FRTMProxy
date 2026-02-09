import Foundation
import NIO

struct TLSClientHelloInfo: Sendable {
    var sniHost: String?
    var alpnProtocols: [String]
}

// Ported from ProxyPin's TLS parser. This is intentionally minimal: we only need SNI + ALPN.
enum TLSClientHelloParser {
    static func isTLSClientHello(_ buffer: ByteBuffer) -> Bool {
        var b = buffer
        guard let first: UInt8 = b.getInteger(at: b.readerIndex, as: UInt8.self) else { return false }
        guard first == 0x16 else { return false } // handshake
        guard let major: UInt8 = b.getInteger(at: b.readerIndex + 1, as: UInt8.self), major == 0x03 else { return false }
        guard let minor: UInt8 = b.getInteger(at: b.readerIndex + 2, as: UInt8.self), minor <= 0x03 else { return false }
        guard let hsType: UInt8 = b.getInteger(at: b.readerIndex + 5, as: UInt8.self), hsType == 0x01 else { return false } // client_hello
        guard let hsMajor: UInt8 = b.getInteger(at: b.readerIndex + 9, as: UInt8.self), hsMajor == 0x03 else { return false }
        guard let hsMinor: UInt8 = b.getInteger(at: b.readerIndex + 10, as: UInt8.self), hsMinor <= 0x03 else { return false }
        return true
    }

    static func parse(_ buffer: ByteBuffer) -> TLSClientHelloInfo? {
        guard isTLSClientHello(buffer) else { return nil }
        var data = buffer
        let bytes = data.readableBytesView
        if bytes.count < 43 {
            return nil
        }

        // This parser assumes the ClientHello begins at offset 0 of the record payload.
        // It matches ProxyPin's implementation and is sufficient for ALPN/SNI extraction.
        func u16(_ index: Int) -> Int {
            let hi = Int(bytes[bytes.startIndex.advanced(by: index)])
            let lo = Int(bytes[bytes.startIndex.advanced(by: index + 1)])
            return (hi << 8) | lo
        }

        var pos = 43
        let sessionLen = Int(bytes[bytes.startIndex.advanced(by: pos)])
        pos += 1 + sessionLen
        if bytes.count < pos + 2 { return nil }

        let cipherSuitesLen = u16(pos)
        pos += 2 + cipherSuitesLen
        if bytes.count < pos + 1 { return nil }

        let compressionLen = Int(bytes[bytes.startIndex.advanced(by: pos)])
        pos += 1 + compressionLen
        if bytes.count < pos + 2 { return nil }

        let extensionsLen = u16(pos)
        pos += 2
        if bytes.count < pos + extensionsLen { return nil }

        let end = pos + extensionsLen
        var sni: String?
        var alpn: [String] = []

        while pos + 4 <= end {
            let extType = u16(pos)
            let extLen = u16(pos + 2)
            pos += 4

            // Compute the end of this extension and bounds-check it
            let extEnd = pos + extLen
            if extEnd > end { break }

            if extType == 0 { // server_name
                if pos + 2 > extEnd { pos = extEnd; continue }
                let listLen = u16(pos)
                pos += 2
                if pos + listLen > extEnd { pos = extEnd; continue }

                if pos + 3 > extEnd { pos = extEnd; continue }
                let nameType = Int(bytes[bytes.startIndex.advanced(by: pos)])
                let nameLen = u16(pos + 1)
                pos += 3
                if nameType != 0 { pos = extEnd; continue }
                if pos + nameLen > extEnd { pos = extEnd; continue }

                let start = bytes.startIndex.advanced(by: pos)
                let hostBytes = bytes[start..<start.advanced(by: nameLen)]
                sni = String(decoding: hostBytes, as: UTF8.self)
                pos = extEnd
                continue
            }

            if extType == 16 { // ALPN
                if pos + 2 > extEnd { pos = extEnd; continue }
                let alpnExtLen = u16(pos)
                pos += 2
                if pos + alpnExtLen > extEnd { pos = extEnd; continue }

                let alpnEnd = pos + alpnExtLen
                while pos + 1 <= alpnEnd {
                    let protoLen = Int(bytes[bytes.startIndex.advanced(by: pos)])
                    pos += 1
                    if pos + protoLen > alpnEnd { break }

                    let start = bytes.startIndex.advanced(by: pos)
                    let pBytes = bytes[start..<start.advanced(by: protoLen)]
                    alpn.append(String(decoding: pBytes, as: UTF8.self))
                    pos += protoLen
                }
                pos = extEnd
                continue
            }

            // Skip unknown extensions
            pos = extEnd
        }

        return TLSClientHelloInfo(sniHost: sni, alpnProtocols: alpn)
    }
}
