# Security Policy

## Supported versions

FRTMProxy ships as a rolling release; only the **latest version** receives security fixes.
Update via Homebrew (`brew upgrade --cask frtmproxy`) or the built-in Sparkle updater.

| Version         | Supported |
| --------------- | :-------: |
| Current release |     ✅    |
| Older releases  |     ❌    |

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue.

- Preferred: GitHub's [private vulnerability reporting](https://github.com/ValentinoPalomba/FRTMProxy/security/advisories/new)
  (repo → **Security** → **Report a vulnerability**).

You'll get an acknowledgement as soon as possible. Once a fix ships you're welcome to be
credited in the release notes (opt-in).

## Trust model — what FRTMProxy does to your system

FRTMProxy is a native controller for a bundled [mitmproxy](https://mitmproxy.org) engine.
To inspect HTTPS it can:

- **Install a local root CA** into your login keychain, iOS simulators, or (via QR) a physical
  device, so TLS can be decrypted. This CA is generated locally by mitmproxy and never leaves
  your machine.
- **Decrypt traffic locally.** All interception happens on your Mac; FRTMProxy sends no traffic
  to any third party.
- **Toggle the macOS system proxy** (via `networksetup`) when you enable "capture this Mac".

The app is **open source and public domain** (fully auditable), and every release is signed with
a Developer ID and **notarized by Apple**. You can remove the CA at any time from Keychain Access
(search "mitmproxy").
