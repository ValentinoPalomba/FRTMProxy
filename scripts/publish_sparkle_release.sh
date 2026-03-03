#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-FRTMProxy}"
SCHEME="${SCHEME:-FRTMProxy_Release}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS}"
INFO_PLIST_PATH="${INFO_PLIST_PATH:-$ROOT_DIR/Info.plist}"
RELEASE_DIR="${RELEASE_DIR:-$HOME/releases/$APP_NAME}"
REMOTE_NAME="${REMOTE_NAME:-origin}"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-ed25519}"
PRODUCT_LINK="${PRODUCT_LINK:-https://github.com/ValentinoPalomba/FRTMProxy/releases}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"
RELEASE_NOTES_URL_PREFIX="${RELEASE_NOTES_URL_PREFIX:-}"

# Notarization settings (env overrides)
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"
APPLE_PASSWORD="${APPLE_PASSWORD:-}"

PUBLISH=1
BUILD_APP=1
ALLOW_KEY_CREATE=1
NOTARIZE=0

log() {
  printf '%s\n' "[sparkle-release] $*"
}

fail() {
  printf '%s\n' "[sparkle-release] ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/publish_sparkle_release.sh [options]

Options:
  --release-dir <path>          Directory containing Sparkle archives and appcast
  --scheme <name>               Xcode scheme (default: FRTMProxy_Release)
  --configuration <name>        Xcode configuration (default: Release)
  --destination <value>         xcodebuild destination (default: platform=macOS)
  --download-url-prefix <url>   Prefix for enclosure URLs in appcast
  --notes-url-prefix <url>      Prefix for release notes URLs in appcast
  --product-link <url>          Link used in appcast item
  --remote <name>               Git remote for publishing (default: origin)
  --pages-branch <name>         Branch for GitHub Pages (default: gh-pages)
  --sparkle-account <name>      Keychain account for Sparkle keys (default: ed25519)
  --skip-build                  Reuse existing Release build product
  --no-publish                  Do not push artifacts to gh-pages
  --no-key-create               Fail if Sparkle private key is missing

Notarization:
  --notarize                    Submit app for notarization and staple ticket (default: off)
  --notarytool-profile <name>   Keychain credential profile for notarytool (recommended)
  --apple-id <email>            Apple ID for notarization (alternative to --notarytool-profile)
  --team-id <id>                Apple Developer Team ID
  --apple-password <pass>       App-specific password or @keychain:<item>

  -h, --help                    Show this help

Environment overrides:
  APP_NAME, SCHEME, CONFIGURATION, DESTINATION, INFO_PLIST_PATH,
  RELEASE_DIR, REMOTE_NAME, PAGES_BRANCH, SPARKLE_ACCOUNT, PRODUCT_LINK,
  DOWNLOAD_URL_PREFIX, RELEASE_NOTES_URL_PREFIX,
  NOTARYTOOL_PROFILE, APPLE_ID, TEAM_ID, APPLE_PASSWORD

Notes:
  Notarization requires macOS 12+ and Xcode 13+. The recommended approach is
  to store credentials once with:
    xcrun notarytool store-credentials "AC_PASSWORD" \
      --apple-id you@example.com --team-id TEAMID --password <app-specific-pwd>
  Then pass --notarytool-profile "AC_PASSWORD" to this script.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-dir)
      RELEASE_DIR="$2"
      shift 2
      ;;
    --scheme)
      SCHEME="$2"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --destination)
      DESTINATION="$2"
      shift 2
      ;;
    --download-url-prefix)
      DOWNLOAD_URL_PREFIX="$2"
      shift 2
      ;;
    --notes-url-prefix)
      RELEASE_NOTES_URL_PREFIX="$2"
      shift 2
      ;;
    --product-link)
      PRODUCT_LINK="$2"
      shift 2
      ;;
    --remote)
      REMOTE_NAME="$2"
      shift 2
      ;;
    --pages-branch)
      PAGES_BRANCH="$2"
      shift 2
      ;;
    --sparkle-account)
      SPARKLE_ACCOUNT="$2"
      shift 2
      ;;
    --skip-build)
      BUILD_APP=0
      shift
      ;;
    --no-publish)
      PUBLISH=0
      shift
      ;;
    --no-key-create)
      ALLOW_KEY_CREATE=0
      shift
      ;;
    --notarize)
      NOTARIZE=1
      shift
      ;;
    --notarytool-profile)
      NOTARYTOOL_PROFILE="$2"
      NOTARIZE=1
      shift 2
      ;;
    --apple-id)
      APPLE_ID="$2"
      NOTARIZE=1
      shift 2
      ;;
    --team-id)
      TEAM_ID="$2"
      shift 2
      ;;
    --apple-password)
      APPLE_PASSWORD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

