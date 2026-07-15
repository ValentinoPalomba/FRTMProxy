#!/usr/bin/env bash
#
# Cattura gli screenshot dell'app via XCUITest (scheme FRTMProxyScreenshots).
# Bypassa i permessi Screen Recording/Accessibility: usa l'automazione di XCTest.
#
# ATTENZIONE: richiede una sessione GUI attiva. Il test prende il controllo di
# schermo/mouse per ~1-2 minuti — non toccare tastiera e mouse durante l'esecuzione.
#
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO/.media"
SHOTS="${FRTM_SHOT_DIR:-$HOME/frtm-shots}"

echo "==> Chiudo eventuali istanze di FRTMProxy (evita conflitti su porta 8080 / doppia istanza)…"
osascript -e 'quit app "FRTMProxy"' >/dev/null 2>&1 || true
sleep 1

echo "==> Eseguo gli UI test (non toccare tastiera/mouse)…"
xcodebuild test \
  -scheme FRTMProxyScreenshots \
  -destination 'platform=macOS' \
  -derivedDataPath "$REPO/.build" || true

if compgen -G "$SHOTS/*.png" >/dev/null; then
  echo "==> Copio gli screenshot in .media/…"
  cp -f "$SHOTS"/*.png "$DEST"/
  ls -1 "$DEST"/*.png
else
  echo "!! Nessuno screenshot trovato in $SHOTS — controlla il log del test qui sopra."
  exit 1
fi
