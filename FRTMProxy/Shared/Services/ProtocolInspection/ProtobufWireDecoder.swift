import Foundation

enum ProtobufWireDecoder {
    static func decode(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        var cursor = data.startIndex
        var lines: [String] = []

        while cursor < data.endIndex {
            guard let key = readVarint(data, cursor: &cursor) else { return nil }
            let fieldNumber = key >> 3
            let wireType = Int(key & 0x07)
            guard fieldNumber > 0 else { return nil }

            switch wireType {
            case 0:
                guard let value = readVarint(data, cursor: &cursor) else { return nil }
                lines.append("\(fieldNumber): varint \(value)")
            case 1:
                guard let value = readFixed(data, cursor: &cursor, byteCount: 8) else { return nil }
                lines.append("\(fieldNumber): fixed64 0x\(hex(value))")
            case 2:
                guard let length = readVarint(data, cursor: &cursor),
                      length <= UInt64(data.distance(from: cursor, to: data.endIndex))
                else { return nil }
                let end = data.index(cursor, offsetBy: Int(length))
                let payload = Data(data[cursor..<end])
                cursor = end
                lines.append("\(fieldNumber): bytes[\(length)] \(render(payload))")
            case 5:
                guard let value = readFixed(data, cursor: &cursor, byteCount: 4) else { return nil }
                lines.append("\(fieldNumber): fixed32 0x\(hex(value))")
            default:
                return nil
            }
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func readVarint(_ data: Data, cursor: inout Data.Index) -> UInt64? {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard cursor < data.endIndex else { return nil }
            let byte = data[cursor]
            cursor = data.index(after: cursor)
            result |= UInt64(byte & 0x7f) << UInt64(shift)
            if byte & 0x80 == 0 { return result }
        }
        return nil
    }

    private static func readFixed(_ data: Data, cursor: inout Data.Index, byteCount: Int) -> Data? {
        guard data.distance(from: cursor, to: data.endIndex) >= byteCount else { return nil }
        let end = data.index(cursor, offsetBy: byteCount)
        defer { cursor = end }
        return Data(data[cursor..<end])
    }

    private static func render(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8),
           data.allSatisfy({ $0 == 9 || $0 == 10 || $0 == 13 || $0 >= 32 }) {
            return String(reflecting: text)
        }
        if let nested = decode(data) {
            return "{ \(nested.replacing("\n", with: "; ")) }"
        }
        return "0x\(hex(data))"
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
