# Releasing FRTMProxy

Maintainer notes for cutting a new release. Day-to-day contributors don't need this.

The app version lives in **`project.yml`** (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).
Bump it there, then regenerate the Xcode project:

```bash
# edit project.yml -> MARKETING_VERSION / CURRENT_PROJECT_VERSION
make gen
```

## Sparkle release (recommended flow)

The simplest, reliable flow is **Archive + Distribute → Developer ID → Export** from Xcode
(the exported `.app` is signed *Developer ID Application*, notarized and stapled, so Gatekeeper
accepts it). Then zip, regenerate the appcast, and publish to `gh-pages`:

```bash
# builds FRTMProxy_Release, zips the app, regenerates appcast.xml, pushes to gh-pages
./scripts/publish_sparkle_release.sh
```

Useful variants:

```bash
# Generate zip + appcast locally only (no push)
./scripts/publish_sparkle_release.sh --no-publish

# Reuse an existing Release build output
./scripts/publish_sparkle_release.sh --skip-build

# Run Apple notarization as part of the flow
./scripts/publish_sparkle_release.sh --notarize
```

Before pushing, recover the previous `.zip` artifacts from `gh-pages` so the update history and
delta patches are preserved. The Sparkle EdDSA private key lives in the login keychain; the public
key is `SUPublicEDKey` in the root `Info.plist`.

## Homebrew cask update

After publishing a GitHub Release, update the cask metadata (`version`, `sha256`, `url`):

```bash
VERSION="x.y.z"
TAG="v.${VERSION}"

./scripts/update_homebrew_cask.sh \
  --version "$VERSION" \
  --tag "$TAG" \
  --tap-dir ~/Repositories/homebrew-frtmtools
```

Optional automation in the tap repository:

```bash
# commit in the tap repo
./scripts/update_homebrew_cask.sh --version "$VERSION" --tag "$TAG" \
  --tap-dir ~/Repositories/homebrew-frtmtools --commit

# commit + push in the tap repo
./scripts/update_homebrew_cask.sh --version "$VERSION" --tag "$TAG" \
  --tap-dir ~/Repositories/homebrew-frtmtools --push
```

## Checklist

1. Bump version in `project.yml`, run `make gen`.
2. Update `CHANGELOG.md` with the new version and date.
3. `make test` — all tests green.
4. Archive + Export (Developer ID), notarize, staple.
5. `./scripts/publish_sparkle_release.sh` (or the manual zip + `generate_appcast` flow).
6. Verify the live appcast and download: <https://valentinopalomba.github.io/FRTMProxy/appcast.xml>.
7. Update the Homebrew cask.

## Capture schema compatibility

The current capture database schema is 3. It adds the nullable incomplete-session reason while preserving encrypted flow payloads and body-reference tables. Before upgrading from a version that supports schema 2 or earlier, retain a consistent SQLite backup (including its WAL, or use SQLite's backup API with capture stopped). An older app rejects schema 3; distributing the old binary alone is not a supported rollback. Validate upgrade and restore on disposable captures before publishing a release.


## Current branch verification (6 October 2026)

The user will perform Archive, Developer ID export and notarization in Xcode.
The locally verified Release build uses a Development identity; it is not an exported
release. The publication scripts reject Development/ad hoc signatures, missing hardened
runtime/timestamp, debugging entitlements and mismatched Sparkle keys. Publication also
requires Gatekeeper and stapling verification. No key rotation or publication was performed. The user recovered the existing private
Sparkle key on another Mac; verify its public key matches `SUPublicEDKey` before signing.

The bundled engine is **Apple Silicon only (arm64)**. The Swift executable also contains
an x86_64 slice; that does not establish Intel support. Do not advertise Intel compatibility
or a universal distribution until a corresponding engine is packaged and tested.

Capture profiles and Sessions now live inside Manage → Advanced Tools. Workspace and Selective Capture screens and commands
are removed, alongside Noise Control and inspector search/expansion prototypes.
Legacy data is preserved. The latest verification and outstanding gates are recorded in
[RELEASE_READINESS.md](RELEASE_READINESS.md).

Before publication:

1. Choose the release version/build in `project.yml`, regenerate, and Archive.
2. Export for Developer ID, notarize and staple the app and nested helpers.
3. Run `python3 scripts/verify_release_bundle.py <exported.app> --require-notarization`.
4. Verify clean install, upgrade and schema-compatible rollback on disposable captures.
5. Complete current manual UI acceptance. The latest XCTest UI runner timed out while
   enabling macOS automation, before executing tests; it is not counted as a pass.
6. Resolve the documented SwiftLint baseline before claiming a clean lint run.

Native tests, HTTP/TLS integration and a 6,000-request whole-app smoke pass are evidence
for their stated scope. They do not close the roadmap's remaining 30-minute whole-app,
UI-frame latency, upstream/PAC, provider integration or comparative Rockxy parity gates.