command -v xcodebuild >/dev/null || fail "xcodebuild not found"
command -v git >/dev/null || fail "git not found"
command -v ditto >/dev/null || fail "ditto not found"
command -v rsync >/dev/null || fail "rsync not found"
command -v xcrun >/dev/null || fail "xcrun not found"
[[ -x /usr/libexec/PlistBuddy ]] || fail "PlistBuddy not found"

find_sparkle_bin() {
  if [[ -n "${SPARKLE_BIN:-}" && -x "${SPARKLE_BIN}/generate_appcast" ]]; then
    printf '%s\n' "$SPARKLE_BIN"
    return 0
  fi

  local pattern
  pattern="$HOME/Library/Developer/Xcode/DerivedData/FRTMProxy-"'*/SourcePackages/artifacts/sparkle/Sparkle/bin'
  local candidate
  candidate="$(ls -dt $pattern 2>/dev/null | head -n1 || true)"
  if [[ -n "$candidate" && -x "$candidate/generate_appcast" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  log "Sparkle tools not found in DerivedData. Resolving package dependencies..."
  xcodebuild -resolvePackageDependencies -project "$ROOT_DIR/FRTMProxy.xcodeproj" >/dev/null
  candidate="$(ls -dt $pattern 2>/dev/null | head -n1 || true)"
  if [[ -n "$candidate" && -x "$candidate/generate_appcast" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

# Submit app bundle for Apple notarization, then staple the ticket.
# Must be called after build and before creating the final distribution archive.
notarize_and_staple() {
  local app_path="$1"

  log "Notarizing $app_path ..."

  # Validate credentials
  if [[ -z "$NOTARYTOOL_PROFILE" ]] && [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APPLE_PASSWORD" ]]; then
    fail "Notarization requires either --notarytool-profile or all three of --apple-id, --team-id, --apple-password"
  fi

  # Create a temporary ZIP for submission (notarytool requires a zip/pkg/dmg)
  local temp_zip
  temp_zip="$(mktemp -t notarize-submit-XXXX).zip"
  local _cleanup_zip="$temp_zip"
  # shellcheck disable=SC2064
  trap "rm -f '$_cleanup_zip'" RETURN

  log "Creating temporary archive for notarization submission..."
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$temp_zip"

  # Submit and wait for Apple's response
  log "Submitting to Apple Notary Service (this may take a few minutes)..."
  if [[ -n "$NOTARYTOOL_PROFILE" ]]; then
    xcrun notarytool submit "$temp_zip" \
      --keychain-profile "$NOTARYTOOL_PROFILE" \
      --wait \
      --timeout 30m
  else
    xcrun notarytool submit "$temp_zip" \
      --apple-id "$APPLE_ID" \
      --team-id "$TEAM_ID" \
      --password "$APPLE_PASSWORD" \
      --wait \
      --timeout 30m
  fi

  rm -f "$temp_zip"

  # Staple the notarization ticket to the app bundle so it works offline
  log "Stapling notarization ticket to $app_path ..."
  xcrun stapler staple "$app_path"

  # Verify the staple succeeded
  log "Verifying stapled ticket..."
  xcrun stapler validate "$app_path"

  log "Notarization and stapling complete."
}

SPARKLE_BIN="$(find_sparkle_bin)" || fail "Unable to locate Sparkle tools (generate_appcast/sign_update)"
log "Using Sparkle tools from: $SPARKLE_BIN"

if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$INFO_PLIST_PATH" 2>/dev/null || true)"
  DOWNLOAD_URL_PREFIX="${FEED_URL%appcast.xml}"
fi
if [[ -z "$RELEASE_NOTES_URL_PREFIX" ]]; then
  RELEASE_NOTES_URL_PREFIX="$DOWNLOAD_URL_PREFIX"
fi
[[ -n "$DOWNLOAD_URL_PREFIX" ]] || fail "Unable to infer --download-url-prefix (SUFeedURL missing?)"

plist_get_or_empty() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST_PATH" 2>/dev/null || true
}

plist_set_string() {
  local key="$1"
  local value="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST_PATH" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$INFO_PLIST_PATH"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$INFO_PLIST_PATH"
  fi
}

CURRENT_PUBLIC_KEY="$(plist_get_or_empty SUPublicEDKey)"
KEY_UPDATED=0

if KEYCHAIN_PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null)"; then
  :
else
  if [[ "$ALLOW_KEY_CREATE" -eq 0 ]]; then
    fail "Sparkle private key for account '$SPARKLE_ACCOUNT' not found in Keychain"
  fi
  log "Sparkle private key missing. Generating a new key for account '$SPARKLE_ACCOUNT'..."
  "$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" >/dev/null
  KEYCHAIN_PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)"
fi

if [[ -z "$KEYCHAIN_PUBLIC_KEY" ]]; then
  fail "Unable to read Sparkle public key from Keychain account '$SPARKLE_ACCOUNT'"
fi

if [[ "$CURRENT_PUBLIC_KEY" != "$KEYCHAIN_PUBLIC_KEY" ]]; then
  log "Updating SUPublicEDKey in $INFO_PLIST_PATH"
  plist_set_string "SUPublicEDKey" "$KEYCHAIN_PUBLIC_KEY"
  KEY_UPDATED=1
fi

if [[ "$BUILD_APP" -eq 1 ]]; then
  log "Building app ($SCHEME / $CONFIGURATION)..."
  xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    build
fi

BUILD_SETTINGS="$(
  xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -showBuildSettings 2>/dev/null
)"

TARGET_BUILD_DIR="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F' = ' '/TARGET_BUILD_DIR =/ {print $2; exit}')"
FULL_PRODUCT_NAME="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F' = ' '/FULL_PRODUCT_NAME =/ {print $2; exit}')"
[[ -n "$TARGET_BUILD_DIR" ]] || fail "Unable to determine TARGET_BUILD_DIR"
[[ -n "$FULL_PRODUCT_NAME" ]] || fail "Unable to determine FULL_PRODUCT_NAME"

APP_PATH="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
[[ -d "$APP_PATH" ]] || fail "Built app not found at $APP_PATH"

# Notarize before packaging so the stapled ticket is included in the archive
if [[ "$NOTARIZE" -eq 1 ]]; then
  notarize_and_staple "$APP_PATH"
else
  log "Skipping notarization (pass --notarize to enable)"
fi

APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO_PLIST")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_INFO_PLIST")"
ARCHIVE_NAME="$APP_NAME-$SHORT_VERSION.zip"
ARCHIVE_PATH="$RELEASE_DIR/$ARCHIVE_NAME"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"

mkdir -p "$RELEASE_DIR"
log "Creating archive: $ARCHIVE_PATH"
rm -f "$ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

log "Generating appcast..."
"$SPARKLE_BIN/generate_appcast" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --release-notes-url-prefix "$RELEASE_NOTES_URL_PREFIX" \
  --link "$PRODUCT_LINK" \
  -o "$APPCAST_PATH" \
  "$RELEASE_DIR"

if [[ "$PUBLISH" -eq 1 ]]; then
  REMOTE_URL="$(git remote get-url "$REMOTE_NAME" 2>/dev/null || true)"
  [[ -n "$REMOTE_URL" ]] || fail "Git remote '$REMOTE_NAME' not found"

  TEMP_PUBLISH_DIR="$(mktemp -d -t "${APP_NAME}-gh-pages-XXXX")"
  cleanup() {
    rm -rf "$TEMP_PUBLISH_DIR"
  }
  trap cleanup EXIT

  log "Publishing artifacts to $REMOTE_NAME/$PAGES_BRANCH..."
  git clone --branch "$PAGES_BRANCH" --single-branch "$REMOTE_URL" "$TEMP_PUBLISH_DIR" >/dev/null

  rsync -a \
    --include='*/' \
    --include='*.xml' \
    --include='*.zip' \
    --include='*.delta' \
    --exclude='*' \
    "$RELEASE_DIR/" \
    "$TEMP_PUBLISH_DIR/"

  pushd "$TEMP_PUBLISH_DIR" >/dev/null
  git add -A
  if git diff --cached --quiet; then
    log "No changes to publish on $PAGES_BRANCH"
  else
    git commit -m "Publish Sparkle appcast $SHORT_VERSION"
    git push origin "$PAGES_BRANCH"
  fi
  popd >/dev/null
fi

log "Done."
log "Version: $SHORT_VERSION ($BUILD_VERSION)"
log "Archive: $ARCHIVE_PATH"
log "Appcast: $APPCAST_PATH"
log "Notarized: $([[ "$NOTARIZE" -eq 1 ]] && echo 'yes' || echo 'no (pass --notarize to enable)')"
if [[ "$KEY_UPDATED" -eq 1 ]]; then
  log "SUPublicEDKey was updated in $INFO_PLIST_PATH"
  log "Commit/push Info.plist on your app branch if this key rotation is intentional."
fi
log "Tip: backup private key -> \"$SPARKLE_BIN/generate_keys\" --account \"$SPARKLE_ACCOUNT\" -x \"$HOME/Documents/sparkle_private_key_backup.txt\""
