#!/bin/zsh
# Vérification manuelle du cas TUI (mode invite, branche « même ligne »). Hors du verifier.sh :
# ça lance une vraie session Claude Code et consomme un prompt, on ne le fait pas à chaque passe.
# Attendu : à la validation du prompt, la boîte se vide SUR LA MÊME LIGNE et la bulle se pose
# aussitôt — pas de position de parcage à attendre, contrairement au shell.
setopt extended_glob
here=${0:a:h}
PID=$(pgrep -f 'Input Methods/Bubulle.app') || { echo "Bubulle ne tourne pas"; exit 2 }
[[ -x $here/bubblewatch ]] || swiftc -O -o $here/bubblewatch $here/bubblewatch.swift
[[ -x $here/frappe ]] || swiftc -O -o $here/frappe $here/frappe.swift
[[ -x $here/wins-ghostty ]] || swiftc -O -o $here/wins-ghostty $here/wins-ghostty.swift

avant=$($here/wins-ghostty)
open -a Ghostty; sleep 1.2
osascript -e 'tell application "System Events" to keystroke "n" using command down' >/dev/null 2>&1
sleep 2
neuve=$(comm -13 <(print -r -- "$avant") <(print -r -- "$($here/wins-ghostty)") | head -1)
[[ -n "$neuve" ]] || { echo "ABANDON : aucune fenêtre neuve. Rien tapé."; exit 3 }
titre=$(osascript -e 'tell application "System Events" to tell process "ghostty" to get name of value of attribute "AXFocusedWindow"' 2>/dev/null)
[[ -n "$titre" && "$titre" != *[Cc]laude* ]] || { echo "ABANDON : fenêtre focalisée « $titre ». Rien tapé."; exit 3 }
echo "fenêtre d'essai : id $neuve, titre « $titre »"

pos() { $here/bubblewatch $PID | sed -n 's/.*\(x=[0-9.]* y=[0-9.]*\).*/\1/p' }
etat() { $here/bubblewatch $PID | cut -d' ' -f1 }

$here/frappe "cd ~/dev/streamlink/scripts/bubulle && claude" entree
sleep 16
titre2=$(osascript -e 'tell application "System Events" to tell process "ghostty" to get name of value of attribute "AXFocusedWindow"' 2>/dev/null)
echo "titre après lancement : « $titre2 »"
echo "avant le prompt : $(etat) $(pos)"
# prompt volontairement long : un prompt de 2 caractères ne recule le caret que de 18 pt au
# retour à la boîte vide, sous le seuil d'un caractère-et-demi. Cas limite réel, cf. NOTES.
$here/frappe "reponds uniquement le mot ok" entree
out=""
for i in $(seq 1 12); do
  case "$($here/bubblewatch $PID)" in VISIBLE*) out="$out"V ;; *) out="$out." ;; esac
  sleep 0.1
done
echo "après validation : $out   $(etat) $(pos)"
sleep 6
$here/frappe "/exit" entree; sleep 3; $here/frappe "exit" entree; sleep 1
