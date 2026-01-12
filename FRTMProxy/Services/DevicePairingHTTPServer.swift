import Foundation
import Network

final class DevicePairingHTTPServer {
    struct RuntimeInfo: Sendable {
        var landingURL: URL
        var ipAddress: String
        var wifiSSID: String?
    }

    enum ServerError: LocalizedError {
        case noNetworkAddress
        case failedToStart(String)

        var errorDescription: String? {
            switch self {
            case .noNetworkAddress:
                return "Impossibile determinare l'indirizzo IP locale (Wi‑Fi)."
            case .failedToStart(let reason):
                return "Impossibile avviare il server di pairing: \(reason)"
            }
        }
    }

    private let queue = DispatchQueue(label: "io.frtmproxy.devicepairing.http", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var listener: NWListener?
    private var proxyPort: Int = 8080
    private var rootCADER: Data = Data()
    private var wifiSSID: String?

    var onStarted: (@Sendable (RuntimeInfo) -> Void)?
    var onStopped: (@Sendable () -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    init() {
        queue.setSpecific(key: queueKey, value: 1)
    }

    func updateConfig(proxyPort: Int, rootCADER: Data, wifiSSID: String?) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            self.proxyPort = proxyPort
            self.rootCADER = rootCADER
            self.wifiSSID = wifiSSID
        } else {
            queue.sync { [weak self] in
                self?.proxyPort = proxyPort
                self?.rootCADER = rootCADER
                self?.wifiSSID = wifiSSID
            }
        }
    }

