#!/usr/bin/env bash
# publish_appcast_from_app.sh
#
# Given a pre-built (and optionally notarized) .app bundle:
#   1. Creates a signed .zip archive (locally — upload to GitHub Releases manually)
#   2. Generates the Sparkle appcast.xml, with enclosure URLs pointing to
#      GitHub Releases: https://github.com/OWNER/REPO/releases/download/TAG/App-version.zip
#   3. Pushes only the appcast.xml to gh-pages
#
# Usage:
#   ./scripts/publish_appcast_from_app.sh /path/to/FRTMProxy.app [options]
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# ── Defaults (can be overridden via env or CLI flags) ────────────────────────
APP_NAME="${APP_NAME:-FRTMProxy}"
RELEASE_DIR="${RELEASE_DIR:-$HOME/releases/$APP_NAME}"
REMOTE_NAME="${REMOTE_NAME:-origin}"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-ed25519}"
PRODUCT_LINK="${PRODUCT_LINK:-}"          # inferred from GH_REPO if empty
GH_REPO="${GH_REPO:-}"                   # e.g. ValentinoPalomba/FRTMProxy — inferred from remote
RELEASE_TAG="${RELEASE_TAG:-}"           # e.g. v1.6.0 — inferred from version if empty
RELEASE_NOTES_URL_PREFIX="${RELEASE_NOTES_URL_PREFIX:-}"
# DOWNLOAD_URL_PREFIX is always auto-built from GH_REPO + RELEASE_TAG;
# override only if you host zips elsewhere.
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"

PUBLISH=1
APP_PATH=""

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { printf '%s\n' "[appcast] $*"; }
fail() { printf '%s\n' "[appcast] ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  ./scripts/publish_appcast_from_app.sh <path/to/App.app> [options]

Options:
  --release-dir <path>          Directory for the zip and appcast (default: ~/releases/APP_NAME)
  --gh-repo <owner/repo>        GitHub repo slug (inferred from git remote if omitted)
  --tag <v1.6.0>                GitHub Release tag (default: v<CFBundleShortVersionString>)
  --notes-url-prefix <url>      Base URL for release notes links in appcast
  --product-link <url>          Link in appcast item (default: GitHub releases page)
  --sparkle-account <name>      Keychain account for Sparkle signing key (default: ed25519)
  --remote <name>               Git remote (default: origin)
  --pages-branch <name>         Branch used for GitHub Pages (default: gh-pages)
  --no-publish                  Generate zip + appcast locally only, skip gh-pages push
  -h, --help                    Show this help

Environment overrides:
  APP_NAME, RELEASE_DIR, REMOTE_NAME, PAGES_BRANCH, SPARKLE_ACCOUNT,
  GH_REPO, RELEASE_TAG, PRODUCT_LINK, RELEASE_NOTES_URL_PREFIX,
  DOWNLOAD_URL_PREFIX (override only if zips are hosted outside GitHub Releases)

The zip enclosure URL in the appcast is automatically set to:
  https://github.com/<GH_REPO>/releases/download/<TAG>/<AppName-version.zip>

Remember to upload the generated zip to that GitHub Release manually (or via CI).
EOF
}

# ── Argument parsing ─────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

if [[ "${1:-}" != --* && "${1:-}" != -h ]]; then
  APP_PATH="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-dir)         RELEASE_DIR="$2";              shift 2 ;;
    --gh-repo)             GH_REPO="$2";                  shift 2 ;;
    --tag)                 RELEASE_TAG="$2";              shift 2 ;;
    --notes-url-prefix)    RELEASE_NOTES_URL_PREFIX="$2"; shift 2 ;;
    --product-link)        PRODUCT_LINK="$2";             shift 2 ;;
    --sparkle-account)     SPARKLE_ACCOUNT="$2";          shift 2 ;;
    --remote)              REMOTE_NAME="$2";              shift 2 ;;
    --pages-branch)        PAGES_BRANCH="$2";             shift 2 ;;
    --no-publish)          PUBLISH=0;                     shift   ;;
    -h|--help)             usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

# ── Validate inputs ──────────────────────────────────────────────────────────
[[ -n "$APP_PATH" ]]        || fail "No .app path provided. Run with --help for usage."
[[ -d "$APP_PATH" ]]        || fail ".app not found: $APP_PATH"
[[ "$APP_PATH" == *.app ]]  || fail "Path does not look like a .app bundle: $APP_PATH"

command -v ditto  >/dev/null || fail "ditto not found"
command -v git    >/dev/null || fail "git not found"
command -v rsync  >/dev/null || fail "rsync not found"
[[ -x /usr/libexec/PlistBuddy ]] || fail "PlistBuddy not found"

# ── Read version from the app bundle ─────────────────────────────────────────
APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$APP_INFO_PLIST" ]] || fail "Info.plist not found inside $APP_PATH"

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO_PLIST")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_INFO_PLIST" 2>/dev/null || echo "$SHORT_VERSION")"
[[ -n "$SHORT_VERSION" ]] || fail "CFBundleShortVersionString missing from $APP_INFO_PLIST"

log "App     : $APP_PATH"
log "Version : $SHORT_VERSION (build $BUILD_VERSION)"

