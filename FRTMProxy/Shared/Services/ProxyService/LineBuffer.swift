import Foundation

/// Accumula i chunk grezzi letti dallo stdout di un processo e ne estrae righe
/// complete (separate da `\n`), in modo thread-safe.
///
/// I `readabilityHandler` di `FileHandle` vengono invocati su un thread privato
/// di Foundation, non necessariamente sempre lo stesso: mutare un `Data`
/// catturato per riferimento dalla closure senza sincronizzazione è una data
/// race che può corrompere il framing JSON. Questo tipo incapsula il buffer
/// dietro un lock e consegna le righe complete fuori dal lock.
final class LineBuffer {
    private var buffer = Data()
    private let lock = NSLock()
    private let onLine: (String) -> Void
    private let maximumLineBytes: Int
    private let onOverflow: () -> Void
    private var discarding = false

    private static let newline: UInt8 = 0x0A

    init(maximumLineBytes: Int = 16 * 1024 * 1024, onOverflow: @escaping () -> Void = {}, onLine: @escaping (String) -> Void) {
        self.maximumLineBytes = max(1, maximumLineBytes)
        self.onOverflow = onOverflow
        self.onLine = onLine
    }

    /// Aggiunge un chunk e consegna ogni riga UTF-8 non vuota completata.
    func append(_ chunk: Data) {
        var completedLines: [String] = []
        var overflowCount = 0

        lock.lock()
        var start = chunk.startIndex
        while start < chunk.endIndex {
            let newline = chunk[start...].firstIndex(of: Self.newline)
            let end = newline ?? chunk.endIndex
            if !discarding {
                if buffer.count + end - start > maximumLineBytes {
                    buffer.removeAll(keepingCapacity: false)
                    discarding = true
                    overflowCount += 1
                } else {
                    buffer.append(contentsOf: chunk[start..<end])
                }
            }
            guard let newline else { break }
            if !discarding, let text = String(data: buffer, encoding: .utf8), !text.isEmpty {
                completedLines.append(text)
            }
            buffer.removeAll(keepingCapacity: true)
            discarding = false
            start = newline + 1
        }
        lock.unlock()

        for _ in 0..<overflowCount { onOverflow() }
        // onLine fuori dal lock: evita reentrancy e riduce la contesa.
        for line in completedLines {
            onLine(line)
        }
    }
}
