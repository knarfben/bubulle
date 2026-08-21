#!/bin/zsh
# Compile, pose le bundle dans ~/Library/Input Methods/, l'enregistre et le sélectionne.
#
# L'ORDRE EST LA SEULE CHOSE QUI COMPTE ICI. Deux pièges, tous deux mesurés :
#   1. TISEnableInputSource doit être appelé AVANT de lancer le process. Il renvoie 0 et
#      semble ne rien faire (enabled reste false) — mais il arme une intention que le daemon
#      valide quand l'IMKServer du process fait sa poignée de main. Sans cet appel préalable,
#      le flip enabled=0->1 n'arrive JAMAIS, quelle que soit la durée d'attente. C'est
#      exactement la régression du ticket 09.
#   2. Le process doit tourner AVANT TISSelectInputSource, sinon -50 (paramErr).
# D'où l'ordre : copier, enregistrer, activer, lancer, attendre le flip, sélectionner.
set -e
here=${0:a:h}

BUNDLE_ID="local.bubulle"
DEST="$HOME/Library/Input Methods/Bubulle.app"
BIN="$DEST/Contents/MacOS/Bubulle"

echo "== build"
"$here/build.sh"

echo "== désélection/désactivation d'une éventuelle instance en cours"
# Si la source est encore selected au moment du pkill ci-dessous, le superviseur système
# (imklaunchagent) relance le process tout seul, en plus de la relance manuelle faite plus
# bas -> deux instances vivantes. Désélectionner/désactiver avant de tuer évite la relance
# système. Confirmé au ticket 15 : source encore sélectionnée + pkill = 2 instances à 100%
# (3/3), désélection avant pkill = 1 instance à 100% (5/5).
swift "$here/Scripts/tisctl.swift" deselect "$BUNDLE_ID" 2>/dev/null || true
swift "$here/Scripts/tisctl.swift" disable "$BUNDLE_ID" 2>/dev/null || true

echo "== arrêt d'une éventuelle instance en cours"
pkill -f "$BIN" 2>/dev/null || true
sleep 0.3

echo "== copie vers $DEST"
rm -rf "$DEST"
mkdir -p "$HOME/Library/Input Methods"
cp -R "$here/.build/Bubulle.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "== enregistrement TIS"
swift "$here/Scripts/tisctl.swift" register "$DEST"

echo "== activation (AVANT lancement — voir l'en-tête ; renvoie 0 sans effet visible)"
swift "$here/Scripts/tisctl.swift" enable "$BUNDLE_ID"

echo "== lancement (doit tourner avant la sélection TIS)"
"$BIN" >/dev/null 2>&1 &
disown
sleep 1

echo "== attente de l'auto-enable"
swift "$here/Scripts/tisctl.swift" wait-enabled "$BUNDLE_ID"

echo "== sélection"
swift "$here/Scripts/tisctl.swift" select "$BUNDLE_ID"

echo
echo "Bubulle est actif. Tes layouts (US, French, SCIM, Persan) ne sont pas touchés :"
echo "la palette se sélectionne en parallèle, pas à leur place."
echo
echo "Vérifier :  tail -f /tmp/bubulle.log"
echo "Désinstaller :  ./uninstall.sh"
