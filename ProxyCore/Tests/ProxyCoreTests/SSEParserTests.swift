import XCTest
import NIO
@testable import ProxyCore

final class SSEParserTests: XCTestCase {
    func testParsesSingleEventAcrossChunks() {
        var parser = SSEParser()
        let allocator = ByteBufferAllocator()

        var buf1 = allocator.buffer(capacity: 0)
        buf1.writeString("event: message\nid: 1\ndata: hel")
        XCTAssertEqual(parser.append(buf1).count, 0)

        var buf2 = allocator.buffer(capacity: 0)
        buf2.writeString("lo\n\n")
        let events = parser.append(buf2)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].event, "message")
        XCTAssertEqual(events[0].id, "1")
        XCTAssertEqual(events[0].data, "hello")
    }

    func testParsesMultiLineData() {
        var parser = SSEParser()
        let allocator = ByteBufferAllocator()

        var buf = allocator.buffer(capacity: 0)
        buf.writeString("data: a\ndata: b\n\n")

        let events = parser.append(buf)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "a\nb")
    }

    func testIgnoresCommentsAndHandlesCRLF() {
        var parser = SSEParser()
        let allocator = ByteBufferAllocator()

        var buf = allocator.buffer(capacity: 0)
        buf.writeString(":comment\r\ndata: hi\r\n\r\n")

        let events = parser.append(buf)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "hi")
    }
}

