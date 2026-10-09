# Releasing FRTMProxy

Maintainer notes for cutting a new release. Day-to-day contributors don't need this.

The app version lives in **`project.yml`** (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).
Bump it there, then regenerate the Xcode project:

```bash
# edit project.yml -> MARKETING_VERSION / CURRENT_PROJECT_VERSION
make gen
```

## GitHub Actions: signed and notarized releases

The `Release` workflow runs when a `v*` tag is pushed. The tagged commit must
belong to `main`, and the tag must match `MARKETING_VERSION`: `v1.10.0` or
`v.1.10.0`. Use a new version greater than every published version and increase
`CURRENT_PROJECT_VERSION` too; do not reuse existing tags.

Create a GitHub environment named `release`, with these secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE` | Base64-encoded `.p12` exported from Keychain Access, containing the **Developer ID Application** certificate and its private key |
| `DEVELOPER_ID_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_ID` | Apple Developer account email |
| `APPLE_APP_PASSWORD` | Apple app-specific password for notarization |
| `SPARKLE_PRIVATE_KEY` | Existing Sparkle private key exported with `generate_keys -x`; raw file contents, not an additional base64 encoding |

Add the environment variable `APPLE_TEAM_ID` (currently `8JS222QZL3`).
Keep secret values out of commits, logs, and chat messages. The certificate
must be valid for Developer ID distribution, not Apple Development.
Export the existing Sparkle key; generating a replacement would break update
validation for installed copies. The workflow verifies its public key against
the app's `SUPublicEDKey`.

In **Settings → Pages → Build and deployment**, select **GitHub Actions**.
The existing `gh-pages` branch remains the persistent store for the website,
old downloads, and appcast history. The workflow updates that branch and deploys
its contents with the official Pages actions. Restrict the `release` environment
to maintainer-controlled tags as appropriate.

The workflow builds for **Apple Silicon / arm64**, matching the pinned embedded
mitmproxy engine. Xcode signs the app and Sparkle helpers with hardened runtime
and secure timestamps. The upstream engine is never re-signed; its complete
copied tree is verified against the pinned manifest. Apple notarization must be
accepted, stapling must validate, and Gatekeeper must accept the app before the
final ZIP is created. Sparkle signs this final ZIP, historical appcast entries
keep their download URLs, and the GitHub Release is published before the feed.
Delta updates for the new release are not generated.

After merging and testing `main`, bump the version, regenerate the project,
commit and push those changes, then push the matching tag:

```bash
git tag v1.10.0
git push origin v1.10.0
```

The example version must be replaced with the version in `project.yml`.
Diagnostics and the packaged ZIP are retained as Actions artifacts for 14 days.
If release publication succeeds but Pages fails, the ZIP remains available;
recover the feed deployment before cutting another release. Do not overwrite a
published ZIP: its Sparkle signature and installed clients depend on its bytes.

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
