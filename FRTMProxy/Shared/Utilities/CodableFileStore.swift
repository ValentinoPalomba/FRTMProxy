import Foundation

/// Load/save di tipi `Codable` su file JSON con protezione contro la perdita
/// silenziosa dei dati.
///
/// Il pattern precedente degli store (`catch { return [] }`) trattava un decode
/// fallito come "file vuoto": il chiamante salvava poi lo stato vuoto e
/// **sovrascriveva definitivamente** dati validi ma non più deserializzabili
/// (es. dopo un cambio di schema o un troncamento). Qui un decode fallito viene
/// invece distinto dal file assente: il file corrotto viene messo da parte con
/// un nome `*.corrupt-<timestamp>` e l'errore è reso esplicito al chiamante.
enum CodableFileStore {

    enum LoadResult<Value> {
        /// Il file non esiste ancora (primo avvio, nessun dato salvato).
        case missing
        /// Decodifica riuscita.
        case loaded(Value)
        /// Il file esiste ma non è decodificabile; è stato spostato in backup.
        case corrupted(Error)
    }

    /// Carica e decodifica `type` da `url`. Su decode fallito esegue il backup
    /// del file corrotto e ritorna `.corrupted` senza cancellare i dati.
    static func load<Value: Decodable>(
        _ type: Value.Type,
        from url: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) -> LoadResult<Value> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try decoder.decode(type, from: data))
        } catch {
            backUpCorruptedFile(at: url, error: error)
            return .corrupted(error)
        }
    }

    /// Scrittura atomica del valore codificato.
    static func save<Value: Encodable>(
        _ value: Value,
        to url: URL,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    /// Rinomina il file corrotto in `<name>.corrupt-<timestamp>.<ext>` così i
    /// dati non vengono persi e non bloccano la scrittura successiva.
    private static func backUpCorruptedFile(at url: URL, error: Error) {
        let timestamp = backupTimestampFormatter.string(from: Date())
        let ext = url.pathExtension
        var backupURL = url.deletingPathExtension().appendingPathExtension("corrupt-\(timestamp)")
        if !ext.isEmpty {
            backupURL = backupURL.appendingPathExtension(ext)
        }
        do {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.moveItem(at: url, to: backupURL)
            NSLog("CodableFileStore: corrupted \(url.lastPathComponent) backed up to \(backupURL.lastPathComponent): \(error)")
        } catch {
            NSLog("CodableFileStore: failed to back up corrupted \(url.lastPathComponent): \(error)")
        }
    }

    private static let backupTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
