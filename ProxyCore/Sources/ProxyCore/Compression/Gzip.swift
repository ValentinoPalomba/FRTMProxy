import Foundation

#if canImport(zlib)
import zlib
#endif

enum GzipError: Error {
    case unsupportedPlatform
    case deflateInitFailed(Int32)
    case deflateFailed(Int32)
}

enum Gzip {
    /// Gzip-compress data (RFC 1952).
    static func compress(_ data: Data, level: Int32 = -1) throws -> Data {
        #if !canImport(zlib)
        throw GzipError.unsupportedPlatform
        #else
        if data.isEmpty { return data }

        var stream = z_stream()
        let windowBits: Int32 = 15 + 16 // gzip header/trailer
        let memLevel: Int32 = 8

        let initStatus = deflateInit2_(
            &stream,
            level,
            Z_DEFLATED,
            windowBits,
            memLevel,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw GzipError.deflateInitFailed(initStatus)
        }
        defer { deflateEnd(&stream) }

        let chunkSize = 16 * 1024
        var output = Data()
        output.reserveCapacity(min(data.count, chunkSize))

        try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            guard let baseAddress = input.bindMemory(to: Bytef.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer(mutating: baseAddress)
            stream.avail_in = uInt(data.count)

            var status: Int32 = Z_OK
            repeat {
                var chunk = Data(count: chunkSize)
                let written = chunk.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int in
                    guard let outBase = out.bindMemory(to: Bytef.self).baseAddress else { return 0 }
                    stream.next_out = outBase
                    stream.avail_out = uInt(chunkSize)

                    status = deflate(&stream, stream.avail_in == 0 ? Z_FINISH : Z_NO_FLUSH)
                    return chunkSize - Int(stream.avail_out)
                }

                if written > 0 {
                    chunk.count = written
                    output.append(chunk)
                }

                if status == Z_STREAM_END {
                    break
                }
                if status != Z_OK {
                    throw GzipError.deflateFailed(status)
                }
            } while true
        }

        return output
        #endif
    }
}
