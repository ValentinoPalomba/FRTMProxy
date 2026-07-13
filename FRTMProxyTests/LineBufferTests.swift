import Testing
import Foundation
@testable import FRTMProxy

/// `LineBuffer` fa il framing dei chunk grezzi di stdout in righe complete separate
/// da `\n`. È critico per l'integrità del protocollo JSON line-delimited col bridge.
@Suite("LineBuffer")
struct LineBufferTests {

    /// Collettore thread-safe delle righe consegnate dal buffer.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
        var snapshot: [String] { lock.lock(); defer { lock.unlock() }; return lines }
    }

    private func data(_ s: String) -> Data { Data(s.utf8) }

    @Test("Più righe complete in un solo chunk")
    func multipleLinesSingleChunk() {
        let sink = Sink()
        let buffer = LineBuffer { sink.append($0) }
        buffer.append(data("a\nb\nc\n"))
        #expect(sink.snapshot == ["a", "b", "c"])
    }

    @Test("Riga spezzata tra due chunk viene ricomposta")
    func partialLineAcrossChunks() {
        let sink = Sink()
        let buffer = LineBuffer { sink.append($0) }
        buffer.append(data("hel"))
        #expect(sink.snapshot.isEmpty)
        buffer.append(data("lo\n"))
        #expect(sink.snapshot == ["hello"])
    }

    @Test("Newline a cavallo: la coda di un chunk si unisce alla testa del successivo")
    func newlineStraddlingChunks() {
        let sink = Sink()
        let buffer = LineBuffer { sink.append($0) }
        buffer.append(data("x\ny"))
        buffer.append(data("z\n"))
        #expect(sink.snapshot == ["x", "yz"])
    }

    @Test("Le righe vuote vengono scartate")
    func emptyLinesDropped() {
        let sink = Sink()
        let buffer = LineBuffer { sink.append($0) }
        buffer.append(data("a\n\n\nb\n"))
        #expect(sink.snapshot == ["a", "b"])
    }

    @Test("Sequenza UTF-8 multibyte spezzata tra chunk viene ricomposta correttamente")
    func multibyteUTF8SplitAcrossChunks() {
        let sink = Sink()
        let buffer = LineBuffer { sink.append($0) }
        // "é" in UTF-8 = 0xC3 0xA9
        buffer.append(Data([0xC3]))
        #expect(sink.snapshot.isEmpty)
        buffer.append(Data([0xA9, 0x0A])) // secondo byte di 'é' + '\n'
        #expect(sink.snapshot == ["é"])
    }

    @Test("Una riga senza newline finale resta bufferizzata")
    func trailingPartialStaysBuffered() {
        let sink = Sink()
        let buffer = LineBuffer { sink.append($0) }
        buffer.append(data("complete\npartial"))
        #expect(sink.snapshot == ["complete"])
    }

    @Test("Append concorrenti: nessuna riga persa e nessuna corruzione")
    func concurrentAppends() {
        let sink = Sink()
        let buffer = LineBuffer { sink.append($0) }
        let iterations = 500
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            buffer.append(data("line-\(i)\n"))
        }
        let lines = sink.snapshot
        #expect(lines.count == iterations)
        // Ogni riga è integra (una sola per iterazione, tutte del formato atteso)
        #expect(Set(lines) == Set((0..<iterations).map { "line-\($0)" }))
    }
}
