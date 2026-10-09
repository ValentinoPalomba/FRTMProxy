#!/usr/bin/env bash
set -euo pipefail

# Secrets arrive via the workflow environment; never enable shell tracing here.
for variable in DEVELOPER_ID_CERTIFICATE DEVELOPER_ID_PASSWORD APPLE_ID APPLE_APP_PASSWORD APPLE_TEAM_ID SPARKLE_PRIVATE_KEY; do
  [[ -n "${!variable:-}" ]] || { echo "Missing release setting: $variable" >&2; exit 1; }
done
mkdir -p artifacts
keychain="$RUNNER_TEMP/release.keychain-db"
keychain_password="$(openssl rand -hex 32)"
printf '%s' "$DEVELOPER_ID_CERTIFICATE" | base64 --decode > "$RUNNER_TEMP/developer-id.p12"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$RUNNER_TEMP/developer-id.p12" -P "$DEVELOPER_ID_PASSWORD" -A -t cert -f pkcs12 -k "$keychain"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
identity="$(security find-identity -v -p codesigning "$keychain" | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p')"
[[ -n "$identity" && "$identity" != *$'\n'* && "$identity" == *"($APPLE_TEAM_ID)" ]] || {
  echo 'Expected one Developer ID Application identity matching APPLE_TEAM_ID' >&2; exit 1;
}
xcrun notarytool store-credentials release-notary --keychain "$keychain" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" >/dev/null

xcodebuild -project FRTMProxy.xcodeproj -scheme FRTMProxy_Release \
  -configuration Release -destination 'platform=macOS' -derivedDataPath .build-release \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO OTHER_CODE_SIGN_FLAGS="--timestamp --keychain $keychain" build
app='.build-release/Build/Products/Release/FRTMProxy.app'
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$GITHUB_REF_NAME" == "v$version" || "$GITHUB_REF_NAME" == "v.$version" ]] || {
  echo 'Tag must match the version in project.yml (vVERSION or v.VERSION)' >&2; exit 1;
}
# Verify copied runtime byte-for-byte; do not re-sign the upstream engine.
python3 - "$app" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, 'scripts')
from verify_engine import verify
verify(Path(sys.argv[1]) / 'Contents/Resources', json.loads(Path('FRTMProxy/Resources/mitmdump.metadata.json').read_text()))
PY
codesign --verify --deep --strict --verbose=2 "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$RUNNER_TEMP/notary.zip"
xcrun notarytool submit "$RUNNER_TEMP/notary.zip" --keychain-profile release-notary \
  --keychain "$keychain" --wait --timeout 30m --output-format json > artifacts/notarization.json
python3 - <<'PY'
import json
from pathlib import Path
result = json.loads(Path('artifacts/notarization.json').read_text())
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted; inspect notarization.json')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "artifacts/FRTMProxy-$version.zip"

sparkle_bin="$(find .build-release/SourcePackages/artifacts -type f -name generate_appcast -print -quit)"
[[ -n "$sparkle_bin" ]] || { echo 'Sparkle tools missing' >&2; exit 1; }
sparkle_bin="$(dirname "$sparkle_bin")"
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$RUNNER_TEMP/sparkle.key"
"$sparkle_bin/generate_keys" --account release -f "$RUNNER_TEMP/sparkle.key"
public_key="$("$sparkle_bin/generate_keys" --account release -p)"
expected_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")"
[[ "$public_key" == "$expected_key" ]] || { echo 'Sparkle private key does not match SUPublicEDKey' >&2; exit 1; }
"$sparkle_bin/generate_appcast" --account release \
  --download-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/$GITHUB_REF_NAME/" \
  --link "https://github.com/$GITHUB_REPOSITORY/releases" -o artifacts/appcast.xml artifacts
# Keep historical download URLs and reject reused or older build versions.
python3 scripts/merge_release_appcast.py artifacts/appcast.xml .release-pages/appcast.xml
