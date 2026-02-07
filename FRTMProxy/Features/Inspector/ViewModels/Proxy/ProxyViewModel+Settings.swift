import Combine
import Foundation

extension ProxyViewModel {
    func bind(settings: SettingsStore) {
        settingsCancellables.removeAll()

        settings.$defaultPort
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPort in
                guard let self else { return }
                self.defaultPort = newPort
                if !self.isRunning {
                    self.activePort = newPort
                }
                self.updateMacOSProxyOverridePort()
            }
            .store(in: &settingsCancellables)

        settings.$autoClearOnStart
            .receive(on: DispatchQueue.main)
            .sink { [weak self] flag in
                self?.autoClearOnStart = flag
            }
            .store(in: &settingsCancellables)

        settings.$autoStartProxy
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] autoStart in
                guard let self else { return }
                if autoStart && !self.isRunning {
                    Task { @MainActor in
                        await self.startProxy()
                    }
                }
            }
            .store(in: &settingsCancellables)

        settings.$restrictInterceptionToActivePinnedHosts
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] flag in
                self?.restrictInterceptionToHosts = flag
                self?.handleInterceptionConfigChanged()
            }
            .store(in: &settingsCancellables)

        settings.$pinnedHosts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pinnedHosts in
                self?.interceptionHosts = pinnedHosts.filter(\.isActive).map(\.host)
                self?.handleInterceptionConfigChanged()
            }
            .store(in: &settingsCancellables)

        settings.$selectedTrafficProfileID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profileID in
                guard let self else { return }
                let profile = TrafficProfileLibrary.profile(with: profileID)
                self.setTrafficProfile(profile)
            }
            .store(in: &settingsCancellables)

        settings.$overrideMacOSProxy
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                self.overrideMacOSProxy = isEnabled
                self.syncMacOSProxyOverride()
            }
            .store(in: &settingsCancellables)

        settings.$alertsEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                self.alertsEnabled = isEnabled
                if isEnabled {
                    self.seenAlertFlowIDs = Set(self.flows.filter { $0.response != nil }.map(\.id))
                    self.triggeredAlertKeys.removeAll()
                } else {
                    self.seenAlertFlowIDs.removeAll()
                    self.triggeredAlertKeys.removeAll()
                }
            }
            .store(in: &settingsCancellables)

        settings.$alertRules
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rules in
                guard let self else { return }
                self.applyAlertRules(rules)
            }
            .store(in: &settingsCancellables)

        defaultPort = settings.defaultPort
        autoClearOnStart = settings.autoClearOnStart
        restrictInterceptionToHosts = settings.restrictInterceptionToActivePinnedHosts
        interceptionHosts = settings.pinnedHosts.filter(\.isActive).map(\.host)
        setTrafficProfile(settings.activeTrafficProfile, force: true)
        overrideMacOSProxy = settings.overrideMacOSProxy
        alertsEnabled = settings.alertsEnabled
        applyAlertRules(settings.alertRules)
        if overrideMacOSProxy {
            applyMacOSProxyOverride(port: activePort)
        }

        if settings.autoStartProxy && !isRunning {
            Task { @MainActor in
                await self.startProxy()
            }
        }
    }

    func handleInterceptionConfigChanged() {
        let configHash = restrictInterceptionToHosts.hashValue ^ interceptionHosts.joined(separator: ",").hashValue
        guard configHash != lastInterceptionConfigHash else { return }
        lastInterceptionConfigHash = configHash
        guard isRunning else { return }
        logText.append("\n[PROXY] Domain filter changed. Restart the proxy to apply.")
    }

    func syncMacOSProxyOverride() {
        if overrideMacOSProxy {
            applyMacOSProxyOverride(port: activePort)
        } else {
            clearMacOSProxyOverride()
        }
    }

    func updateMacOSProxyOverridePort() {
        guard overrideMacOSProxy else { return }
        applyMacOSProxyOverride(port: activePort)
    }

    func applyMacOSProxyOverride(port: Int) {
        Task { @MainActor [weak self] in
            do {
                try await MacOSProxyOverrideManager.shared.enableProxy(host: "localhost", port: port)
            } catch {
                self?.appendLog("\n[SYSTEM] \(error.localizedDescription)")
            }
        }
    }

    func clearMacOSProxyOverride() {
        Task { @MainActor [weak self] in
            do {
                try await MacOSProxyOverrideManager.shared.disableProxy()
            } catch {
                self?.appendLog("\n[SYSTEM] \(error.localizedDescription)")
            }
        }
    }

    func setTrafficProfile(_ profile: TrafficProfile, force: Bool = false) {
        if !force && profile == activeTrafficProfile {
            return
        }
        activeTrafficProfile = profile
        if isRunning {
            let service = service
            Task { @MainActor in
                service.applyTrafficProfile(profile)
            }
        }
    }
}
