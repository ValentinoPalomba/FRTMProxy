#!/usr/bin/env bash
# publish_appcast_from_app.sh
#
# Given a pre-built (and optionally notarized) .app bundle:
#   1. Creates a signed .zip archive
#   2. Generates the Sparkle appcast.xml
#   3. Uploads the .zip to a GitHub Release (creates the release if missing)
#   4. Pushes appcast.xml to gh-pages
#
# GitHub Release upload uses the `gh` CLI if available, otherwise falls back
# to the GitHub REST API via `curl` (requires GITHUB_TOKEN env var).
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
PRODUCT_LINK="${PRODUCT_LINK:-https://github.com/ValentinoPalomba/FRTMProxy/releases}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"
RELEASE_NOTES_URL_PREFIX="${RELEASE_NOTES_URL_PREFIX:-}"
GH_REPO="${GH_REPO:-}"          # e.g. ValentinoPalomba/FRTMProxy (inferred from remote if empty)
GITHUB_TOKEN="${GITHUB_TOKEN:-}" # personal access token — needed only when gh CLI is absent
RELEASE_TAG="${RELEASE_TAG:-}"  # e.g. v1.6.0 (inferred from CFBundleShortVersionString if empty)
RELEASE_TITLE="${RELEASE_TITLE:-}"
RELEASE_NOTES="${RELEASE_NOTES:-}"

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
  --download-url-prefix <url>   Base URL for appcast enclosure download links
  --notes-url-prefix <url>      Base URL for release notes links in appcast
  --product-link <url>          Link in appcast item (default: GitHub releases page)
  --sparkle-account <name>      Keychain account for Sparkle signing key (default: ed25519)
  --remote <name>               Git remote (default: origin)
  --pages-branch <name>         Branch used for GitHub Pages (default: gh-pages)
  --gh-repo <owner/repo>        GitHub repo slug (inferred from remote URL if omitted)
  --tag <v1.2.3>                GitHub Release tag (default: v<CFBundleShortVersionString>)
  --title <string>              GitHub Release title (default: tag name)
  --notes <string>              GitHub Release body text
  --no-publish                  Generate zip + appcast locally only, skip all uploads
  -h, --help                    Show this help

Environment overrides:
  APP_NAME, RELEASE_DIR, REMOTE_NAME, PAGES_BRANCH, SPARKLE_ACCOUNT,
  PRODUCT_LINK, DOWNLOAD_URL_PREFIX, RELEASE_NOTES_URL_PREFIX,
  GH_REPO, RELEASE_TAG, RELEASE_TITLE, RELEASE_NOTES, GITHUB_TOKEN

GitHub Release upload priority:
  1. gh CLI  (if installed — no token needed, uses existing gh auth)
  2. curl + GITHUB_TOKEN  (fallback — set GITHUB_TOKEN env var)
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
    --download-url-prefix) DOWNLOAD_URL_PREFIX="$2";      shift 2 ;;
    --notes-url-prefix)    RELEASE_NOTES_URL_PREFIX="$2"; shift 2 ;;
    --product-link)        PRODUCT_LINK="$2";             shift 2 ;;
    --sparkle-account)     SPARKLE_ACCOUNT="$2";          shift 2 ;;
    --remote)              REMOTE_NAME="$2";              shift 2 ;;
    --pages-branch)        PAGES_BRANCH="$2";             shift 2 ;;
    --gh-repo)             GH_REPO="$2";                  shift 2 ;;
    --tag)                 RELEASE_TAG="$2";              shift 2 ;;
    --title)               RELEASE_TITLE="$2";            shift 2 ;;
    --notes)               RELEASE_NOTES="$2";            shift 2 ;;
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
command -v curl   >/dev/null || fail "curl not found"
[[ -x /usr/libexec/PlistBuddy ]] || fail "PlistBuddy not found"

# Detect which GitHub upload backend we'll use
USE_GH_CLI=0
if [[ "$PUBLISH" -eq 1 ]]; then
  if command -v gh >/dev/null 2>&1; then
    USE_GH_CLI=1
    log "GitHub upload backend: gh CLI"
  elif [[ -n "$GITHUB_TOKEN" ]]; then
    log "GitHub upload backend: curl + GITHUB_TOKEN"
  else
    fail "No GitHub upload backend found. Install gh CLI (brew install gh) or set GITHUB_TOKEN."
  fi
fi

# ── Read version from the app bundle ─────────────────────────────────────────
APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$APP_INFO_PLIST" ]] || fail "Info.plist not found inside $APP_PATH"

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_INFO_PLIST")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_INFO_PLIST" 2>/dev/null || echo "$SHORT_VERSION")"
[[ -n "$SHORT_VERSION" ]] || fail "CFBundleShortVersionString missing from $APP_INFO_PLIST"

log "App     : $APP_PATH"
log "Version : $SHORT_VERSION (build $BUILD_VERSION)"

# ── Infer download URL prefix from Info.plist SUFeedURL ──────────────────────
if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$ROOT_DIR/Info.plist" 2>/dev/null || true)"
  DOWNLOAD_URL_PREFIX="${FEED_URL%appcast.xml}"
fi
[[ -n "$DOWNLOAD_URL_PREFIX" ]] || \
  fail "Cannot infer --download-url-prefix (SUFeedURL missing from Info.plist — pass it explicitly)"

