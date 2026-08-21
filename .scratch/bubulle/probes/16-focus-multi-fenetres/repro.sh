#!/bin/zsh
# Repro/régression du ticket 16 — « une bulle sur deux ne s'affiche pas en bascule de focus ».
#
# Deux boucles, même assertion : après chaque bascule de focus entre deux fenêtres Ghostty,
# la bulle doit être À L'ÉCRAN (CGWindowListCopyWindowInfo sur le pid de Bubulle), échantillonnée
# à 0,15 / 0,30 / 0,55 / 0,85 s après la bascule.
#   - mode axraise : bascule par AXRaise (pas d'acte, isole la bascule de focus pure)
#   - mode clic    : bascule par un vrai clic CGEvent (geste réel, incrémente les compteurs #04)
#
# Une bascule pendant laquelle les compteurs d'actes bougent (hors du clic de la bascule elle-même)
# est ANNULÉE, pas comptée en échec : une frappe ou un scroll ailleurs dans la session ferme la
# bulle tout à fait légitimement, et confondre les deux rend le test flaky.
#
# Prérequis : deux fenêtres Ghostty côte à côte, l'une à x=0, l'autre à x=843 ; Bubulle installé
# et sélectionné, et on ne touche ni clavier ni souris pendant les ~12 s que dure la boucle.
# Rouge sur le binaire d'avant le correctif, vert après (vérifié dans les deux sens).
set -e
here=${0:a:h}
mode=${1:-axraise}
PID=$(pgrep -f 'Input Methods/Bubulle.app') || { echo "Bubulle ne tourne pas"; exit 2 }

[[ -x $here/bubblewatch ]] || swiftc -O -o $here/bubblewatch $here/bubblewatch.swift
[[ -x $here/clic ]] || swiftc -O -o $here/clic $here/clic.swift

bascule() {  # $1 = axraise|clic, $2 = x de la fenêtre
  if [[ $1 == clic ]]; then
    [[ $2 == 0 ]] && $here/clic 400 600 || $here/clic 1200 600
  else
    osascript $here/raise.scpt $2 >/dev/null
  fi
}
actes() { $here/bubblewatch $PID | sed 's/.*actes=//' }

fail=0; annulees=0
bascule $mode 0; sleep 1.2
for x in 843 0 843 0; do
  bascule $mode $x
  a0=$(actes)          # après la bascule : inclut déjà le clic de la bascule en mode clic
  line=""
  for d in 0.15 0.15 0.25 0.30; do
    sleep $d
    o=$($here/bubblewatch $PID)
    case "$o" in VISIBLE*) line="$line V" ;; HORS*) line="$line ." ;; *) line="$line ?" ;; esac
  done
  a1=$(actes)
  if [[ "$a0" != "$a1" ]]; then
    echo "[$mode] fenêtre x=$x :$line   ANNULÉE (acte externe pendant la mesure : $a0 -> $a1)"
    annulees=$((annulees + 1))
  else
    echo "[$mode] fenêtre x=$x :$line   ($o)"
    [[ "$line" == *"."* || "$line" == *"?"* ]] && fail=1
  fi
  sleep 0.5
done
[[ $annulees -ge 3 ]] && { echo "NON CONCLUANT — $annulees bascules sur 4 annulées, ne touche pas clavier/souris"; exit 3 }
[ $fail -eq 0 ] && echo "VERT ($annulees annulée(s))" || echo "ROUGE (V=à l'écran, .=hors écran)"
exit $fail
