<div align="center">

<img src=".media/icon.png" alt="FRTMProxy" width="128" height="128" />

# FRTMProxy

**A fast, native macOS app to inspect, mock, and reshape HTTP/S traffic in real time.**
Free forever. Public domain.

[![Latest release](https://img.shields.io/github/v/release/ValentinoPalomba/FRTMProxy?color=5E6AD2&label=release)](https://github.com/ValentinoPalomba/FRTMProxy/releases)
[![Downloads](https://img.shields.io/github/downloads/ValentinoPalomba/FRTMProxy/total?color=5E6AD2)](https://github.com/ValentinoPalomba/FRTMProxy/releases)
[![Platform](https://img.shields.io/badge/macOS-14.1%2B-black)](https://www.apple.com/macos/)
[![License: Unlicense](https://img.shields.io/badge/license-Unlicense-5E6AD2)](LICENSE)
[![Stars](https://img.shields.io/github/stars/ValentinoPalomba/FRTMProxy?style=flat&color=5E6AD2)](https://github.com/ValentinoPalomba/FRTMProxy/stargazers)

[**Website**](https://valentinopalomba.github.io/FRTMProxy/) · [Download](https://github.com/ValentinoPalomba/FRTMProxy/releases) · [Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)

<img src=".media/Inspector_dark.png" alt="FRTMProxy inspector" width="820" />

</div>

---

## Why FRTMProxy

Debugging network traffic on macOS shouldn't cost $89. FRTMProxy gives you the full toolkit —
breakpoints, Map Local, scripting, diffing, WebSocket inspection, device setup — **for free, with no
limits**. It's a native SwiftUI app built on top of the battle-tested [mitmproxy](https://mitmproxy.org)
engine, so TLS interception just works.

### FRTMProxy vs Proxyman

| | **FRTMProxy** | **Proxyman — Free** | **Proxyman — Paid** |
|---|:---:|:---:|:---:|
| **Price** | **Free forever** | Free | from **$89** |
| Debugging / rewrite rules | ✅ Unlimited | ⚠️ 1 rule | ✅ |
| Breakpoints | ✅ | ⚠️ 1 rule | ✅ |
| Map Local | ✅ | ⚠️ 1 rule | ✅ |
| Scripting | ✅ | ⚠️ 1 rule | ✅ |
| Request/response Diff | ✅ | ✅ | ✅ |
| WebSocket inspection | ✅ | ❌ | ✅ |
| iOS & Android setup | ✅ | ✅ | ✅ |
| HAR import / export | ✅ | ❌ | ✅ |
| Native macOS (SwiftUI) | ✅ | ✅ | ✅ |
| Open / public domain | ✅ | ❌ | ❌ |

<sub>Proxyman feature availability and pricing per [proxyman.com/pricing](https://proxyman.com/pricing), as of July 2026. Proxyman is a great, more mature tool — this table is about what you get for free.</sub>

---

## Install

### Homebrew (recommended)

```bash
brew tap ValentinoPalomba/frtmtools
brew install --cask frtmproxy
```

### Direct download

Grab the latest `.zip` from the [Releases](https://github.com/ValentinoPalomba/FRTMProxy/releases)
page. The app is signed with a Developer ID, notarized, and auto-updates via
[Sparkle](https://sparkle-project.org).

---

## What you can do

- **Inspect** requests and responses with a fast, readable inspector.
- **Mock** local responses with no code — perfect for edge cases and isolating from backends.
- **Record & replay** sessions: capture traffic, export to **HAR**, replay recorded responses as mocks.
- **Break** on requests/responses to inspect or edit them on the fly.
- **Connect devices**: guided certificate setup for iOS simulators, physical devices (via QR), and Android.
- **Capture this Mac's traffic** with a one-toggle system proxy override.
- **Shape traffic**: simulate latency, jitter, bandwidth limits, and packet loss.
- **Build rule pipelines**: match traffic once, then mock, redirect, rewrite, block, delay,
  breakpoint, or script it with ordered actions.
- **Return to earlier captures**: encrypted persistent sessions keep a paged timeline with notes
  and bookmarks.
- **Launch selective targets**: route one app, Chromium/Electron profile, or CLI process through
  FRTMProxy without changing the system proxy.
- **Inspect structured protocols**: GraphQL, JWT, cookies, forms, multipart, SSE, XML/HTML, gRPC,
  and generic Protobuf wire payloads.
- **Share a workspace**: import or export versioned, Git-friendly rules, scripts, and breakpoints.
- **Automate locally**: expose redacted flows and atomic rule replacement through a local MCP
  server bound to a user-only Unix socket.

### Key tools

**Rules** — answer specific requests locally. Fast mocks, edge cases, dependency isolation.

**Collections** — record a session, keep it local or push it to a Git repo. Export to HAR, edit,
reuse. Enable a collection to enter **Replay** mode: matching calls are served from recorded mocks.

**Breakpoints** — pause requests/responses to inspect or modify them before they continue.

**Device setup** — a dedicated section to connect iOS/Android: guided simulator install and a QR
code to install the certificate on a physical device.

### MCP automation

Start FRTMProxy, then choose **Device → Copy MCP Server Configuration** and paste the copied JSON
into your MCP client. The bundled stdio launcher connects to FRTMProxy's local Unix socket. Flow
headers and URLs are redacted by default, bodies are omitted by default, and the socket is
accessible only to the current macOS user.

---

## Screenshots

### Inspector

| Light | Dark |
| --- | --- |
| ![Inspector (Light)](.media/Inspector.png) | ![Inspector (Dark)](.media/Inspector_dark.png) |

### Mock with Map Local

![Map Local editor](.media/MapLocal.png)

### Traffic profiles & tools

![Manage menu and traffic profiles](.media/TrafficProfiles.png)

### Device setup

![Device pairing and certificate install](.media/Device.png)

---

## Contributing

FRTMProxy is public domain and contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) to
get started (`make bootstrap`, `make build`, `make test`). Maintainer release notes live in
[docs/RELEASING.md](docs/RELEASING.md).

## Support

FRTMProxy is free and will stay free. If it saves you time, a ⭐ on the repo genuinely helps it reach
more developers — and if you'd like to say thanks, you can buy me a coffee.

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-fratm-FFDD00?logo=buymeacoffee&logoColor=black)](https://www.buymeacoffee.com/fratm)

## License

Released into the **public domain** under the [Unlicense](LICENSE). Do whatever you want with it.

Happy debugging! 🚀
