# FRTMProxy

FRTMProxy is a macOS app built with SwiftUI to sniff, inspect, and debug HTTP/S traffic in real time with a strong focus on user experience. Inside you’ll find a ready-to-use MITM proxy, a fast inspector, and an editor to map local responses in just a few clicks.

> **Note**: The application is not meant for production execution, but as an internal tool for API debugging.

---

## Highlights

- **Dual-pane inspector** – Requests and responses side by side, copied in one go with dedicated shortcuts (URL, cURL, body, map local).
- **Power-user flow explorer** – Spreadsheet-style custom table with text filters, quick mapped/error chips, and color-coded method/status badges.
- **Optional domain filtering** – When enabled, the proxy intercepts only pinned hosts (and leaves the rest tunneled) to reduce interference with other apps.
- **CodeMirror editor** – Raw / Pretty / Hex views with syntax highlighting, line numbers, and read-only mode synced with the selected flow.
- **Map Local Studio** – Request/response editor with key-value fields for headers and query params, sync status, and Save/Close actions.
- **Integrated proxy service** – Mitmproxy backend orchestrated via `MitmproxyService` and `ProxyViewModel`, with Combine bindings for every UI state.

---

## Architecture at a Glance

| Layer | Description |
| --- | --- |
| `App/` | Entry point (`FRTMProxyApp`, `AppRootView`) and `AppDelegate` setup. |
| `ViewModels/` | ObservableObjects orchestrating proxy, inspector, and map editor (`ProxyViewModel`, `MapEditorViewModel`). |
| `Inspector/` | All SwiftUI inspector views: flow list, split request/response panel, map editor, header bar, etc. |
| `Components/` | Reusable building blocks (FlowTableView, CodeEditorView powered by CodeMirror, ControlButton, SurfaceCard…). |
| `Models/` | Shared models (`MitmFlow`, `MapRule`) plus helper extensions. |
| `Services/` | `MitmproxyService` + `ProxyServiceProtocol` to communicate with the Python/mitmproxy backend. |
| `Utils/` | Misc helpers (formatter, clipboard, networking config). |

Each macro section is designed to be easily swappable or testable and follows clear naming to avoid spaghetti code.

---

## Requirements

- macOS 14.0+
- Xcode 15.1+
- Swift 5.9
- Python 3 + mitmproxy (for the CLI backend, already managed by `MitmproxyService`)

---

## Getting Started

```bash
git clone https://github.com/<org>/FRTMProxy.git
cd FRTMProxy
open FRTMProxy.xcodeproj
```

1. Select the **FRTMProxy** scheme and build (`⌘B`).
2. Open macOS network preferences and point the HTTP/HTTPS proxy to `127.0.0.1` port `8080`.
3. Launch FRTMProxy and press **Start** to spin up the internal proxy.
4. Launch the iOS Simulator (or a real device on the same Wi-Fi).
5. Download and install the certificate for iOS, then trust it from Settings > General > About > Certificate Trust Settings.
6. Go back to the simulator and start browsing: you’ll see flows appear in real time inside FRTMProxy.

### Physical Device via QR (no manual Wi‑Fi proxy configuration)

1. Launch FRTMProxy and press **Start**.
2. Open **Manage → Device**.
3. Scan the QR code from your device (same Wi-Fi network) and install the downloaded profile (the proxy is configured automatically for the current Wi-Fi network).
4. Enable CA trust: Settings → General → About → Certificate Trust Settings.
5. If the SSID is not detected on macOS 15.3+, enable location permissions for FRTMProxy (System Settings → Privacy & Security → Location Services).
   - Optional (macOS 15.3+): also enable the `com.apple.developer.networking.wifi-info` entitlement (“Access Wi‑Fi Information”). In the project you’ll find `FRTMProxy/FRTMProxy.wifi-info.entitlements` to use instead of `FRTMProxy/FRTMProxy.entitlements` when signing with a development certificate.

### iOS Simulator (guided CA install)

Open **Manage → Device** and use the **iOS Simulator** section to:
- verify booted simulators
- install the mitmproxy CA via `simctl`

---

## Quick Commands in the UI

- `Clear`: resets the flow list.
- `Rules`: opens the rules manager to enable/disable saved map-local entries.
- `Start / Stop`: control the underlying mitmproxy process.
- Search: supports keywords and filters `host:`, `method:`, `status:` (e.g. `2xx`, `>=400`), `type:` (content type, e.g. `json`) and `device:` (client IP). Use `-` to exclude (e.g. `-type:image`).
- Flow table: clicking a row opens the inspector panel; double-click copies the URL.
- Inspector: `URL`, `cURL`, `Body`, `Map Local` buttons give access to the main shortcuts.
- Map Editor: `Save` stores the fake response, `Close` dismisses the panel while keeping local state.

---

## UI Preview

![FRTMProxy Light UI](.github/Screenshot%202026-01-12%20alle%2016.29.04.png)

![FRTMProxy Dark UI](.github/Screenshot%202026-01-12%20alle%2016.29.15.png)

---

## Core Technologies

- **SwiftUI** for every view (macOS target).
- **Combine** for reactive binding between service and view model.
- **CodeMirror-Swift** for the colorized JSON editor.
- **mitmproxy** (invoked via a Python bridge) for traffic proxying.

---

## Roadmap / Future Ideas

- WebSocket & gRPC support
- Project saving + flow export
- Theme editor and multi-column layout
- Advanced shortcuts (⌘C for quick raw/pretty copy)

---

## Contributing

1. Fork the repo and create a `feature/name-of-feature` branch.
2. Ensure the UI stays consistent with the existing design system.
3. Open a pull request describing the bug/feature and attach screenshots/GIFs.

If you have any questions, use the issues section or chat directly with the network team.

---

Happy debugging! 🚀