    func start() {
        stop()

        guard let ipAddress = LocalNetworkInfo.primaryIPv4Address() else {
            onError?(ServerError.noNetworkAddress)
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        self.onError?(ServerError.failedToStart("port non disponibile"))
                        return
                    }
                    let url = URL(string: "http://\(ipAddress):\(port.rawValue)/")!
                    let info = RuntimeInfo(landingURL: url, ipAddress: ipAddress, wifiSSID: LocalNetworkInfo.currentWiFiSSID())
                    self.onStarted?(info)
                case .failed(let error):
                    self.onError?(ServerError.failedToStart(error.localizedDescription))
                    self.stop()
                case .cancelled:
                    self.onStopped?()
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection, ipAddress: ipAddress)
            }

            listener.start(queue: queue)
        } catch {
            onError?(ServerError.failedToStart(error.localizedDescription))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection, ipAddress: String) {
        connection.start(queue: queue)
        receiveRequest(connection: connection) { [weak self] requestLine, request in
            guard let self else { return }

            if requestLine.isEmpty {
                self.sendNotFound(connection: connection)
                return
            }

            switch request.path {
            case "/":
                self.sendLandingPage(connection: connection, ipAddress: ipAddress)
            case "/frtmproxy.mobileconfig":
                self.sendMobileConfig(connection: connection, ipAddress: ipAddress, query: request.query)
            default:
                self.sendNotFound(connection: connection)
            }
        }
    }

    private struct HTTPRequest {
        var path: String
        var query: [String: String]
    }

    private func receiveRequest(connection: NWConnection, completion: @escaping (String, HTTPRequest) -> Void) {
        var buffer = Data()

        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let error {
                    self.onError?(error)
                    connection.cancel()
                    return
                }
                if let data, !data.isEmpty {
                    buffer.append(data)
                    if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                        completion(self.parseRequestLine(buffer), self.parseRequest(buffer))
                        return
                    }
                }
                if isComplete {
                    completion("", HTTPRequest(path: "", query: [:]))
                    return
                }
                readMore()
            }
        }

        readMore()
    }

    private func parseRequestLine(_ data: Data) -> String {
        guard let string = String(data: data, encoding: .utf8) else { return "" }
        return string.components(separatedBy: "\r\n").first ?? ""
    }

    private func parseRequest(_ data: Data) -> HTTPRequest {
        let parts = parseRequestLine(data).split(separator: " ")
        guard parts.count >= 2 else { return HTTPRequest(path: "", query: [:]) }
        let target = String(parts[1])

        guard var components = URLComponents(string: target) else {
            return HTTPRequest(path: target.split(separator: "?").first.map(String.init) ?? target, query: [:])
        }
        if components.scheme == nil {
            components.scheme = "http"
        }
        if components.host == nil {
            components.host = "localhost"
        }

        let path = components.path.isEmpty ? "/" : components.path
        var query: [String: String] = [:]
        components.queryItems?.forEach { item in
            if let value = item.value {
                query[item.name] = value
            }
        }
        return HTTPRequest(path: path, query: query)
    }

    private func sendLandingPage(connection: NWConnection, ipAddress: String) {
        let ssid = wifiSSID ?? LocalNetworkInfo.currentWiFiSSID()
        let profileURL = "/frtmproxy.mobileconfig" + (ssid.map { ssidQuery($0) } ?? "")
        let instructions = landingPageHTML(
            ipAddress: ipAddress,
            ssid: ssid,
            profileURL: profileURL,
            proxyPort: proxyPort
        )
        sendResponse(
            connection: connection,
            status: "200 OK",
            headers: ["Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store"],
            body: Data(instructions.utf8)
        )
    }

    private func sendMobileConfig(connection: NWConnection, ipAddress: String, query: [String: String]) {
        let requestedSSID = (query["ssid"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSSID = (requestedSSID.isEmpty ? (wifiSSID ?? LocalNetworkInfo.currentWiFiSSID()) : requestedSSID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let resolvedSSID, !resolvedSSID.isEmpty else {
            sendResponse(
                connection: connection,
                status: "400 Bad Request",
                headers: ["Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store"],
                body: Data("SSID Wi‑Fi mancante: apri la pagina principale e riprova.".utf8)
            )
            return
        }

        let builder = MobileConfigBuilder()
        let payload = MobileConfigBuilder.Payload(
            displayName: "FRTMProxy (Proxy + CA)",
            organization: "FRTMProxy",
            wifiSSID: resolvedSSID,
            proxyHost: ipAddress,
            proxyPort: proxyPort,
            rootCADER: rootCADER
        )

        do {
            let data = try builder.build(payload)
            sendResponse(
                connection: connection,
                status: "200 OK",
                headers: [
                    "Content-Type": "application/x-apple-aspen-config",
                    "Content-Disposition": "attachment; filename=\"FRTMProxy.mobileconfig\"",
                    "Cache-Control": "no-store"
                ],
                body: data
            )
        } catch {
            sendResponse(
                connection: connection,
                status: "500 Internal Server Error",
                headers: ["Content-Type": "text/plain; charset=utf-8"],
                body: Data(error.localizedDescription.utf8)
            )
        }
    }

    private func sendNotFound(connection: NWConnection) {
        sendResponse(
            connection: connection,
            status: "404 Not Found",
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data("Not Found".utf8)
        )
    }

    private func sendResponse(connection: NWConnection, status: String, headers: [String: String], body: Data) {
        var head = "HTTP/1.1 \(status)\r\n"
        var mergedHeaders = headers
        mergedHeaders["Content-Length"] = "\(body.count)"
        mergedHeaders["Connection"] = "close"
        for (key, value) in mergedHeaders {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"

        let headData = Data(head.utf8)
        connection.send(content: headData + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func ssidQuery(_ ssid: String) -> String {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "ssid", value: ssid)]
        return components.percentEncodedQuery.map { "?\($0)" } ?? ""
    }

    private func landingPageHTML(ipAddress: String, ssid: String?, profileURL: String, proxyPort: Int) -> String {
        let trimmedSSID = ssid?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeSSID = htmlEscape((trimmedSSID?.isEmpty == false ? trimmedSSID : "—") ?? "—")
        let safeIP = htmlEscape(ipAddress)
        let safeProfileURL = htmlEscape(profileURL)
        let proxyDescription = htmlEscape("\(ipAddress):\(proxyPort)")
        return """
        <!DOCTYPE html>
        <html lang="it">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>FRTMProxy — Device setup</title>
          <style>
            :root {
              color-scheme: light dark;
              /* Based on Xcode Light Theme */
              --bg: #F5F5F7;
              --surface: #FFFFFF;
              --surface-elevated: #ECEEF3;
              --text: #131417;
              --text-muted: #5E5E65;
              --accent: #0A84FF;
              --border: #D2D2D7;
              --shadow: rgba(0, 0, 0, 0.07);
            }
            @media (prefers-color-scheme: dark) {
              :root {
                /* Based on Xcode Dark Theme */
                --bg: #1C1C1E;
                --surface: #1F1F23;
                --surface-elevated: #2C2C3A;
                --text: #F2F2F7;
                --text-muted: #8E8E93;
                --accent: #0A84FF;
                --border: #32323C;
                --shadow: rgba(0, 0, 0, 0.25);
              }
            }
            *, *::before, *::after { box-sizing: border-box; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", system-ui, sans-serif;
              background: var(--bg);
              color: var(--text);
              margin: 0;
              min-height: 100dvh;
              -webkit-font-smoothing: antialiased;
            }
            .page {
              max-width: 560px;
              margin: 0 auto;
              padding: 28px 18px 48px;
              display: flex;
              flex-direction: column;
              gap: 22px;
            }
            .hero {
              display: flex;
              flex-direction: column;
              gap: 8px;
            }
            .eyebrow {
              text-transform: uppercase;
              letter-spacing: 0.1em;
              font-size: 11px;
              font-weight: 600;
              color: var(--accent);
            }
            h1 {
              font-size: 28px;
              letter-spacing: -0.01em;
              margin: 0;
            }
            p {
              margin: 0;
              line-height: 1.5;
              color: var(--text-muted);
            }
            .card {
              background: var(--surface);
              border: 1px solid var(--border);
              border-radius: 22px;
              padding: 20px;
              box-shadow: 0 10px 30px var(--shadow);
            }
            .profile-card {
              display: flex;
              flex-direction: column;
              gap: 16px;
            }
            .badge {
              display: inline-flex;
              align-items: center;
              gap: 8px;
              padding: 8px 12px;
              border-radius: 999px;
              background: var(--surface-elevated);
              border: 1px solid var(--border);
              font-size: 13px;
            }
            .badge strong {
              color: var(--text);
              font-weight: 600;
            }
            .stats {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
              gap: 12px;
            }
            .stat {
              background: var(--surface-elevated);
              border-radius: 14px;
              border: 1px solid var(--border);
              padding: 12px;
            }
            .stat .label {
              font-size: 12px;
              color: var(--text-muted);
              margin-bottom: 4px;
            }
            .stat .value {
              font-size: 16px;
              font-weight: 600;
              font-family: -apple-system-ui-monospaced, "SF Mono", "Menlo", monospace;
              color: var(--text);
            }
            .primary {
              display: inline-flex;
              justify-content: center;
              align-items: center;
              padding: 14px 18px;
              border-radius: 14px;
              border: none;
              font-weight: 600;
              font-size: 15px;
              text-decoration: none;
              color: white;
              background: var(--accent);
              box-shadow: 0 8px 24px -4px var(--accent);
              transition: transform 0.15s ease-out, box-shadow 0.15s ease-out;
            }
            .primary:active {
              transform: translateY(1px) scale(0.99);
              box-shadow: 0 4px 12px -2px var(--accent);
            }
            .steps {
              list-style: none;
              padding: 0;
              margin: 0;
              display: flex;
              flex-direction: column;
              gap: 16px;
            }
            .steps li {
              display: flex;
              gap: 12px;
            }
            .step-index {
              flex-shrink: 0;
              width: 32px;
              height: 32px;
              border-radius: 12px;
              background: var(--surface-elevated);
              border: 1px solid var(--border);
              font-weight: 600;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              color: var(--accent);
            }
            .step-body strong {
              color: var(--text);
            }
            .note {
              font-size: 13px;
              color: var(--text-muted);
              margin-top: 4px;
            }
          </style>
        </head>
        <body>
          <div class="page">
            <header class="hero">
              <div class="eyebrow">FRTMProxy</div>
              <h1>Device setup</h1>
              <p>Scarica e installa il profilo combinato per questa rete Wi‑Fi.</p>
            </header>

            <section class="card profile-card">
              <div class="badge">Wi‑Fi attuale: <strong>\(safeSSID)</strong></div>
              <div class="stats">
                <div class="stat">
                  <p class="label">Proxy</p>
                  <p class="value">\(proxyDescription)</p>
                </div>
                <div class="stat">
                  <p class="label">IP del Mac</p>
                  <p class="value">\(safeIP)</p>
                </div>
              </div>
              <a class="primary" href="\(safeProfileURL)">Scarica profilo</a>
              <p class="note">Dopo il download apri Impostazioni → Profilo scaricato per completare l’installazione.</p>
              <p class="note">Il profilo configura il proxy solo per la rete indicata: se cambi Wi‑Fi rigenera il QR.</p>
            </section>

            <section class="card">
              <h2 style="margin-top:0; font-size:18px;">Come installare</h2>
              <ol class="steps">
                <li>
                  <span class="step-index">1</span>
                  <div class="step-body">
                    <strong>Scarica il profilo.</strong>
                    <p>Tocca “Scarica profilo” e conferma nel browser del dispositivo.</p>
                  </div>
                </li>
                <li>
                  <span class="step-index">2</span>
                  <div class="step-body">
                    <strong>Installa da Impostazioni.</strong>
                    <p>Vai in Impostazioni → Profilo scaricato e completa l’installazione del proxy + CA.</p>
                  </div>
                </li>
                <li>
                  <span class="step-index">3</span>
                  <div class="step-body">
                    <strong>Attiva la fiducia della CA.</strong>
                    <p>Impostazioni → Generali → Info → Impostazioni certificati → abilita la CA mitmproxy.</p>
                  </div>
                </li>
              </ol>
            </section>
          </div>
        </body>
        </html>
        """
    }

    private func htmlEscape(_ value: String) -> String {
        var escaped = value
        let replacements: [(String, String)] = [
            ("&", "&amp;"),
            ("<", "&lt;"),
            (">", "&gt;"),
            ("\"", "&quot;"),
            ("'", "&#39;")
        ]
        replacements.forEach { escaped = escaped.replacingOccurrences(of: $0.0, with: $0.1) }
        return escaped
    }
}
