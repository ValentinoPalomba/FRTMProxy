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
./scripts/update_homebrew_cask.sh \
  --version 1.7.0 \
  --tag v.1.7.0 \
  --tap-dir ~/Repositories/homebrew-frtmtools
```

Optional automation in the tap repository:

```bash
# commit in the tap repo
./scripts/update_homebrew_cask.sh --version 1.7.0 --tag v.1.7.0 \
  --tap-dir ~/Repositories/homebrew-frtmtools --commit

# commit + push in the tap repo
./scripts/update_homebrew_cask.sh --version 1.7.0 --tag v.1.7.0 \
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
