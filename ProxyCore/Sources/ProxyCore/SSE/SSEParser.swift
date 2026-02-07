import Foundation
import NIO

/// Incremental parser for Server-Sent Events (text/event-stream).
struct SSEParser: Sendable {
    struct ParsedEvent: Sendable {
        var event: String?
        var id: String?
        var data: String
    }

    private var pending = Data()
    private var consumed = 0

    private var currentEvent: String?
    private var currentID: String?
    private var currentDataLines: [String] = []

    mutating func append(_ buffer: ByteBuffer) -> [ParsedEvent] {
        var buf = buffer
        if let bytes = buf.readBytes(length: buf.readableBytes), !bytes.isEmpty {
            pending.append(contentsOf: bytes)
        }

        var out: [ParsedEvent] = []

        while true {
            guard let newlineIndex = findNewline(from: consumed) else {
                break
            }

            var lineBytes = pending[consumed..<newlineIndex]
            consumed = newlineIndex + 1

            // Trim trailing '\r' (CRLF).
            if lineBytes.last == 0x0D {
                lineBytes = lineBytes.dropLast()
            }

            let line = String(decoding: lineBytes, as: UTF8.self)

            if line.isEmpty {
                if !currentDataLines.isEmpty || currentEvent != nil || currentID != nil {
                    let data = currentDataLines.joined(separator: "\n")
                    out.append(ParsedEvent(event: currentEvent, id: currentID, data: data))
                }
                resetCurrent()
                continue
            }

            if line.hasPrefix(":") {
                continue
            }

            let field: Substring
            let value: Substring
            if let colon = line.firstIndex(of: ":") {
                field = line[..<colon]
                var v = line[line.index(after: colon)...]
                if v.first == " " {
                    v = v.dropFirst()
                }
                value = v
            } else {
                field = Substring(line)
                value = ""
            }

            switch field {
            case "event":
                currentEvent = String(value)
            case "data":
                currentDataLines.append(String(value))
            case "id":
                currentID = String(value)
            case "retry":
                break
            default:
                break
            }
        }

        // Compact buffer periodically.
        if consumed > 0, consumed >= 4096 || consumed == pending.count {
            pending.removeSubrange(0..<consumed)
            consumed = 0
        }

        return out
    }

    private mutating func resetCurrent() {
        currentEvent = nil
        currentID = nil
        currentDataLines.removeAll(keepingCapacity: true)
    }

    private func findNewline(from start: Int) -> Int? {
        guard start < pending.count else { return nil }

        // Scan for LF. (SSE uses LF line endings; CRLF is permitted.)
        let end = pending.count
        return pending.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt8.self).baseAddress!
            var i = start
            while i < end {
                if ptr[i] == 0x0A {
                    return i
                }
                i += 1
            }
            return nil
        }
    }
}
