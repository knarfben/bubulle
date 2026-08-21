# Sonde #16 — la bulle ne s'affiche pas en bascule de focus

Boucle de repro / régression du [ticket 16](../../tickets/16-bulle-absente-en-bascule-de-focus.md).

## Lancer

```
./repro.sh axraise   # bascule de focus pure, sans acte
./repro.sh clic      # geste réel : vrai clic posté en CGEvent
```

Les binaires (`bubblewatch`, `clic`) sont recompilés à la volée s'ils manquent.

**Prérequis** : deux fenêtres Ghostty côte à côte, l'une à `x=0`, l'autre à `x=843` (les deux seules
`AXStandardWindow` que `raise.scpt` sait viser) ; Bubulle installé et sélectionné.

## Ce que ça mesure

`bubblewatch.swift` lit `CGWindowListCopyWindowInfo(.optionAll)` et filtre sur le pid du process
Bubulle. `owner`, `bounds`, `alpha` et `isOnscreen` ne réclament **aucune permission** — seuls les
titres de fenêtre exigeraient Screen Recording, et on n'en a pas besoin.

Chaque bascule est échantillonnée à 0,15 / 0,30 / 0,55 / 0,85 s. Quatre `V` = la bulle est restée à
l'écran ; un `.` = elle en est sortie. L'échantillonnage dans le temps est ce qui distingue
« jamais posée » de « posée puis retirée » — c'est ce qui a nommé le bug.

## Signal clé

Sur le binaire buggé, la bulle avait la **bonne frame et alpha = 1** tout en étant **hors écran**.
Donc pose correcte puis retrait, jamais un échec de résolution du rect du caret. Le mode `clic`
compte autant que `axraise` : le clic incrémente les compteurs d'actes du
[#04](../../tickets/04-detecter-la-premiere-frappe.md), donc le fondu de sortie part *avant* le
`deactivateServer:` — même course, chemin d'entrée différent.

## Flake attribué, pas subi

La boucle flakait à ~1 passe sur 5, avec un motif **distinct** de celui du bug : `V V V .` et
`alpha = 0` (bulle posée puis fondue normalement) contre `. . . .` et `alpha = 1` (bulle posée puis
retirée d'un coup). Cause : un acte externe pendant les ~12 s de la boucle. `bubblewatch` rend donc
aussi les compteurs d'actes, et `repro.sh` **annule** une bascule pendant laquelle ils bougent au
lieu de la compter en échec. Ne touche ni clavier ni souris pendant une passe.

## Piège

`tell application "System Events" to click at {x, y}` ne produit **aucun événement** ici : la boucle
passait au vert sans que rien ne se soit produit, la bulle observée étant celle d'avant. D'où
`clic.swift`, qui poste un vrai `CGEvent`. La boucle vérifie en plus que la frame suit la fenêtre
visée — un vert sur une frame qui ne bouge pas est un faux vert.
