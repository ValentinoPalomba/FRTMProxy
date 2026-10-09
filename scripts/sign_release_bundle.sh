#!/usr/bin/env bash
set -euo pipefail

app="${1:?Usage: sign_release_bundle.sh app identity [keychain]}"
identity="${2:?Developer ID Application identity required}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flags=(--force --sign "$identity" --options runtime --timestamp)
if [[ -n "${3:-}" ]]; then
  flags+=(--keychain "$3")
fi
sparkle="$app/Contents/Frameworks/Sparkle.framework"

# Sign only Sparkle's known code, inside-out. Never re-sign the pinned engine.
# https://sparkle-project.org/documentation/sandboxing/#code-signing
codesign "${flags[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
codesign "${flags[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
codesign "${flags[@]}" "$sparkle/Versions/B/Autoupdate"
codesign "${flags[@]}" "$sparkle/Versions/B/Updater.app"
codesign "${flags[@]}" "$sparkle"
codesign "${flags[@]}" --entitlements "$root/FRTMProxy/FRTMProxy.entitlements" "$app"
python3 "$root/scripts/verify_release_bundle.py" "$app" \
  --expected-public-key "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$root/Info.plist")"
