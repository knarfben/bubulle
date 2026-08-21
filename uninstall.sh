#!/bin/zsh
# Désélectionne, désactive, arrête le process, retire le bundle. Restaure
# AppleSelectedInputSources à l'état d'avant (le cycle complet est réversible, cf. research/02).
set -e
here=${0:a:h}

BUNDLE_ID="local.bubulle"
DEST="$HOME/Library/Input Methods/Bubulle.app"
BIN="$DEST/Contents/MacOS/Bubulle"

echo "== désélection / désactivation"
swift "$here/Scripts/tisctl.swift" deselect "$BUNDLE_ID" || true
swift "$here/Scripts/tisctl.swift" disable "$BUNDLE_ID" || true

echo "== arrêt du process"
pkill -f "$BIN" 2>/dev/null || true

echo "== retrait du bundle"
rm -rf "$DEST"

echo "Fait. AppleSelectedInputSources devrait être revenu à tes layouts normaux."
