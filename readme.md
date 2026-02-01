# FRTMProxy

FRTMProxy is a macOS app to observe, understand, and shape HTTP/S traffic in real time. It’s built for daily debugging, with tools that organize requests, make mocking easy, and help you replay real-world scenarios in a few clicks.

FRTMProxy is free for every developer, and it will remain free.

> **Note**: This app is not intended for production use, but as an internal API debugging tool.

---

## What you can do

- **Inspect** requests and responses with a fast, readable inspector.
- **Mock** local responses in a controlled way (no code required).
- **Record sessions** and reuse them for replay and testing.
- **Pause traffic** with breakpoints to inspect or edit on the fly.
- **Connect iOS devices** with guided certificate setup.

---

## Key tools

### Rules
Define rules to answer specific requests locally. Perfect for fast mocks, edge cases, or isolating the app from external dependencies.

### Collections
Record a session, keep it locally or push it to a Git repo. You can export to **HAR**, edit it, and reuse it. When a collection is enabled, you enter **Replay** mode: when the app makes the same calls, FRTMProxy responds with the previously recorded mock services.

### Breakpoints
Pause requests/responses to inspect or modify them before letting them continue.

### Device (iOS)
A dedicated section to connect iOS devices:
- **Simulator**: guided certificate installation.
- **Physical device**: QR code to download the certificate directly on the phone.

---

## UI Preview

### Inspector

| Light | Dark |
| --- | --- |
| ![Inspector (Light)](.media/Inspector.png) | ![Inspector (Dark)](.media/Inspector_dark.png) |

### Rules

![Rules](.media/Rules.png)

### Collections

![Collections](.media/Collections.png)

### Breakpoints

![Breakpoints](.media/Breakpoints.png)

### Actions

![Actions](.media/Actions.png)

Happy debugging! 🚀
