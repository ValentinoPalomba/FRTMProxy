import Combine
import Foundation

@MainActor
final class CaptureProfileStore: ObservableObject {
    nonisolated static let dataKey = "inspector.captureProfiles"
    @Published private(set) var profiles: [CaptureProfile] = []
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var errorMessage: String?
    var activeProfile: CaptureProfile? { profiles.first { $0.id == activeProfileID } }

    var canEdit: Bool { !preservesUnreadableData }

    private let defaults: UserDefaults
    private var preservesUnreadableData = false

    struct Snapshot: Codable, Equatable, Sendable {
        var profiles: [CaptureProfile]
        var activeProfileID: UUID?
    }

    enum Failure: LocalizedError {
        case invalidName, duplicateName, missingProfile, invalidMember, capacity, unreadable
        var errorDescription: String? {
            switch self {
            case .invalidName: return String(localized: "Enter a profile name of at most 128 UTF-8 bytes.", bundle: AppLocalization.bundle)
            case .duplicateName: return String(localized: "A profile with this name already exists.", bundle: AppLocalization.bundle)
            case .missingProfile: return String(localized: "The capture profile no longer exists.", bundle: AppLocalization.bundle)
            case .invalidMember: return String(localized: "Choose a valid request, host, or app.", bundle: AppLocalization.bundle)
            case .capacity: return String(localized: "Capture profiles exceed the storage limit (50 profiles, 128 members per profile, 256 KiB).", bundle: AppLocalization.bundle)
            case .unreadable: return String(localized: "Saved capture profiles could not be read. Existing data has been preserved.", bundle: AppLocalization.bundle)
            }
        }
    }

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? Self.defaultPreferences()
        self.defaults = defaults
        reload()
    }

    var preferences: UserDefaults { defaults }

    func reload() {
        preservesUnreadableData = false
        errorMessage = nil
        do {
            if let existing = defaults.object(forKey: Self.dataKey) {
                guard let data = existing as? Data, data.count <= 256 * 1024 else { throw Failure.unreadable }
                let snapshot = try Self.decodedSnapshot(data)
                profiles = snapshot.profiles
                activeProfileID = snapshot.activeProfileID
            } else if let legacy = defaults.object(forKey: SavedFocusSet.dataKey) {
                guard let data = legacy as? Data else { throw Failure.unreadable }
                let migrated = try Self.migratedProfiles(from: SavedFocusSet.decode(data))
                try persist(migrated, active: nil)
            } else {
                profiles = []
                activeProfileID = nil
            }
        } catch {
            profiles = []
            activeProfileID = nil
            preservesUnreadableData = true
            errorMessage = Failure.unreadable.localizedDescription
        }
    }

    private static func defaultPreferences() -> UserDefaults {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["FRTM_UI_TEST_STORAGE"] {
            let suite = "FRTMProxy.CaptureProfiles.Fixture." + URL(fileURLWithPath: path).lastPathComponent
            return UserDefaults(suiteName: suite) ?? .standard
        }
        #endif
        return .standard
    }

    func selectProfile(_ id: UUID?) {
        do { try persist(profiles, active: id) }
        catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func createProfile(name: String, member: CaptureProfileMember? = nil) throws -> CaptureProfile {
        let profile = CaptureProfile(name: name, members: member.map { [$0] } ?? [])
        try persist(profiles + [profile], active: activeProfileID)
        return profiles.first { $0.id == profile.id } ?? profile
    }

    func add(member: CaptureProfileMember, to id: UUID) throws {
        try update(id) { $0.members.append(member) }
    }

    func removeProfile(_ id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else { throw Failure.missingProfile }
        try persist(profiles.filter { $0.id != id }, active: activeProfileID == id ? nil : activeProfileID)
    }

    func removeMember(_ member: CaptureProfileMember, from id: UUID) throws {
        guard let normalized = member.normalized else { throw Failure.invalidMember }
        try update(id) { $0.members.removeAll { $0.normalized == normalized } }
    }

    func renameProfile(_ id: UUID, name: String) throws {
        try update(id) { $0.name = name }
    }

    private func update(_ id: UUID, mutation: (inout CaptureProfile) -> Void) throws {
        var updated = profiles
        guard let index = updated.firstIndex(where: { $0.id == id }) else { throw Failure.missingProfile }
        mutation(&updated[index])
        try persist(updated, active: activeProfileID)
    }

    nonisolated static func migratedProfiles(from scopes: [SavedFocusSet]) throws -> [CaptureProfile] {
        try SavedFocusSet.validate(scopes)
        var names = Set<String>()
        return scopes.map { scope in
            let base = scope.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var name = base
            var suffix = 2
            while names.contains(name.lowercased()) {
                let ending = " (\(suffix))"
                var prefix = base
                while prefix.utf8.count + ending.utf8.count > 128 { prefix.removeLast() }
                name = prefix + ending
                suffix += 1
            }
            names.insert(name.lowercased())
            return CaptureProfile(id: scope.id, name: name, legacyFilter: scope.filter)
        }
    }

    nonisolated static func encodedSnapshot(profiles: [CaptureProfile], active: UUID?) throws -> Data {
        let validated = try Self.validated(profiles)
        guard active == nil || validated.contains(where: { $0.id == active }) else { throw Failure.missingProfile }
        let data = try JSONEncoder().encode(Snapshot(profiles: validated, activeProfileID: active))
        guard data.count <= 256 * 1024 else { throw Failure.capacity }
        return data
    }

    nonisolated static func decodedSnapshot(_ data: Data) throws -> Snapshot {
        guard data.count <= 256 * 1024 else { throw Failure.capacity }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        let validated = try Self.validated(snapshot.profiles)
        guard snapshot.activeProfileID == nil || validated.contains(where: { $0.id == snapshot.activeProfileID }) else {
            throw Failure.missingProfile
        }
        return Snapshot(profiles: validated, activeProfileID: snapshot.activeProfileID)
    }

    private func persist(_ proposed: [CaptureProfile], active: UUID?) throws {
        do { try commit(proposed, active: active) }
        catch { errorMessage = error.localizedDescription; throw error }
    }

    private func commit(_ proposed: [CaptureProfile], active: UUID?) throws {
        guard !preservesUnreadableData else { throw Failure.unreadable }
        let data = try Self.encodedSnapshot(profiles: proposed, active: active)
        let snapshot = try Self.decodedSnapshot(data)
        defaults.set(data, forKey: Self.dataKey)
        profiles = snapshot.profiles
        activeProfileID = active
        errorMessage = nil
    }

    nonisolated private static func validated(_ proposed: [CaptureProfile]) throws -> [CaptureProfile] {
        guard proposed.count <= 50, Set(proposed.map(\.id)).count == proposed.count else { throw Failure.capacity }
        var names = Set<String>()
        return try proposed.map { profile in
            var profile = profile
            profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !profile.name.isEmpty, profile.name.utf8.count <= 128 else { throw Failure.invalidName }
            guard names.insert(profile.name.lowercased()).inserted else { throw Failure.duplicateName }
            var seen = Set<CaptureProfileMember>()
            profile.members = try profile.members.compactMap { member in
                guard let member = member.normalized, member.displayName.utf8.count <= 4096 else { throw Failure.invalidMember }
                return seen.insert(member).inserted ? member : nil
            }
            guard profile.members.count <= 128 else { throw Failure.capacity }
            if let filter = profile.legacyFilter {
                try SavedFocusSet.validate([SavedFocusSet(id: profile.id, name: profile.name, filter: filter)])
            }
            return profile
        }
    }
}
