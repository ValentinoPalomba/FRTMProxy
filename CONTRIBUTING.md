# Contributing to FRTMProxy

Thanks for your interest in improving FRTMProxy! This is a free, public-domain macOS app and
contributions of all kinds are welcome — bug reports, fixes, features, docs.

## Prerequisites

- macOS 26.0+ and a recent Xcode.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

The Xcode project is **generated from `project.yml`** (the source of truth). Never hand-edit
`FRTMProxy.xcodeproj` — change `project.yml` and regenerate.

## Getting started

```bash
make bootstrap   # installs xcodegen if missing + generates the project
make build       # build the dev scheme
make test        # run the FRTMProxyTests suite (Swift Testing)
make run         # build & launch the app
make help        # list all targets
```

Dependencies (Sparkle, CodeMirror-Swift) are resolved by Xcode via Swift Package Manager.

## Architecture (quick map)

Two processes talk over stdin/stdout, plus a SwiftUI layer:

- **`FRTMProxy/bridge.py`** — a mitmproxy addon; the single source of truth for all traffic
  manipulation (Map Local matching, breakpoints, traffic profiles). Communication is
  line-delimited JSON.
- **`ProxyServiceProtocol` / `MitmproxyService`** — owns the bundled `mitmdump` process, parses
  stdout into flows, sends commands to stdin.
- **`ProxyViewModel`** — the app's brain, split across feature extensions.

See `CLAUDE.md` for a deeper architecture overview.

> **Map Local keys must stay in sync.** The Swift `MapRuleKeyBuilder` and the Python key logic in
> `bridge.py` generate the same keys. If you change key/signature logic on either side, update both
> and regenerate the golden keys in `MapRuleKeyBuilderTests` (the generator is documented in the
> test file).

## Code style

`FRTMProxy/AGENTS.md` is the authoritative Swift/SwiftUI style guide — please read it. Highlights:
target macOS 26 / modern Swift concurrency, modern Foundation/SwiftUI APIs, one type per file,
avoid force unwraps, no third-party frameworks without discussion first. Match the surrounding
file's paradigm (some shared state uses `ObservableObject` + Combine — don't mix paradigms within
a type).

## Commits & pull requests

- Follow the [Conventional Commits](https://www.conventionalcommits.org/) format:
  `type(scope): description` (e.g. `fix(rules): align query canonicalization`).
- Keep PRs focused; describe what and why.
- Make sure `make build` and `make test` are green before opening the PR.
- Update `CHANGELOG.md` under an `## [Unreleased]` section when your change is user-facing.

## Reporting bugs

Open an issue using the bug report template. Include your macOS version, FRTMProxy version, and
clear reproduction steps.
