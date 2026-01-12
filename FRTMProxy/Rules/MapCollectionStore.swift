import Foundation
import Compression

protocol MapCollectionStoreProtocol {
    func loadCollections() -> [MapCollection]
    func save(collections: [MapCollection])
    func export(collection: MapCollection, to destinationURL: URL) throws
    func importCollection(at url: URL) throws -> MapCollection
}

final class MapCollectionStore: MapCollectionStoreProtocol {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let collectionsDirectory: URL
    private let storageURL: URL

    init(filename: String = "collections.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("FRTMProxy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collectionsDir = directory.appendingPathComponent("Collections", isDirectory: true)
        try? FileManager.default.createDirectory(at: collectionsDir, withIntermediateDirectories: true)
        self.collectionsDirectory = collectionsDir
        self.storageURL = collectionsDir.appendingPathComponent(filename)
        encoder.outputFormatting = [.prettyPrinted]
    }

    func loadCollections() -> [MapCollection] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: storageURL)
            return try decoder.decode([MapCollection].self, from: data)
        } catch {
            NSLog("Failed to load collections: \(error)")
            return []
        }
    }

    func save(collections: [MapCollection]) {
        do {
            let data = try encoder.encode(collections)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("Failed to save collections: \(error)")
        }
    }

    func export(collection: MapCollection, to destinationURL: URL) throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FRTMCollection-\(collection.id.uuidString)", isDirectory: true)

        try? FileManager.default.removeItem(at: tempRoot)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let rootFolder = tempRoot.appendingPathComponent(collection.name.proxySanitizedFilename(), isDirectory: true)
        try FileManager.default.createDirectory(at: rootFolder, withIntermediateDirectories: true)

        let metadataURL = rootFolder.appendingPathComponent("collection.json")
        let metadataData = try encoder.encode(collection)
        try metadataData.write(to: metadataURL)

        let rulesDirectory = rootFolder.appendingPathComponent("rules", isDirectory: true)
        try FileManager.default.createDirectory(at: rulesDirectory, withIntermediateDirectories: true)

        for rule in collection.rules {
            let filename = rule.displayURL.proxySanitizedFilename()
            let fileURL = rulesDirectory.appendingPathComponent(filename).appendingPathExtension("json")
            let data = try encoder.encode(rule)
            try data.write(to: fileURL)
        }

        try? FileManager.default.removeItem(at: destinationURL)
        try ZipUtility.zipItem(at: rootFolder, to: destinationURL)
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func importCollection(at url: URL) throws -> MapCollection {
        if url.pathExtension.lowercased() == "zip" {
            return try importFromArchive(url)
        } else {
            return try loadCollection(fromDirectory: url)
        }
    }

    private func importFromArchive(_ archiveURL: URL) throws -> MapCollection {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("FRTMCollectionImport-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try ZipUtility.unzipItem(at: archiveURL, to: destination)
        let contents = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let directories = contents.filter { $0.hasDirectoryPath }
        let target: URL
        if let folder = directories.first(where: { $0.lastPathComponent != "__MACOSX" }) ?? directories.first {
            target = folder
        } else {
            target = destination
        }
        let collection = try loadCollection(fromDirectory: target)
        try? FileManager.default.removeItem(at: destination)
        return collection
    }

    private func loadCollection(fromDirectory directory: URL) throws -> MapCollection {
        let metadataURL = directory.appendingPathComponent("collection.json")
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let data = try Data(contentsOf: metadataURL)
            let stored = try decoder.decode(MapCollection.self, from: data)
            let rules = try readRuleFiles(in: directory)
            return MapCollection(
                id: UUID(),
                name: stored.name,
                createdAt: stored.createdAt,
                isEnabled: false,
                enabledAt: nil,
                rules: rules.isEmpty ? stored.rules : rules
            )
        } else {
            let rules = try readRuleFiles(in: directory)
            let name = directory.lastPathComponent
            return MapCollection(
                id: UUID(),
                name: name,
                createdAt: Date(),
                isEnabled: false,
                enabledAt: nil,
                rules: rules.sorted(by: { $0.key < $1.key })
            )
        }
    }

    private func readRuleFiles(in directory: URL) throws -> [MapRule] {
        var rules: [MapRule] = []
        let rulesDirectory = directory.appendingPathComponent("rules", isDirectory: true)
        let target = FileManager.default.fileExists(atPath: rulesDirectory.path) ? rulesDirectory : directory
        let contents = try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        for file in contents where file.pathExtension.lowercased() == "json" {
            if file.lastPathComponent == "collection.json" { continue }
            let data = try Data(contentsOf: file)
            let rule = try decoder.decode(MapRule.self, from: data)
            rules.append(rule)
        }
        return rules.sorted(by: { $0.key < $1.key })
    }
}
