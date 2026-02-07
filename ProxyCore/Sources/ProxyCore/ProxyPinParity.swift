import Foundation

/// Convenience helpers for running ProxyCore with ProxyPin-style config files under a single base directory.
public enum ProxyPinParity {
    /// Loads ProxyPin-style config files from `baseDirectory` and returns a ready-to-install interceptor chain.
    ///
    /// Files (if present):
    /// - `hosts.json`
    /// - `request_map.json` + `request_map/*.json`
    /// - `request_rewrite.json` + `rewrite/*.json`
    /// - `script.json` + `scripts/*.js`
    /// - `request_block.json`
    /// - `report_servers.json`
    public static func loadInterceptors(
        baseDirectory: URL,
        scriptEnvironment: ScriptEnvironment = ScriptEnvironment(),
        logger: @escaping JavaScriptEngine.Logger = { _ in }
    ) async throws -> [any ProxyInterceptor] {
        let hostsStore = HostsStore(baseDirectory: baseDirectory)
        try await hostsStore.loadIfPresent()

        let mapStore = RequestMapStore(baseDirectory: baseDirectory)
        try await mapStore.loadIfPresent()

        let rewriteStore = RequestRewriteStore(baseDirectory: baseDirectory)
        try await rewriteStore.loadIfPresent()

        let scriptStore = ScriptStore(baseDirectory: baseDirectory, environment: scriptEnvironment)
        try await scriptStore.loadIfPresent()

        let blockStore = RequestBlockStore(baseDirectory: baseDirectory)
        try await blockStore.loadIfPresent()

        let reportStore = ReportServerStore(baseDirectory: baseDirectory)
        try await reportStore.loadIfPresent()

        // Shared JS runtime to keep session/cache behavior closer to ProxyPin.
        let jsEngine = JavaScriptEngine(baseDirectory: baseDirectory, logger: logger)

        return [
            HostsInterceptor(store: hostsStore),
            RequestMapInterceptor(store: mapStore, baseDirectory: baseDirectory, engine: jsEngine),
            RequestRewriteInterceptor(store: rewriteStore, baseDirectory: baseDirectory),
            ScriptInterceptor(store: scriptStore, engine: jsEngine),
            RequestBlockInterceptor(store: blockStore),
            ReportServerInterceptor(store: reportStore, logger: logger),
        ]
    }
}

