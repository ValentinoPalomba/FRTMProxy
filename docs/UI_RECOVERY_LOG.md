# UI recovery and reliability evidence

Current UI scope (6 October 2026): Workspace and Selective Capture surfaces are removed. Named call/host/app profiles live inside Manage; Add Field lives in the trailing table slider menu. Earlier workspace/noise/selective screenshots and entries below are historical evidence. Compatibility formats and services are retained.

Date: 5 October 2026. Base: `e292683`, branch `codex/rockxy-maturity-plan`.

This register tracks implementation and observations separately. A successful build or logic test does not close visual acceptance. The reference is the existing FRTMProxy design system; no Rockxy code has been copied.

| ID | Workflow | Evidence before correction | Change | Acceptance status |
|---|---|---|---|---|
| C1 | Composer header values | `ComposerTemplate` skipped every row without a name, including a nonempty value | Reject partial rows explicitly; preserve empty values, duplicate names and order | Verified through local HTTP fixture: duplicate/empty headers and wire request; dark/light S/M/L UI workflow passes |
| C2 | Composer header limit | Add appended without checking the existing 128-row transport limit | Enforce limit before mutation; show count/limit; keep stable row identity; scroll before focus | 128-row boundary covered in logic; Add/type sequence and stable row values verified in UI |
| C3 | Composer layout | XCTest screenshot shows the footer missing; Send has a nonfinite clickable rectangle | Constrain layout to GeometryReader bounds; support a narrower sheet; adapt header and two-column threshold to UI scale | Confirmed before fix; corrected full-sheet screenshot shows reachable Send, verified by actual click and response |
| C4 | Composer variable cancellation | Sheet bound directly to live variables and saved on every dismissal | Local draft, Save/Cancel, validation, retained draft on failure, bounded scrolling, focus after Add | Save/reopen and Cancel verified in UI; validation/write failure retain previous persisted values in logic tests |
| R1 | Header matcher persistence | Materialization filtered out unnamed rows, including partial matchers | Retain rows and prevent save until every matcher has a valid name; trim names on successful materialization | Interactive save/reopen verified in dark/light; engine fixture verifies wildcard and case-sensitive match/nonmatch |
| R2 | Rules theme and scrolling | Pattern/action editors used fixed red and standard controls outside app palette | Pass owner palette into editors; use existing fields/buttons/tokens; bound header list and scroll new matcher into view | Build passes; matcher screenshots reviewed in dark/light medium; action editor and long-list matrix remain open |
| I1 | Header columns | Add could create a column hidden by the active search; sheet had no maximum height | Clear search on Add, scroll to the new column, restore input focus, fixed sheet extent, bounded errors | Existing serialization tests; dark/light medium screenshots reviewed; interactive column Save/Cancel remains open |
| I2 | Flow diff | Long URLs/warnings/values could expand summary and rows | Bound display text, retain full value in help, use existing loading/error component and keyboard Close | Existing diff logic tests; long-content visual acceptance pending |
| S1 | Session notes | New note sheet used standard action buttons and unbounded editor minimum | Reuse app editor/buttons, fixed sheet extent, prevent dismissal while saving | Build verified; session note visual workflow remains open |
| W1 | Session writer | Batch limits did not limit the complete pending/in-flight/retry queue | Global estimated-payload/count reservation; reject saturation explicitly, stop capture, preserve accepted retries, persist incomplete status (SQLite schema 3) | Count/byte/retry/migration tests; whole-app RSS still unmeasured |

## Automated runs

- Native latest run: 170 Swift Testing tests + 20 XCTest tests pass (190 total), including actual event → saturation → stop → durable incomplete session and transactional encrypted HAR import. Aggregated coherence build and native run passed on October 5 (`/tmp/frtm-visual-coherence-build.log`, `/tmp/frtm-coherence-native.log`).
- Python bridge: 11 tests pass. Proxy/composer end-to-end fixture: 13 tests pass, including request-header wildcard and case sensitivity on actual proxied requests.
- Composer UI: complete Add/type/send/response and variable Cancel/Save/reopen workflow passes for Tokyo Night and Xcode Light at S/M/L. The refreshed matrix passes; full-sheet captures were reviewed at medium and at dark L/light S.
- Rules UI: Add/type/save/reopen retains header name, wildcard pattern/mode and case sensitivity in both themes. Escape cancels the inner editor. Column/noise sheets opened and cancelled in both themes; screenshots reviewed.
- Failed runs are retained in Xcode results: initial launch failure, confirmed missing footer, missing fixture listener entitlement, an ambiguous picker label and nested Cancel query. Two overlapping Xcode runs were stopped and rerun serially. They are not counted as passes.
- XCTest fixture declares network client/server capabilities and binds only `127.0.0.1`; application entitlements are unchanged. Debug fixture storage is disposable and uses a fixture-only encryption key. Release storage continues using Keychain. Column/noise forms are cancelled, preserving the user's preferences.
- Startup sampling confirmed synchronous Keychain access before window creation. Default session-store initialization and body-store environment loading now run outside MainActor; a cancelled start cannot later launch after storage becomes ready.
- Sustained engine replication passes: 180,000 requests/terminal events, zero duplicates/client errors, 100 req/s over 1,800.089 seconds. Engine peak RSS 138.375 MiB. Scope is HTTP engine + bridge only, excluding Swift app/session writer and TLS overhead. Raw report: [2026-10-05-proxy-sustained.json](benchmarks/2026-10-05-proxy-sustained.json).

