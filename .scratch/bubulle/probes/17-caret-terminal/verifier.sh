#!/bin/zsh
# Vérification du mode invite (ticket 17).
#
# GARDE-FOUS — ce script poste de vraies frappes clavier : elles vont dans la fenêtre qui a le
# focus, quelle qu'elle soit. Une version antérieure a tapé dans une session Claude Code parce que
# le ⌘N n'avait pas ouvert de fenêtre. Il ne tape donc RIEN tant qu'il n'a pas prouvé les trois :
#   1. un id de fenêtre Ghostty est apparu qui n'existait pas avant le ⌘N ;
#   2. la fenêtre focalisée est bien celle-là (position identique) ;
#   3. son titre ne ressemble pas à une session Claude Code.
# Sinon il abandonne sans rien taper.
#
# Trois cas, échantillonnés toutes les 100 ms :
#   A. `sleep 2` : bulle ABSENTE ~2 s (le caret est parqué en colonne 0) puis PRÉSENTE à l'invite.
#      C'est le test qui distingue « posée au retour de l'invite » de « posée à Entrée ».
#   B. `ls`      : commande rapide. Ici la visibilité ne prouve rien — la bulle est re-posée
#      avant que la précédente ait fini son fondu, donc elle ne disparaît jamais. On compare donc
#      les POSITIONS : elle doit avoir été re-posée sur la nouvelle ligne d'invite.
#   C. frappe sans Entrée puis pause : la bulle doit rester ABSENTE.
#
# Ne touche ni clavier ni souris pendant les ~25 s que ça dure.
setopt extended_glob
here=${0:a:h}
PID=$(pgrep -f 'Input Methods/Bubulle.app') || { echo "Bubulle ne tourne pas"; exit 2 }
[[ -x $here/bubblewatch ]] || swiftc -O -o $here/bubblewatch $here/bubblewatch.swift
[[ -x $here/frappe ]] || swiftc -O -o $here/frappe $here/frappe.swift

# Les ids de fenêtre viennent de CGWindowList, pas d'AX : l'énumération AX ne rend que les
# fenêtres du Space courant et renvoie parfois 0, ce qui donnait de faux « aucune fenêtre neuve ».
fenetres() { $here/wins-ghostty }

titre_focalise() {
  osascript -e 'tell application "System Events" to tell process "ghostty" to get name of value of attribute "AXFocusedWindow"' 2>/dev/null
}

[[ -x $here/wins-ghostty ]] || swiftc -O -o $here/wins-ghostty $here/wins-ghostty.swift

avant=$(fenetres)
open -a Ghostty; sleep 1.2          # SANS -n : active l'instance en cours, n'en crée pas une
# ⌘N par System Events : un CGEvent avec .maskCommand ne déclenche rien dans Ghostty (mesuré).
osascript -e 'tell application "System Events" to keystroke "n" using command down' >/dev/null 2>&1
sleep 2.0
neuve=$(comm -13 <(print -r -- "$avant") <(print -r -- "$(fenetres)") | head -1)
[[ -n "$neuve" ]] || { echo "ABANDON : le ⌘N n'a ouvert aucune fenêtre. Rien tapé."; exit 3 }

focalisee=$(titre_focalise)
[[ -n "$focalisee" ]] || { echo "ABANDON : impossible de lire la fenêtre focalisée. Rien tapé."; exit 3 }
[[ "$focalisee" != *[Cc]laude* ]] || { echo "ABANDON : la fenêtre focalisée est une session Claude Code ($focalisee). Rien tapé."; exit 3 }
echo "fenêtre d'essai : id $neuve, titre « $focalisee »"

chrono() {  # une ligne de V (visible) / . (absente), un caractère par 100 ms
  local n=$1 out=""
  for i in $(seq 1 $n); do
    case "$($here/bubblewatch $PID)" in VISIBLE*) out="$out"V ;; *) out="$out." ;; esac
    sleep 0.1
  done
  print -r -- "$out"
}

fail=0
verdict() { if [[ "$2" == ${~3} ]]; then echo "  OK   $1 : $2"; else echo "  RATÉ $1 : $2"; fail=1; fi }

echo "A. sleep 2 — absente pendant que la commande tourne, présente à l'invite"
$here/frappe "sleep 2" entree
# Tolère quelques V au départ : la bulle de la commande précédente finit son fondu.
# Seuil à 10 points d'absence et pas 15 : un échantillon coûte un fork de sonde, donc il dure un
# peu plus de 100 ms et le compte varie de ±2 d'une passe à l'autre. 10 (soit ~1,2 s) reste très
# au-dessus des deux modes d'échec qu'on veut rejeter — « posée à Entrée » et « posée sur le
# parcage » donnent l'un comme l'autre 0 à 2 points.
verdict "sleep 2" "$(chrono 35)" '*.(#c10,)V##'

sleep 1
echo "B. ls — re-posée sur la nouvelle ligne d'invite"
pos() { $here/bubblewatch $PID | sed -n 's/.*\(x=[0-9.]* y=[0-9.]*\).*/\1/p' }
etat() { $here/bubblewatch $PID | cut -d' ' -f1 }
avant_b=$(pos)
$here/frappe "ls" entree; sleep 1.2
apres_b=$(pos); visible_b=$(etat)
if [[ "$visible_b" == VISIBLE && -n "$apres_b" && "$avant_b" != "$apres_b" ]]; then
  echo "  OK   ls : $avant_b -> $apres_b, à l'écran"
else
  echo "  RATÉ ls : $avant_b -> $apres_b ($visible_b)"; fail=1
fi

sleep 1
echo "C. frappe sans Entrée — doit rester absente"
$here/frappe "echo hello"
verdict "sans Entrée" "$(chrono 12)" '*.(#c8,)'

$here/frappe "" entree; sleep 0.6; $here/frappe "exit" entree; sleep 1
[ $fail -eq 0 ] && echo "VERT" || echo "ROUGE"
exit $fail
