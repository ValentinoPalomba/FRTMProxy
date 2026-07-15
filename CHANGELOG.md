# Changelog

All notable changes to FRTMProxy are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.7.0] - 2026-07-13

### Added
- Full UX/UI redesign: dark-first, Linear/Raycast-inspired, with a redesigned neutral palette and
  indigo accent, consistent components, empty/loading/error states, and toast notifications.
- Device certificate setup for macOS and Android, plus **capture of this Mac's own traffic** via a
  system proxy override toggle.
- Localization in 8 languages (String Catalog).
- Unit test suite (`FRTMProxyTests`, Swift Testing) covering pure logic, including golden Map Local
  keys kept in sync with `bridge.py`.
- Column sorting, show/hide columns, hover, and error-row highlighting in the flow list.

### Changed
- Project generation migrated to **XcodeGen** (`project.yml` is the source of truth); added a
  `Makefile` task runner.
- Always-visible status bar with proxy state, flow counts, and a "Mac proxy" badge; refreshed
  menu bar extra.

### Fixed
- Map Local query canonicalization now matches `bridge.py` for percent-encoded `+`.
- Hardened the `mitmdump` process and stdout handling; bounded resource usage in the bridge.
- Collections capture in-flight flows and preserve binary bodies; guard against data loss on
  corrupted store files.

## [1.6.0] - 2026-03-03

### Changed
- Switched the macOS system proxy override backend to `networksetup`.
- Verbose bridge debug logs are now gated behind an environment flag.

### Added
- Apple notarization step in the Sparkle publish script.

## [1.5.1] - 2026-02-25

### Fixed
- New EdDSA signing key for Sparkle updates and appcast publishing fixes.

[Unreleased]: https://github.com/ValentinoPalomba/FRTMProxy/compare/v.1.7.0...HEAD
[1.7.0]: https://github.com/ValentinoPalomba/FRTMProxy/releases/tag/v.1.7.0
[1.6.0]: https://github.com/ValentinoPalomba/FRTMProxy/releases/tag/v.1.6.0
[1.5.1]: https://github.com/ValentinoPalomba/FRTMProxy/releases/tag/v1.5.1