The recovery tests use synthetic localhost traffic, do not enable the system proxy and do not install a CA. The baseline for C3 is [composer-before-footer-fix.png](ui-recovery/2026-10-05/composer-before-footer-fix.png). Corrected captures are stored alongside it.

## Still required

Complete interactive workflows for columns, filter drafts, search/diff, sessions/export/import and workspace. Extend rule/editor coverage to long lists and actions. Check light, dark and custom themes; S/M/L; supported minimum/large windows; empty/long lists; long errors; keyboard navigation; capture updating during edits. Confirm the original user-reported Add Header defect in its original screen before attributing a cause.

Writer budget is 4,096 queued snapshots / 64 MiB of estimated payload, including batches being written and retry data. Reservations are released after snapshot references are dropped. A single record over the budget is refused; prior accepted records remain queued. This is neither an RSS limit nor durable storage for data not yet committed. If the disk also prevents recording the incomplete marker, the error remains visible in memory/logs; recovery after an application crash in this state remains open.

SQLite schema 3 preserves existing encrypted flow payloads and adds a nullable reason. Older app versions reject schema 3, so rollback requires a pre-upgrade database backup or a compatible version. Signed distribution/update/rollback and comparative Rockxy testing remain unverified.

## Next inspector/session increment

The captured main window could be 451 px high while its split panes required more space; a screenshot and accessibility geometry showed table/panel content outside window bounds. Inspector now supplies an explicit scaled minimum (1060 × 900 logical points) for both empty and selected states. Session browser has an explicit themed Close action with Escape; note editor has a named accessibility field. A persisted incomplete active session is excluded when choosing the target for a new capture, retaining its original failure reason. These latest changes require fresh native/UI acceptance.

A draft-cancellation run reached columns/noise forms in both themes but its exact text query for the new column failed; this is recorded as failed UI evidence. It has not been counted as a complete column editing pass.

The expanded JSON-search screenshot reproduced a second layout overflow: raising the window minimum alone did not contain the AppKit split view. The inspector content area is now constrained to GeometryReader bounds, with a larger bottom-pane minimum and a bounded JSON result region. A fresh UI run is required before this correction is accepted. Note Save/reopen ran in both themes, but one fast injected text sequence dropped a character; the overall test failed and is not a passing result. Debug test launches blocked in dyld were worked around locally with `ENABLE_DEBUG_DYLIB=NO` without changing Release configuration.

## Graphical coherence increment

Parallel view work covered Rules, Sessions/Workspace, and an independent keyboard diagnosis. Rules action editors now use owner palette, shared fonts, styled menus/buttons, bounded names and horizontally scrolling badges. Sessions use themed list backgrounds, selected-row contrast, bounded text/tooltips, consistent Close/Delete actions and a scaled sidebar. HAR review has bounded scrolling; workspace preferences remain within a scrolling region so resources stay reachable. Inspector JSON results use a compact selectable text region rather than a second embedded web editor; split-view sizing is explicitly constrained.

The aggregated build and all 190 native tests passed once after these changes. Direct inspection of that build confirmed the dark rule editor and Mock Response form, empty sessions, empty HAR import, and workspace in dark and Xcode Light. Fresh images are under `ui-recovery/2026-10-05/coherence/`. A transient ScreenCaptureKit stream failure occurred during inspection; a fresh state query recovered capture. No full UI test pass is claimed for this increment. Populated timeline, new JSON geometry, action variants, long lists, additional scales/themes and complete workspace/HAR workflows still require visual acceptance.

Independent source diagnosis found no plain `c` interception or character filtering in note persistence. The failing XCTest note input remains unresolved between native input handling and event synthesis; no speculative keyboard change was made. The user's theme preference was restored after the light-theme comparison.

