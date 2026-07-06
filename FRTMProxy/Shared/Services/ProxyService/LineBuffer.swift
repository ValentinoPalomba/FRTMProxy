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

    private static let newline: UInt8 = 0x0A

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    /// Aggiunge un chunk e consegna ogni riga UTF-8 non vuota completata.
    func append(_ chunk: Data) {
        var completedLines: [String] = []

        lock.lock()
        buffer.append(chunk)
        while let range = buffer.firstRange(of: Data([Self.newline])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            if let text = String(data: lineData, encoding: .utf8), !text.isEmpty {
                completedLines.append(text)
            }
        }
        lock.unlock()

        // onLine fuori dal lock: evita reentrancy e riduce la contesa.
        for line in completedLines {
            onLine(line)
        }
    }
}
