#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-FRTMProxy}"
CASK_TOKEN="${CASK_TOKEN:-frtmproxy}"
SOURCE_REPO="${SOURCE_REPO:-ValentinoPalomba/FRTMProxy}"
TAP_REPO="${TAP_REPO:-ValentinoPalomba/homebrew-frtmtools}"
TAP_DIR="${TAP_DIR:-}"
VERSION="${VERSION:-}"
TAG="${TAG:-}"
ASSET_NAME="${ASSET_NAME:-}"
DOWNLOAD_URL="${DOWNLOAD_URL:-}"
COMMIT_CHANGES=0
PUSH_CHANGES=0
KEEP_CLONE=0

log() {
  printf '%s\n' "[brew-cask] $*"
}

fail() {
  printf '%s\n' "[brew-cask] ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/update_homebrew_cask.sh --version <x.y.z> [options]

Updates only:
  - version
  - sha256
  - url
in Casks/frtmproxy.rb (or a custom token).

Options:
  --version <x.y.z>            App version (required)
  --tag <vX.Y.Z>               GitHub release tag (default: v<version>)
  --asset-name <name.zip>      Release asset name (default: FRTMProxy-<version>.zip)
  --download-url <url>         Full asset URL (overrides repo/tag/asset-name composition)
  --source-repo <owner/repo>   Source repo containing releases (default: ValentinoPalomba/FRTMProxy)
  --tap-repo <owner/repo>      Homebrew tap repo (default: ValentinoPalomba/homebrew-frtmtools)
  --tap-dir <path>             Existing local tap checkout; if omitted, a temporary clone is used
  --cask-token <token>         Cask token (default: frtmproxy)
  --commit                     Commit the cask change in tap repo
  --push                       Push the commit (implies --commit)
  --keep-clone                 Keep temporary clone when --tap-dir is omitted
  -h, --help                   Show this help

Examples:
  ./scripts/update_homebrew_cask.sh --version 1.6.0 --tag v.1.6.0 --tap-dir ~/Repositories/homebrew-frtmtools
  ./scripts/update_homebrew_cask.sh --version 1.6.0 --tag v.1.6.0 --commit --push
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --asset-name)
      ASSET_NAME="$2"
      shift 2
      ;;
    --download-url)
      DOWNLOAD_URL="$2"
      shift 2
      ;;
    --source-repo)
      SOURCE_REPO="$2"
      shift 2
      ;;
    --tap-repo)
      TAP_REPO="$2"
      shift 2
      ;;
    --tap-dir)
      TAP_DIR="$2"
      shift 2
      ;;
    --cask-token)
      CASK_TOKEN="$2"
      shift 2
      ;;
    --commit)
      COMMIT_CHANGES=1
      shift
      ;;
    --push)
      COMMIT_CHANGES=1
      PUSH_CHANGES=1
      shift
      ;;
    --keep-clone)
      KEEP_CLONE=1
      shift
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

[[ -n "$VERSION" ]] || fail "--version is required"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail "Invalid --version value: $VERSION"

command -v curl >/dev/null || fail "curl not found"
command -v shasum >/dev/null || fail "shasum not found"
command -v git >/dev/null || fail "git not found"

if [[ -z "$TAG" ]]; then
  TAG="v$VERSION"
fi

if [[ -z "$ASSET_NAME" ]]; then
  ASSET_NAME="${APP_NAME}-${VERSION}.zip"
fi

if [[ -z "$DOWNLOAD_URL" ]]; then
  DOWNLOAD_URL="https://github.com/${SOURCE_REPO}/releases/download/${TAG}/${ASSET_NAME}"
fi

TEMP_DIR="$(mktemp -d -t "${CASK_TOKEN}-cask-update-XXXX")"
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

ZIP_PATH="$TEMP_DIR/$ASSET_NAME"
log "Downloading release asset..."
curl -fL --retry 3 --retry-delay 2 -o "$ZIP_PATH" "$DOWNLOAD_URL" >/dev/null
SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

WORK_TAP_DIR="$TAP_DIR"
CLONED_TAP=0
if [[ -z "$WORK_TAP_DIR" ]]; then
  WORK_TAP_DIR="$TEMP_DIR/homebrew-tap"
  log "Cloning tap: $TAP_REPO"
  git clone "https://github.com/${TAP_REPO}.git" "$WORK_TAP_DIR" >/dev/null
  CLONED_TAP=1
fi

[[ -d "$WORK_TAP_DIR/.git" ]] || fail "Tap directory is not a git repository: $WORK_TAP_DIR"

CASK_DIR="$WORK_TAP_DIR/Casks"
CASK_FILE="$CASK_DIR/${CASK_TOKEN}.rb"
mkdir -p "$CASK_DIR"

if [[ ! -f "$CASK_FILE" ]]; then
  log "Cask missing, creating template at: $CASK_FILE"
  cat >"$CASK_FILE" <<EOF
cask "${CASK_TOKEN}" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "${DOWNLOAD_URL}"
  name "${APP_NAME}"
  desc "Observe, understand, and shape HTTP/S traffic in real time"
  homepage "https://github.com/${SOURCE_REPO}"

  app "${APP_NAME}.app"

  depends_on macos: ">= :sonoma"
end
EOF
else
  log "Updating cask: $CASK_FILE"
  VERSION="$VERSION" perl -i '' -pe 's{^\s*version\s+"[^"]*"\s*$}{  version "$ENV{VERSION}"}' "$CASK_FILE"
  SHA256="$SHA256" perl -i '' -pe 's{^\s*sha256\s+"[^"]*"\s*$}{  sha256 "$ENV{SHA256}"}' "$CASK_FILE"
  DOWNLOAD_URL="$DOWNLOAD_URL" perl -i '' -pe 's{^\s*url\s+"[^"]*"\s*$}{  url "$ENV{DOWNLOAD_URL}"}' "$CASK_FILE"
fi

if ! grep -Fqx "  version \"$VERSION\"" "$CASK_FILE"; then
  fail "Failed to update version stanza in $CASK_FILE"
fi
if ! grep -Fqx "  sha256 \"$SHA256\"" "$CASK_FILE"; then
  fail "Failed to update sha256 stanza in $CASK_FILE"
fi
if ! grep -Fqx "  url \"$DOWNLOAD_URL\"" "$CASK_FILE"; then
  fail "Failed to update url stanza in $CASK_FILE"
fi

if [[ "$COMMIT_CHANGES" -eq 1 ]]; then
  git -C "$WORK_TAP_DIR" add "$CASK_FILE"
  if git -C "$WORK_TAP_DIR" diff --cached --quiet; then
    log "No cask changes to commit."
  else
    git -C "$WORK_TAP_DIR" commit -m "${CASK_TOKEN} ${VERSION}" >/dev/null
    log "Committed: ${CASK_TOKEN} ${VERSION}"
  fi
fi

if [[ "$PUSH_CHANGES" -eq 1 ]]; then
  git -C "$WORK_TAP_DIR" push origin HEAD >/dev/null
  log "Pushed to origin."
fi

log "Done."
log "Version : $VERSION"
log "Tag     : $TAG"
log "URL     : $DOWNLOAD_URL"
log "SHA256  : $SHA256"
log "Cask    : $CASK_FILE"

if [[ "$CLONED_TAP" -eq 1 ]]; then
  if [[ "$PUSH_CHANGES" -eq 1 && "$KEEP_CLONE" -eq 0 ]]; then
    log "Temporary tap clone will be removed."
  else
    trap - EXIT
    log "Temporary tap clone kept at: $WORK_TAP_DIR"
  fi
fi
