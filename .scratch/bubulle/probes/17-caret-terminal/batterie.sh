#!/bin/zsh
# Batterie de mesure du ticket 17 : le rect du caret suit-il le curseur du terminal, et quelle
# est la signature du retour de l'invite ?
#
# Prérequis : le patch de `sonde-caret.swift.txt` posé dans le binaire installé, et une fenêtre
# de terminal AU PREMIER PLAN avec un shell — les frappes vont là où est le focus.
#
# ⚠ N'utilise PAS `open -na Ghostty` pour ouvrir cette fenêtre : `-n` force une **nouvelle
# instance de l'app**, pas une nouvelle fenêtre, et Ghostty y restaure ses fenêtres — on se
# retrouve avec plusieurs instances et les fenêtres d'origine passées derrière. Ouvre la fenêtre
# à la main (⌘N), ou accepte de tuer l'instance en trop ensuite.
here=${0:a:h}
[[ -x $here/frappe ]] || swiftc -O -o $here/frappe $here/frappe.swift

marque() { echo "[$(date '+%Y-%m-%d %H:%M:%S') +0000] >>>>> MARQUE $1" >> /tmp/bubulle.log }

: >| /tmp/bubulle.log
marque "invite initiale"; sleep 0.5
marque "echo hi";  $here/frappe "echo hi" entree;  sleep 2
marque "ls";       $here/frappe "ls" entree;       sleep 2
marque "sleep 2";  $here/frappe "sleep 2" entree;  sleep 4
marque "FIN"
sed 's/ +0000//;s/\[DEBUG-c7e1\] //' /tmp/bubulle.log | grep -v deactivate
