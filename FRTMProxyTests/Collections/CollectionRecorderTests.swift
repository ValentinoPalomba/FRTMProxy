import Testing
import Foundation
@testable import FRTMProxy

@Suite("CollectionRecorder")
struct CollectionRecorderTests {

    private func rule(key: String, host: String = "h.com", path: String = "/p") -> MapRule {
        MapRule(key: key, host: host, path: path, body: "{}", status: 200, headers: [:])
    }

    @Test("Stato iniziale: non sta registrando")
    func initialState() {
        let recorder = CollectionRecorder()
        #expect(recorder.isRecording == false)
        #expect(recorder.recordingName == nil)
        #expect(recorder.currentRules().isEmpty)
    }

    @Test("start avvia una sessione con il nome dato")
    func startSession() {
        let recorder = CollectionRecorder()
        recorder.start(name: "Sessione 1")
        #expect(recorder.isRecording)
        #expect(recorder.recordingName == "Sessione 1")
    }

    @Test("record senza sessione attiva è no-op")
    func recordWithoutSession() {
        let recorder = CollectionRecorder()
        recorder.record(rule: rule(key: "k1"))
        #expect(recorder.currentRules().isEmpty)
    }

    @Test("record preserva l'ordine di inserimento")
    func recordPreservesOrder() {
        let recorder = CollectionRecorder()
        recorder.start(name: "S")
        recorder.record(rule: rule(key: "b"))
        recorder.record(rule: rule(key: "a"))
        recorder.record(rule: rule(key: "c"))
        #expect(recorder.currentRules().map(\.key) == ["b", "a", "c"])
    }

    @Test("record sulla stessa key aggiorna senza duplicare l'ordine")
    func recordDedup() {
        let recorder = CollectionRecorder()
        recorder.start(name: "S")
        recorder.record(rule: rule(key: "k", host: "old.com"))
        recorder.record(rule: rule(key: "x"))
        recorder.record(rule: rule(key: "k", host: "new.com"))
        let rules = recorder.currentRules()
        #expect(rules.map(\.key) == ["k", "x"])
        #expect(rules.first(where: { $0.key == "k" })?.host == "new.com")
    }

    @Test("stopAndCreateCollection produce la collection e termina la sessione")
    func stopAndCreate() {
        let recorder = CollectionRecorder()
        recorder.start(name: "Export")
        recorder.record(rule: rule(key: "1"))
        recorder.record(rule: rule(key: "2"))
        let collection = recorder.stopAndCreateCollection()
        #expect(collection?.name == "Export")
        #expect(collection?.rules.map(\.key) == ["1", "2"])
        #expect(collection?.isEnabled == false)
        #expect(recorder.isRecording == false)
    }

    @Test("stopAndCreateCollection senza sessione restituisce nil")
    func stopWithoutSession() {
        let recorder = CollectionRecorder()
        #expect(recorder.stopAndCreateCollection() == nil)
    }

    @Test("discard butta via la sessione senza produrre nulla")
    func discardSession() {
        let recorder = CollectionRecorder()
        recorder.start(name: "S")
        recorder.record(rule: rule(key: "1"))
        recorder.discard()
        #expect(recorder.isRecording == false)
        #expect(recorder.currentRules().isEmpty)
    }
}
