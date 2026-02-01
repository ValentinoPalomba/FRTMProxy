import Foundation

extension ProxyViewModel {
    func loadPersistedRules() {
        let stored = ruleStore.loadRules()
        stored.forEach { rule in
            rules[rule.key] = rule
        }
    }

    func loadPersistedCollections() {
        collections = collectionStore.loadCollections()
    }

    func loadPersistedGitSources() {
        gitCollectionSources = collectionStore.loadGitSources()
    }

    func loadPersistedBreakpoints() {
        let stored = breakpointStore.loadBreakpoints()
        stored.forEach { rule in
            breakpointRules[rule.key] = rule
        }
    }

    func persistRules() {
        let array = rules.values.sorted(by: { $0.key < $1.key })
        ruleStore.save(rules: array)
    }

    func persistCollections() {
        collectionStore.save(collections: collections)
    }

    func persistGitSources() {
        collectionStore.saveGitSources(gitCollectionSources)
    }

    func persistBreakpoints() {
        let array = breakpointRules.values.sorted(by: { $0.key < $1.key })
        breakpointStore.save(breakpoints: array)
    }
}
