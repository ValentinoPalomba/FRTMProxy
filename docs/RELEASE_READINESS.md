# Release verification — 6 October 2026

Branch: `codex/rockxy-maturity-plan`. Archive and Developer ID export will be performed by the user. This document records verification scope; it is not a signed release approval.

## Delivered behavior

- Capture profiles group requests, hosts and apps. Profiles and Sessions are under Manage → Advanced Tools, with consistent disclosure and menu styling.
- Workspace, Selective Capture, Noise Control and the redundant inspector search/expansion controls are removed from the UI. Existing saved data is preserved.
- Request/response original-body export uses an icon-only Share control, with localized accessibility labels and tooltips.
- New installations default to Xcode Light; saved theme choices remain intact.
- Panels use shared typography, spacing, colors and controls. The empty live table displays the thinking orb; inactive/reduced-motion states avoid continuous animation.
- English/Italian strings include runtime messages, presets, table columns, empty states and command-palette search. Runtime messages resolve the selected app language independently of macOS language.
- The proxy bridge parses off the main thread; live storage is bounded, profile matching is indexed, and session writes avoid repeated buffer copies. Interrupted captures drain accepted rows and retain an incomplete-session marker.

## Evidence

- Final localization subset: 7 tests passed, `/tmp/frtm-final-locale.log`; all 775 Italian catalog entries populated with matching placeholders.
- Final Release build passed, `/tmp/frtm-light-default-release.log` (Development signing); final Debug build also passed in `/tmp/frtm-light-default-debug.log`.
- Native suite: 192 Swift Testing tests and 21 XCTest tests passed (213 total), `/tmp/frtm-language-navigation-verified.log`.
- Python unit suite: 11 passed, `/tmp/frtm-final-python.log`.
- Real proxy integration: 13 HTTP/TLS/streaming/WebSocket/scripting/composer checks passed, `/tmp/frtm-final-integration.log`.
- Pinned bundled engine tree validation passed, `/tmp/frtm-final-engine.log`.
- [Whole-app smoke report](benchmarks/2026-10-06-app-stress.json): 6,000 HTTP requests at approximately 100 requests/second, 20 concurrent clients, all 6,000 persisted, no errors, duplicate IDs or corrupt flows. Deliberate engine termination correctly drained and closed the interrupted session.
- That smoke used a Debug build with optimization on Apple M4/macOS arm64. Peak app RSS was 256.47 MiB; engine RSS 135.58 MiB. Client latency p95 was 3.58 ms. These are local HTTP results, not TLS overhead or rendered UI-frame latency.

## Manual UI checkpoint

The real demo app was inspected in Italian. Manage → Advanced Tools exposes Capture profiles and Sessions; selecting Intesa reduced the table from 37 flows to 13 and All traffic restored 37. Request/Response Share controls are icon-only with Italian accessibility labels. The final demo is running with Xcode Light, 36 generated requests plus one readiness request, and Intesa/CheBanca/Curl profiles. [Screenshot](ui-recovery/2026-10-06/demo-inspector-it-light.png). This checkpoint does not replace acceptance of every panel in both languages.

## Distribution gates

1. Choose the release version/build, regenerate the Xcode project, Archive and export with Developer ID. The local Release build is Development-signed.
2. Notarize/staple, then run `python3 scripts/verify_release_bundle.py <exported.app> --require-notarization`.
3. Confirm the recovered private Sparkle key on the other Mac corresponds to the unchanged `SUPublicEDKey` in `Info.plist`; sign the update there. No key was generated, rotated or published here.
4. Verify clean install, upgrade and schema-compatible rollback on disposable captures. Capture schema is 3; an older binary alone is not a supported database rollback.
5. Complete manual acceptance in both languages. The most recent XCTest UI runner timed out enabling automation before executing tests and is not counted as a pass.

## Remaining scope and limitations

- The bundled engine is arm64 only. An x86_64 app slice does not establish Intel support.
- The whole-app smoke lasted about one minute of load. A 30-minute whole-app memory plateau and UI frame/filter latency remain unverified. A separate sustained engine test does not replace these checks.
- SwiftLint has an existing non-clean baseline: 688 findings, including 58 errors, in `/tmp/frtm-final-lint.json`. No clean lint or commit-readiness claim is made.
- Upstream/PAC/provider integration and comparative Rockxy parity gates in the broader maturity plan remain open; the current UI and performance work does not complete that entire roadmap.


## Integration checkpoint — 9 October 2026

Version and build number are 1.9.0 in `project.yml` and the regenerated Xcode project. Before the requested commit, `git diff --check` passed. SwiftLint over both app and native-test sources reported 876 findings (782 warnings, 94 errors); this larger scope is not directly comparable to the earlier app-focused baseline. Lint is still not clean. Previous temporary build logs may no longer be available after a host restart; the checked-in benchmark reports and screenshots remain the durable evidence.
