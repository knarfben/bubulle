# Contexte — Bubulle

Glossaire du domaine. Pas de détails d'implémentation : les décisions vivent dans les tickets de [la carte](.scratch/bubulle/MAP.md).

## Bulle

La fenêtre au drapeau que Bubulle affiche. **Une seule à la fois**, jamais deux.

Elle a trois **modes**, qui disent d'où elle vient. Son apparence est strictement identique dans les trois — sinon on apprend à les distinguer, et l'illusion se fissure.

- **Mode langue** — née d'un changement d'input source. Elle *recouvre* le HUD système, qui apparaît au même endroit au même moment. C'est une contrainte dure : tant qu'il est dessous, elle ne bouge pas et ne part pas.
- **Mode focus** — née d'une prise de focus dans un champ texte. Elle ne recouvre rien : aucun HUD système n'apparaît à la prise de focus. Sa vie est un pur choix.
- **Mode invite** — née du retour de l'**invite** dans un terminal. Comme le mode focus, elle ne recouvre rien et n'a pas de plancher. C'est le seul mode qui ne naît pas d'un geste de l'utilisateur : entre sa frappe et la bulle, il y a la commande, qui peut durer.

## Invite

L'état d'un terminal prêt à recevoir la commande suivante : l'invite est écrite, le caret est
posé derrière, rien n'a encore été tapé. C'est ce qui fait naître une bulle en mode invite.

Ce n'est pas la frappe d'Entrée : entre les deux il y a la commande, qui peut durer. Et ce n'est
pas une position connue d'avance — un shell pose son caret **après** son invite, un TUI le ramène
au **début** de sa boîte de saisie vidée, dans la direction opposée. Le seul invariant est que le
caret **s'y immobilise**, à un endroit que la frappe seule n'explique pas : une autre ligne, ou
plus d'un caractère de là où il était au dernier acte.

## Parcage

L'endroit où un terminal laisse son caret pendant qu'une commande tourne : la marge gauche d'une
ligne neuve, où rien n'a encore été écrit. Le caret peut y rester des secondes, parfaitement
immobile — c'est ce qui le rend indiscernable d'une invite si on ne regarde que l'immobilité.

Un TUI n'en a pas : il vide sa boîte sur place et est prêt aussitôt. **Distinguer le parcage de
l'invite est tout le problème du mode invite**, et ce qui les sépare est la marge gauche, que
Bubulle apprend en regardant simplement le plus petit `x` que le caret ait pris.

## Source muette

Une source d'entrée pour laquelle Bubulle ne pose **aucune bulle**. Deux façons de le devenir : elle
n'est mappée vers aucun drapeau et sa langue primaire n'en désigne aucun non plus, ou elle est
déclarée muette explicitement.

Une source muette n'est pas une panne : en mode langue, le **HUD système** reprend simplement la
main avec ses deux lettres, exactement comme avant Bubulle. C'est le seul cas où on le laisse à
découvert, et c'est délibéré — mieux vaut son information juste qu'un glyphe de notre part qui ne dit
rien. Une bulle déjà à l'écran qui bascule vers une source muette disparaît **net**, sans fondu :
son drapeau est devenu faux, et le laisser s'effacer par-dessus le HUD système le masquerait.

## HUD système

La capsule translucide que macOS peint sous le caret au changement d'input source, avec les deux lettres de la langue (`US`, `FR`, `فا`). Dessinée par `CursorUIViewService`, elle vit 1,50 s. C'est ce que Bubulle recouvre — **jamais ce qu'il neutralise**.

## Plancher de recouvrement

La fenêtre de 1,5 s pendant laquelle une bulle en mode langue a le HUD système sous elle. Pendant le plancher, les gestes qui tueraient normalement la bulle sont ignorés — sinon les deux lettres réapparaissent à découvert.

La **perte de focus perce le plancher** : si on a quitté l'app, le HUD découvert n'est plus dans le champ de vision.

Le plancher est aussi la **portée exacte de l'indiscernabilité**. Tant qu'il court, la bulle doit être impossible à distinguer du HUD système, sous peine de laisser dépasser les deux lettres. Passé le plancher, le HUD système a disparu : il n'y a plus rien dont il faille être indiscernable, et la bulle peut rester — c'est précisément ce que Bubulle apporte de plus que le système, qui, lui, s'efface à 1,50 s qu'on ait tapé ou non.

## Rect du caret

La géométrie du curseur de texte, telle que l'app focalisée la déclare au canal `NSTextInputClient`/TSM. C'est le seul canal qui donne le caret dans *toutes* les apps, y compris Chrome et Electron, et il ne transporte jamais le contenu du champ — une géométrie, rien d'autre. C'est ce qui rend Bubulle utilisable dans un champ mot de passe sans compromis.

## Cadre gardé

La position d'écran où une bulle est peinte. **Fixe pour toute la vie de la bulle** : elle ne suit jamais le caret. Le HUD système ne bouge pas non plus une fois peint.

Il se dérive du rect du caret et de la **zone visible** de l'écran, par une formule mesurée contre le HUD système : une capsule de 29 × 22, posée 4,5 pt sous le caret, alignée sur son bord gauche, et tenue à 2,5 pt des bords de la zone visible.

## Zone visible

Le rectangle utile de l'**écran qui contient le caret** — son `visibleFrame` : ce qui reste une fois le Dock et la barre de menus retirés, jamais l'union des écrans.

C'est le référentiel du cadre gardé, et les trois bords ne s'y comportent pas pareil. À gauche et à droite, la capsule **clampe**. En bas, elle **bascule** au-dessus du caret — et si même là elle ne tient pas, elle clampe sur cette **butée basse**. En haut, rien ne la contraint : elle se pose par-dessus la barre de menus.

## Compteurs d'actes

Le nombre d'événements clavier, souris et molette de la session, relevé sans aucune permission. Bubulle les relève **à neuf à chaque fois qu'il pose une bulle**, et les compare pour savoir si l'utilisateur a agi depuis.

C'est ce qui remplace toute forme de timeout : une bulle ne meurt que d'un acte — frappe, clic, scroll — ou d'une perte de focus.

## Palette

La forme sous laquelle Bubulle s'installe : un bundle Input Method enregistré comme palette, sélectionné *en parallèle* des layouts de clavier. Elle ne voit jamais passer une touche et n'apparaît pas dans le menu des langues. C'est le seul moyen d'ouvrir le canal vers le rect du caret.
