import XCTest
import NIO
@testable import ProxyCore

final class TLSClientHelloParserTests: XCTestCase {
    func testParseExtractsSNIAndALPN() {
        let bytes = Self.makeClientHelloBytes(host: "example.com", alpns: ["h2", "http/1.1"])
        var buffer = ByteBufferAllocator().buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)

        let info = TLSClientHelloParser.parse(buffer)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.sniHost, "example.com")
        XCTAssertEqual(info?.alpnProtocols, ["h2", "http/1.1"])
    }

    private static func makeClientHelloBytes(host: String, alpns: [String]) -> [UInt8] {
        var out = Array<UInt8>(repeating: 0, count: 87)

        // Minimal markers for isTLSClientHello
        out[0] = 0x16
        out[1] = 0x03
        out[2] = 0x01
        out[5] = 0x01
        out[9] = 0x03
        out[10] = 0x03

        // session length at offset 43
        out[43] = 0

        // cipher suites length at 44..45 = 0
        out[44] = 0
        out[45] = 0

        // compression methods length at 46 = 0
        out[46] = 0

        // extensions length at 47..48
        out[47] = 0
        out[48] = 0x26 // 38 bytes

        var pos = 49

        // server_name extension
        let hostBytes = Array(host.utf8)
        let listLen = 1 + 2 + hostBytes.count
        let extPayloadLen = 2 + listLen

        // type 0
        out[pos] = 0
        out[pos + 1] = 0
        // length
        out[pos + 2] = UInt8((extPayloadLen >> 8) & 0xFF)
        out[pos + 3] = UInt8(extPayloadLen & 0xFF)
        pos += 4

        // list length
        out[pos] = UInt8((listLen >> 8) & 0xFF)
        out[pos + 1] = UInt8(listLen & 0xFF)
        pos += 2

        // name type
        out[pos] = 0
        // name length
        out[pos + 1] = UInt8((hostBytes.count >> 8) & 0xFF)
        out[pos + 2] = UInt8(hostBytes.count & 0xFF)
        pos += 3

        out.replaceSubrange(pos..<(pos + hostBytes.count), with: hostBytes)
        pos += hostBytes.count

        // ALPN extension
        let alpnListBytes: [UInt8] = alpns.flatMap { proto in
            let p = Array(proto.utf8)
            return [UInt8(p.count)] + p
        }
        let alpnListLen = alpnListBytes.count
        let alpnPayloadLen = 2 + alpnListLen

        // type 16
        out[pos] = 0
        out[pos + 1] = 16
        // length
        out[pos + 2] = UInt8((alpnPayloadLen >> 8) & 0xFF)
        out[pos + 3] = UInt8(alpnPayloadLen & 0xFF)
        pos += 4

        // list length
        out[pos] = UInt8((alpnListLen >> 8) & 0xFF)
        out[pos + 1] = UInt8(alpnListLen & 0xFF)
        pos += 2

        out.replaceSubrange(pos..<(pos + alpnListLen), with: alpnListBytes)
        pos += alpnListLen

        return out
    }
}