## All-panel pass and empty-traffic orb

Installed the user-requested `Leonxlnx/taste-skill` package (13 skills) with `npx skills add ... --agent codex --global --yes`. Applied its `redesign-existing-projects` audit to the existing native DesignSystem. The landing-page-specific `design-taste-frontend` explicitly excludes dense product interfaces, so marketing layouts and web dependencies were not applied to this app.

The second parallel pass covers Collections/Git/Publish, Breakpoints, Scripts, Settings/Alerts, Device/Simulator/Selective Capture and onboarding. Map Local headings/actions/minimum sizes and long host/path labels were also aligned. Shared native fonts, palette, control styles and scaled dimensions are reused; original platform-specific Settings navigation is retained. All-panel build passed (`/tmp/frtm-coherence-orb-build.log`). Most of these additional views still require light/dark and scale acceptance; fresh Collections empty-state capture is available.

`TrafficThinkingOrb` ports the upstream MIT-licensed `working` orbit geometry to SwiftUI Canvas, including deterministic tilted paths, depth ordering and 64-preset speed. It is rendered at a scaled 112-point extent, centrally in the empty traffic content area, with theme ink and an accessible waiting message. No orb appears merely because filters exclude existing flows. Timeline updates are capped at 30 Hz and pause when the scene is inactive or Reduce Motion is enabled. The license is retained in `docs/licenses/` and bundled in application resources. Direct inspection confirmed the empty-traffic orb and its changing particle positions on the compiled build (`orb-empty-dark.png`). Reduce Motion, disappearance on first flow and inactive-scene CPU behavior still need dedicated runtime checks.

An imagegen concept board is saved as `coherence/design-concept.png`. It is a proposed visual reference, not implementation evidence. The real compiled UI is recorded separately. A real JSONPath query returned `[1]`, but its expanded controls still overflowed the panel in that capture. The follow-up bounded query scroll and explicit panel geometry compile successfully; they are not yet visually accepted. No failed old UI workflow was relabeled as passing. SwiftLint remains failing on existing repository violations; no clean-lint claim is made.


## User-directed Inspector simplification and named profiles

The user's later instructions supersede the earlier search/noise/expansion prototype. Removed Noise Control/Focus Sets toolbar UI, header-column search, HTTP-header search and expansion controls. Header columns are managed through `+ Add Field…` inside the final existing slider menu, including the empty-table state. Prior captures of expanded headers document an abandoned prototype and are not evidence of the current interface.

Named capture profiles support request (method + origin/path, excluding credentials/query/fragment), host and app membership. Members compose with OR. Creation and adding to an existing profile are available from each traffic row; the toolbar switches profiles and All Traffic. Manager supports naming, explicit member removal and confirmed profile deletion. Selected profile and members persist together. Legacy saved filters migrate without overwriting their original data; unreadable storage is preserved and blocks writes with a visible error. Limits and validation reject malformed hosts, invalid member input, duplicate names and oversized snapshots before mutation.

Named profiles ignore unrelated saved host/app pins while retaining explicit search/status/device filters. Selecting a profile or All Traffic clears transient filters. Startup no longer silently reapplies saved pins to All Traffic. Engine capture remains separate from this view filter.

Native verification after integration passed: 178 Swift Testing + 20 XCTest tests (198 total), including eight new profile tests; `/tmp/frtm-profiles-native-final.log`. An additional worker projection test and the single real-loopback profile UI workflow are pending at this checkpoint. An initial build overlapped unfinished model edits and failed; it is not counted as passing. The first UI invocation used the unit-only scheme and was rejected before execution; the corrected invocation uses FRTMProxyScreenshots.

Release status remains open. The local codesigning identity check found Apple Development identities but no Developer ID Application identity; distribution signing/notarization are not confirmed. Native passes and screenshots do not establish complete release readiness. Existing SwiftLint failures, outstanding UI acceptance and roadmap gates remain tracked above.


### 6 October 2026 — final navigation, locale and light default checkpoint

Capture profiles and Sessions moved to Manage → Advanced Tools. The disclosure row now shares typography, spacing, hover and pressed states with the other menu rows. Original-body export uses the shared icon-only Share control. Runtime localization now follows the app language, and all 775 Italian catalog entries are populated. Xcode Light is the default for new installations; saved themes are preserved.

Native suite passed 213 tests; final localization subset passed 7. Final Debug/Release builds passed. Direct demo UI inspection verified the advanced menu, Intesa filtering (13/37) and restoration to all traffic. The current light demo has 36 generated requests plus one readiness request. Evidence and distribution gates: [RELEASE_READINESS.md](RELEASE_READINESS.md).
