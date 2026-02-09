import Foundation

struct DomainApprovalStatus: Codable, Equatable {
    enum Status: String, Codable {
        case pending
        case approved
        case rejected
    }
    
    let domain: String
    let status: Status
    let approvalDate: Date?
    let rejectionDate: Date?
    
    init(domain: String, status: Status, approvalDate: Date? = nil, rejectionDate: Date? = nil) {
        self.domain = domain
        self.status = status
        self.approvalDate = approvalDate
        self.rejectionDate = rejectionDate
    }
}

@MainActor
final class DomainApprovalStore: ObservableObject {
    @Published var approvedDomains: Set<String> = []
    @Published var pendingDomains: [String: DomainApprovalStatus] = [:]
    
    private let fileManager = FileManager.default
    private let fileName = "mitm_domains.json"
    private var storePath: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = appSupport.appendingPathComponent("FRTMProxy", isDirectory: true)
        return appFolder.appendingPathComponent(fileName)
    }
    
    init() {
        ensureStorageDirectory()
        loadFromDisk()
    }
    
    private func ensureStorageDirectory() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = appSupport.appendingPathComponent("FRTMProxy", isDirectory: true)
        
        if !fileManager.fileExists(atPath: appFolder.path) {
            try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }
    }
    
    private func loadFromDisk() {
        guard fileManager.fileExists(atPath: storePath.path) else {
            print("[DomainApprovalStore] No JSON file found at: \(storePath.path)")
            return
        }
        
        print("[DomainApprovalStore] Loading from: \(storePath.path)")
        do {
            let data = try Data(contentsOf: storePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let statuses = try decoder.decode([DomainApprovalStatus].self, from: data)
            
            approvedDomains = Set(statuses.filter { $0.status == .approved }.map { $0.domain })
            pendingDomains = Dictionary(statuses.filter { $0.status == .pending }.map { ($0.domain, $0) }) { _, new in new }
            print("[DomainApprovalStore] Loaded approved: \(approvedDomains), pending: \(pendingDomains.keys)")
        } catch {
            print("[DomainApprovalStore] Error loading domain approvals: \(error)")
        }
    }
    
    private func saveToDisk() {
        var allStatuses: [DomainApprovalStatus] = []
        
        // Approved domains
        allStatuses.append(contentsOf: approvedDomains.map { domain in
            DomainApprovalStatus(domain: domain, status: .approved, approvalDate: Date())
        })
        
        // Pending domains
        allStatuses.append(contentsOf: pendingDomains.values)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(allStatuses)
            try data.write(to: storePath, options: .atomic)
        } catch {
            print("Error saving domain approvals: \(error)")
        }
    }
    
    func approveDomain(_ domain: String) {
        print("[DomainApprovalStore] Approving domain: \(domain)")
        approvedDomains.insert(domain)
        print("[DomainApprovalStore] approvedDomains after insert: \(approvedDomains)")
        pendingDomains.removeValue(forKey: domain)
        saveToDisk()
        print("[DomainApprovalStore] Saved to disk. Current approved: \(approvedDomains)")
    }
    
    func rejectDomain(_ domain: String) {
        pendingDomains.removeValue(forKey: domain)
        saveToDisk()
    }
    
    func markPending(_ domain: String) {
        let status = DomainApprovalStatus(domain: domain, status: .pending)
        pendingDomains[domain] = status
        saveToDisk()
    }
    
    func isApproved(_ domain: String) -> Bool {
        return approvedDomains.contains(domain)
    }
    
    func isPending(_ domain: String) -> Bool {
        return pendingDomains[domain] != nil
    }
    
    func getDomainStatus(_ domain: String) -> DomainApprovalStatus.Status {
        if approvedDomains.contains(domain) {
            return .approved
        } else if pendingDomains[domain] != nil {
            return .pending
        }
        return .pending
    }
}