# ── Infer GH_REPO from remote ─────────────────────────────────────────────────
if [[ -z "$GH_REPO" ]]; then
  REMOTE_URL="$(git remote get-url "$REMOTE_NAME" 2>/dev/null || true)"
  [[ -n "$REMOTE_URL" ]] || fail "Git remote '$REMOTE_NAME' not found and --gh-repo not set"
  GH_REPO="$(printf '%s' "$REMOTE_URL" \
    | sed -E 's|.*github\.com[:/]||' \
    | sed -E 's|\.git$||')"
  [[ -n "$GH_REPO" ]] || fail "Unable to infer GitHub repo from remote URL: $REMOTE_URL"
fi

# ── Derive tag and URLs ───────────────────────────────────────────────────────
[[ -n "$RELEASE_TAG" ]] || RELEASE_TAG="v$SHORT_VERSION"
[[ -n "$PRODUCT_LINK" ]] || PRODUCT_LINK="https://github.com/$GH_REPO/releases"

# Build the download prefix pointing to GitHub Releases — trailing slash required
# Result: https://github.com/Owner/Repo/releases/download/v1.6.0/
if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  DOWNLOAD_URL_PREFIX="https://github.com/$GH_REPO/releases/download/$RELEASE_TAG/"
fi

[[ -n "$RELEASE_NOTES_URL_PREFIX" ]] || RELEASE_NOTES_URL_PREFIX="$DOWNLOAD_URL_PREFIX"

log "Repo    : $GH_REPO"
log "Tag     : $RELEASE_TAG"
log "Zip URL : ${DOWNLOAD_URL_PREFIX}${APP_NAME}-${SHORT_VERSION}.zip"

# ── Find Sparkle tools ────────────────────────────────────────────────────────
find_sparkle_bin() {
  if [[ -n "${SPARKLE_BIN:-}" && -x "${SPARKLE_BIN}/generate_appcast" ]]; then
    printf '%s\n' "$SPARKLE_BIN"; return 0
  fi
  local pattern="$HOME/Library/Developer/Xcode/DerivedData/FRTMProxy-"'*/SourcePackages/artifacts/sparkle/Sparkle/bin'
  local candidate
  candidate="$(ls -dt $pattern 2>/dev/null | head -n1 || true)"
  if [[ -n "$candidate" && -x "$candidate/generate_appcast" ]]; then
    printf '%s\n' "$candidate"; return 0
  fi
  log "Sparkle tools not found in DerivedData. Resolving package dependencies..."
  xcodebuild -resolvePackageDependencies -project "$ROOT_DIR/FRTMProxy.xcodeproj" >/dev/null
  candidate="$(ls -dt $pattern 2>/dev/null | head -n1 || true)"
  if [[ -n "$candidate" && -x "$candidate/generate_appcast" ]]; then
    printf '%s\n' "$candidate"; return 0
  fi
  return 1
}

SPARKLE_BIN="$(find_sparkle_bin)" || \
  fail "Unable to locate Sparkle tools. Build the project once or set SPARKLE_BIN."
log "Sparkle : $SPARKLE_BIN"

# ── Create archive ────────────────────────────────────────────────────────────
ARCHIVE_NAME="$APP_NAME-$SHORT_VERSION.zip"
ARCHIVE_PATH="$RELEASE_DIR/$ARCHIVE_NAME"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"

mkdir -p "$RELEASE_DIR"
log "Creating archive: $ARCHIVE_PATH"
rm -f "$ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

# ── Generate appcast ──────────────────────────────────────────────────────────
log "Generating appcast..."
"$SPARKLE_BIN/generate_appcast" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --release-notes-url-prefix "$RELEASE_NOTES_URL_PREFIX" \
  --link "$PRODUCT_LINK" \
  -o "$APPCAST_PATH" \
  "$RELEASE_DIR"
log "Appcast : $APPCAST_PATH"

# ── Push appcast to gh-pages (zip stays local — upload to GH Release manually) ──
if [[ "$PUBLISH" -eq 0 ]]; then
  log "Skipping publish (--no-publish)."
else
  REMOTE_URL="$(git remote get-url "$REMOTE_NAME" 2>/dev/null || true)"
  [[ -n "$REMOTE_URL" ]] || fail "Git remote '$REMOTE_NAME' not found"

  TEMP_PUBLISH_DIR="$(mktemp -d -t "${APP_NAME}-gh-pages-XXXX")"
  cleanup() { rm -rf "$TEMP_PUBLISH_DIR"; }
  trap cleanup EXIT

  log "Publishing appcast to $REMOTE_NAME/$PAGES_BRANCH..."
  git clone --branch "$PAGES_BRANCH" --single-branch "$REMOTE_URL" "$TEMP_PUBLISH_DIR" >/dev/null

  rsync -a \
    --include='*/' \
    --include='*.xml' \
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
    log "Appcast pushed to $PAGES_BRANCH"
  fi
  popd >/dev/null
fi

# ── Summary ───────────────────────────────────────────────────────────────────
log "────────────────────────────────"
log "Done."
log "Version : $SHORT_VERSION (build $BUILD_VERSION)"
log "Archive : $ARCHIVE_PATH"
log "Appcast : $APPCAST_PATH"
log ""
log "Next step: upload the zip to the GitHub Release manually:"
log "  https://github.com/$GH_REPO/releases/tag/$RELEASE_TAG"
