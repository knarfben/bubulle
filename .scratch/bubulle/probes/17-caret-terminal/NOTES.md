# Sonde #17 — le rect du caret dans un terminal

Mesure du 2026-08-21 qui a fondé le déclencheur du
[ticket 17](../../tickets/17-retour-de-l-invite.md). Machine : macOS 26.6.2, Ghostty
`com.mitchellh.ghostty`, invite de 24 colonnes de 9 pt.

## Contenu

| | quoi |
| --- | --- |
| `verifier.sh` | harnais de régression du mode invite — trois cas, rouge/vert |
| `tui.sh` | vérification du cas TUI, à part : consomme un vrai prompt Claude Code |
| `batterie.sh` + `sonde-caret.swift.txt` | la mesure d'origine, qui a fondé le déclencheur |
| `frappe.swift`, `bubblewatch.swift`, `wins-ghostty.swift` | outillage |

## Garde-fous du harnais

`verifier.sh` poste de **vraies frappes clavier** : elles vont dans la fenêtre focalisée, quelle
qu'elle soit. Une version antérieure a tapé dans une session Claude Code parce que le ⌘N n'avait
pas ouvert de fenêtre. Il ne tape donc plus rien tant qu'il n'a pas prouvé les trois :

1. un id de fenêtre Ghostty est apparu qui n'existait pas avant le ⌘N ;
2. la fenêtre focalisée est lisible ;
3. son titre ne ressemble pas à une session Claude Code.

Sinon il abandonne sans rien taper. Deux pièges qui ont mené là :

- **⌘N par `CGEvent` avec `.maskCommand` ne déclenche rien dans Ghostty.** Il faut
  `tell application "System Events" to keystroke "n" using command down`. (À l'inverse, les frappes
  de texte ordinaires passent en `CGEvent` et **pas** par `click at`, cf. #16 — les deux mécanismes
  ne se recouvrent pas.)
- **L'énumération AX des fenêtres ne rend que le Space courant** et renvoie parfois zéro, d'où de
  faux « aucune fenêtre neuve ». Les ids viennent donc de `CGWindowList` ; AX ne sert qu'à lire le
  titre focalisé.

## Rejouer

Poser le patch de `sonde-caret.swift.txt` dans `Sources/BubbleStateMachine.swift`, reconstruire,
mettre une fenêtre de terminal au premier plan, puis `./batterie.sh`.

**Réinstaller sans la modale** : `install.sh` rappelle `TISEnableInputSource`, ce qui refait
apparaître « Allow "swift-frontend" to enable "Bubulle"? » à chaque rebuild (signature ad-hoc
différente à chaque compilation). Pour une simple itération de sonde, il suffit de remplacer le
binaire dans le bundle installé, de tuer le process et de le relancer à la main — la source reste
`enabled` et `selected`, aucune modale :

```
./build.sh && cp -f .build/Bubulle.app/Contents/MacOS/Bubulle \
    "$HOME/Library/Input Methods/Bubulle.app/Contents/MacOS/Bubulle"
pkill -f 'Input Methods/Bubulle.app'
"$HOME/Library/Input Methods/Bubulle.app/Contents/MacOS/Bubulle" >/dev/null 2>&1 &
```

Le superviseur `imklaunchagent` ne relance **pas** le process dans ce cas — contrairement au
scénario du [#15](../../tickets/15-double-instance-palette.md), où c'était la source encore
sélectionnée *au moment du pkill* qui le réveillait. Ici, relance manuelle obligatoire.

## Ce qu'elle mesure

Le rect du caret **et** les compteurs d'actes du [#04](../../tickets/04-detecter-la-premiere-frappe.md),
échantillonnés à 60 Hz, journalisés seulement quand l'un des deux change. C'est leur mise en
regard qui porte toute l'information : un déplacement du caret **à compteur inchangé** est un
déplacement que l'utilisateur n'a pas causé — donc l'app qui redessine.

## Résultats

**Ghostty suit son curseur en temps réel.** Le rect bouge sans aucune frappe, 3 s après Entrée :

```
12:11:22  x=1227.5  actes=57288   fin de la frappe « sleep 3 »
12:11:22  x= 876.5  actes=57289   Entrée : colonne 0, ligne suivante
12:11:25  x=1164.5  actes=57289   3 s plus tard, MÊME compteur : l'invite revient
```

C'est l'inverse d'iTerm2, qui rendait `(0,0,0,0)` jusqu'à une vraie frappe
([recherche 03](../../research/03-focus-dun-champ-texte.md), ligne 74). **iTerm2 reste à mesurer**
avant de le mettre dans la liste blanche.

**Le shell et le TUI se déplacent en sens opposés.** Trois commandes, `x` puis `actes` :

| commande | avant Entrée | à Entrée | prêt |
| --- | --- | --- | --- |
| `echo hi` | 285,5 · 57302 | 6,5 · 57302 | **222,5 · 57302** |
| `ls` | 240,5 · 57304 | 6,5 · 57305 | **222,5 · 57305** |
| `sleep 2` | 285,5 · 57312 | 6,5 · 57313 | **222,5 · 57313** (2 s plus tard) |
| TUI Claude Code | 132,5 · 57372 | — | **24,5 · 57372** |

`x=6,5` est la colonne 0, `x=222,5` la position après l'invite. Dans le shell, l'invite prête est
un déplacement **vers la droite** ; dans le TUI, la boîte se vide et le caret revient **vers la
gauche**, et c'est déjà l'état prêt. Aucune règle fondée sur la direction ne couvre les deux.

Ce qu'ils ont en commun : la position prête est celle où le caret **s'immobilise** après un
déplacement à compteur d'actes inchangé.

**Le cadre gardé ne coûte rien dans le TUI.** Pendant 15 s de streaming de Claude Code, le rect
n'a pas bougé d'un point : la boîte de saisie est ancrée en bas et la sortie défile au-dessus.

## Pièges rencontrés

- `open -na Ghostty` force une **nouvelle instance de l'app**, pas une nouvelle fenêtre, et
  Ghostty y restaure ses fenêtres : deux instances de trop et les fenêtres d'origine passées
  derrière, à tuer ensuite. Ouvrir la fenêtre d'essai à la main.
- `tell application "System Events" to click at {x, y}` ne produit **aucun événement** (piège déjà
  relevé au [#16](../../tickets/16-bulle-absente-en-bascule-de-focus.md)) ; `frappe.swift` poste
  de vrais `CGEvent`.
- Les deux fenêtres Ghostty de Frank font tourner des sessions Claude Code : ne pas y taper.
