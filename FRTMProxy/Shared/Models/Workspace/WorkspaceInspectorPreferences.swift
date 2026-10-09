import Foundation

struct WorkspaceInspectorPreferences: Codable, Equatable, Sendable {
    struct NoiseControl: Codable, Equatable, Sendable {
        static let queryKey = "inspector.noiseQuery"
        static let enabledKey = "inspector.noiseEnabled"
        let query: String
        let enabled: Bool
        func validate() throws {
            guard query.utf8.count <= 4096 else { throw CocoaError(.fileReadTooLarge) }
        }
    }
    var captureProfiles: [CaptureProfile]? = nil
    var activeCaptureProfileID: UUID? = nil
    var focusSets: [SavedFocusSet]? = nil
    var noiseControl: NoiseControl? = nil
    let headerColumns: [FlowHeaderColumn]
    var headerSortID: UUID? = nil
    var sortAscending = true

    func validate() throws {
        _ = try profileSnapshotData()
        if let focusSets { _ = try SavedFocusSet.encode(focusSets) }
        try noiseControl?.validate()
        try FlowHeaderColumn.validate(headerColumns)
        guard headerSortID == nil || headerColumns.contains(where: { $0.id == headerSortID }) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
    }
    static func read(from defaults: UserDefaults = .standard, profileDefaults: UserDefaults? = nil) throws -> Self {
        let profileDefaults = profileDefaults ?? defaults
        let snapshot: CaptureProfileStore.Snapshot?
        if let saved = profileDefaults.object(forKey: CaptureProfileStore.dataKey) {
            guard let data = saved as? Data else { throw CocoaError(.fileReadCorruptFile) }
            snapshot = try CaptureProfileStore.decodedSnapshot(data)
        } else {
            snapshot = nil
        }
        if let saved = defaults.object(forKey: FlowHeaderColumn.dataKey), !(saved is Data) {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let saved = defaults.object(forKey: SavedFocusSet.dataKey), !(saved is Data) {
            throw CocoaError(.fileReadCorruptFile)
        }
        let scopes = try defaults.data(forKey: SavedFocusSet.dataKey).map(SavedFocusSet.decode)
        let noise: NoiseControl? = defaults.object(forKey: NoiseControl.queryKey) != nil || defaults.object(forKey: NoiseControl.enabledKey) != nil
            ? NoiseControl(query: defaults.string(forKey: NoiseControl.queryKey) ?? "", enabled: defaults.bool(forKey: NoiseControl.enabledKey)) : nil
        try noise?.validate()
        let columns = try FlowHeaderColumn.decode(defaults.data(forKey: FlowHeaderColumn.dataKey) ?? Data())
        let sortID = defaults.string(forKey: FlowHeaderColumn.sortKey).flatMap(UUID.init(uuidString:))
        return Self(captureProfiles: snapshot?.profiles, activeCaptureProfileID: snapshot?.activeProfileID,
                    focusSets: scopes, noiseControl: noise, headerColumns: columns, headerSortID: columns.contains(where: { $0.id == sortID }) ? sortID : nil,
                    sortAscending: defaults.object(forKey: FlowHeaderColumn.directionKey) as? Bool ?? true)
    }
    func apply(to defaults: UserDefaults = .standard, profileDefaults: UserDefaults? = nil) throws {
        try validate()
        let data = try JSONEncoder().encode(headerColumns)
        let scopeData = try focusSets.map(SavedFocusSet.encode)
        let profileData = try profileSnapshotData()
        if let profileData {
            (profileDefaults ?? defaults).set(profileData, forKey: CaptureProfileStore.dataKey)
        }
        defaults.set(data, forKey: FlowHeaderColumn.dataKey)
        if let scopeData { defaults.set(scopeData, forKey: SavedFocusSet.dataKey) }
        if let noiseControl {
            defaults.set(noiseControl.query, forKey: NoiseControl.queryKey)
            defaults.set(noiseControl.enabled, forKey: NoiseControl.enabledKey)
        }
        defaults.set(headerSortID?.uuidString ?? "", forKey: FlowHeaderColumn.sortKey)
        defaults.set(sortAscending, forKey: FlowHeaderColumn.directionKey)
    }

    private func profileSnapshotData() throws -> Data? {
        if let captureProfiles {
            return try CaptureProfileStore.encodedSnapshot(profiles: captureProfiles, active: activeCaptureProfileID)
        }
        guard activeCaptureProfileID == nil else { throw CocoaError(.validationMissingMandatoryProperty) }
        if let focusSets {
            let migrated = try CaptureProfileStore.migratedProfiles(from: focusSets)
            return try CaptureProfileStore.encodedSnapshot(profiles: migrated, active: nil)
        }
        return nil
    }

}
