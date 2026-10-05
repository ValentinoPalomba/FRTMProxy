import Foundation

extension ProxyViewModel {

    // MARK: - Persistence

    func loadPersistedScripts() {
        scripts = scriptStore.load()
    }

    func persistScripts() {
        scriptStore.save(scripts)
        syncUnifiedTrafficRules()
    }

}