[[ -n "$RELEASE_NOTES_URL_PREFIX" ]] || RELEASE_NOTES_URL_PREFIX="$DOWNLOAD_URL_PREFIX"

# ── Derive tag, title, repo ───────────────────────────────────────────────────
[[ -n "$RELEASE_TAG" ]]   || RELEASE_TAG="v$SHORT_VERSION"
[[ -n "$RELEASE_TITLE" ]] || RELEASE_TITLE="$RELEASE_TAG"

if [[ "$PUBLISH" -eq 1 && -z "$GH_REPO" ]]; then
  REMOTE_URL="$(git remote get-url "$REMOTE_NAME" 2>/dev/null || true)"
  [[ -n "$REMOTE_URL" ]] || fail "Git remote '$REMOTE_NAME' not found and --gh-repo not set"
  GH_REPO="$(printf '%s' "$REMOTE_URL" \
    | sed -E 's|.*github\.com[:/]([^/]+/[^/]+?)(\.git)?$|\1|')"
  [[ -n "$GH_REPO" ]] || fail "Unable to infer GitHub repo from remote URL: $REMOTE_URL"
fi

# ── GitHub API helpers (curl fallback) ───────────────────────────────────────

# Returns the release id for a tag, or empty string if not found.
gh_api_get_release_id() {
  local tag="$1"
  curl -fsSL \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$GH_REPO/releases/tags/$tag" \
    2>/dev/null | grep '"id"' | head -1 | sed -E 's/.*"id": *([0-9]+).*/\1/' || true
}

# Creates a draft=false release and returns its id.
gh_api_create_release() {
  local tag="$1" title="$2" notes="$3"
  curl -fsSL \
    -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/$GH_REPO/releases" \
    -d "{\"tag_name\":\"$tag\",\"name\":\"$title\",\"body\":\"$notes\",\"draft\":false}" \
    | grep '"id"' | head -1 | sed -E 's/.*"id": *([0-9]+).*/\1/'
}

# Uploads an asset to an existing release, overwriting if a same-name asset exists.
gh_api_upload_asset() {
  local release_id="$1" file_path="$2" file_name="$3"

  # Delete existing asset with the same name to allow re-upload
  local existing_asset_id
  existing_asset_id="$(
    curl -fsSL \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$GH_REPO/releases/$release_id/assets" \
      2>/dev/null \
    | grep -A2 "\"name\": \"$file_name\"" \
    | grep '"id"' \
    | head -1 \
    | sed -E 's/.*"id": *([0-9]+).*/\1/' || true
  )"
  if [[ -n "$existing_asset_id" ]]; then
    log "Deleting existing asset $file_name (id $existing_asset_id)..."
    curl -fsSL -X DELETE \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$GH_REPO/releases/assets/$existing_asset_id" >/dev/null
  fi

  curl -fsSL \
    -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/zip" \
    --data-binary "@$file_path" \
    "https://uploads.github.com/repos/$GH_REPO/releases/$release_id/assets?name=$file_name" \
    >/dev/null
}

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

# ── Publish ───────────────────────────────────────────────────────────────────
if [[ "$PUBLISH" -eq 0 ]]; then
  log "Skipping publish (--no-publish)."
else

  # 1. Upload zip to GitHub Release ------------------------------------------
  log "Uploading $ARCHIVE_NAME to GitHub Release $RELEASE_TAG ($GH_REPO)..."

  if [[ "$USE_GH_CLI" -eq 1 ]]; then
    # ── gh CLI path ──────────────────────────────────────────────────────────
    if gh release view "$RELEASE_TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
      log "Release $RELEASE_TAG already exists — uploading asset..."
      gh release upload "$RELEASE_TAG" "$ARCHIVE_PATH" \
        --repo "$GH_REPO" \
        --clobber
    else
      log "Release $RELEASE_TAG not found — creating it..."
      GH_CREATE_ARGS=(
        release create "$RELEASE_TAG"
        --repo "$GH_REPO"
        --title "$RELEASE_TITLE"
        --notes "${RELEASE_NOTES:-}"
        "$ARCHIVE_PATH"
      )
      gh "${GH_CREATE_ARGS[@]}"
    fi

  else
    # ── curl + GITHUB_TOKEN path ─────────────────────────────────────────────
    RELEASE_ID="$(gh_api_get_release_id "$RELEASE_TAG")"

    if [[ -z "$RELEASE_ID" ]]; then
      log "Release $RELEASE_TAG not found — creating it..."
      RELEASE_ID="$(gh_api_create_release "$RELEASE_TAG" "$RELEASE_TITLE" "${RELEASE_NOTES:-}")"
      [[ -n "$RELEASE_ID" ]] || fail "Failed to create GitHub Release (check GITHUB_TOKEN permissions)"
      log "Release created (id $RELEASE_ID)"
    else
      log "Release $RELEASE_TAG already exists (id $RELEASE_ID) — uploading asset..."
    fi

    gh_api_upload_asset "$RELEASE_ID" "$ARCHIVE_PATH" "$ARCHIVE_NAME"
  fi

  log "GitHub Release: https://github.com/$GH_REPO/releases/tag/$RELEASE_TAG"

  # 2. Push appcast to gh-pages -----------------------------------------------
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
if [[ "$PUBLISH" -eq 1 ]]; then
  log "Release : https://github.com/$GH_REPO/releases/tag/$RELEASE_TAG"
  log "Feed    : ${DOWNLOAD_URL_PREFIX}appcast.xml"
fi
