# Faire revenir la bulle au retour de l'invite

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:task`
Status: closed
Assignee: Frank (session wayfinder)
Blocked by: —

## Question

Dans un terminal, taper une commande tue la bulle à la première lettre — c'est la règle « la bulle
meurt d'un acte » du [#08](08-machine-a-etats-de-la-bulle.md), et elle est juste. Mais quand la
commande part et que l'invite revient, on est exactement dans la situation du **mode focus** : un
champ prêt, rien de tapé, et la question « dans quelle langue suis-je ? » qui se repose. Or il ne
se passe rien, parce qu'aucun `activateServer:` n'a lieu — le focus n'a pas changé.

Livrable : dans un terminal, la bulle revient sur la ligne de commande quand l'invite est prête à
recevoir, sans permission supplémentaire.

## Décisions

Prises en session de grilling, dans l'ordre où elles se sont résolues.

- **Instant** — la bulle revient **à l'arrivée de la nouvelle invite**, pas à la frappe d'Entrée.
  Pour un `sleep 10`, elle arrive 10 s après Entrée. C'est le sens littéral de « sur la ligne de
  commande » : l'endroit où on va taper la suite.
- **Canal** — on **guette le rect du caret** par le canal IMK déjà en place. Zéro permission, et ça
  marche sous secure input, donc à une invite `sudo` — le cas où le drapeau sert le plus. Écarté :
  un `CGEventTap` sur Entrée, qui coûte *Input Monitoring*, meurt sous secure input, et **ne dit de
  toute façon pas où poser** (voir la mesure).
- **Périmètre** — **terminaux seuls**, par liste blanche sur `bundleIdentifier()` (déjà exposé par
  le client IMK). Bubulle devient app-aware, ce qu'il n'était jamais — écart assumé au cadrage
  « périmètre = toutes les apps ». Discord et Slack ont le même besoin mais restent hors périmètre.
  *Révisé à l'implémentation* : la liste est **en dur et réduite à Ghostty**, pas un
  `Resources/terminals.json`. Frank n'utilise que Ghostty au quotidien, et iTerm2 demande une mesure
  (voir « Angles morts »), pas une ligne de configuration. Écrire le format avant d'avoir un
  deuxième cas, c'était payer pour une forme qu'on ne savait pas juste.
- **Déclencheur** — la bulle se pose quand le caret **s'immobilise à un endroit que la frappe seule
  n'explique pas**. Deux candidats successifs sont morts en route, chacun tué par une mesure :
  « la chute de `x` » (dans un shell, c'est le *départ* de la commande, pas le retour de l'invite),
  puis « l'immobilisation après un déplacement qu'aucun acte n'accompagne » — celle-là posait la
  bulle sur le **parcage**, la colonne 0 où un shell laisse son curseur pendant que la commande
  tourne, jusqu'à plusieurs secondes.
  *Forme finale, en deux branches*, sur la seule chose qui sépare le parcage de l'invite :
  - **Même ligne que l'ancre** — un TUI a vidé sa boîte sur place, c'est déjà l'état prêt. On pose
    si l'écart horizontal dépasse le seuil.
  - **Ligne différente** — un shell est passé à la ligne. On ne pose que si `x` dépasse la **marge
    gauche**, apprise comme le plus petit `x` vu depuis la prise de focus ; sinon c'est le parcage
    et on attend.

  Le seuil est la **hauteur du caret** : en chasse fixe un caractère fait environ la moitié d'une
  hauteur de ligne, donc « plus d'une hauteur » vaut « plus de deux caractères », et ça se met à
  l'échelle avec la police sans la connaître. C'est aussi ce qui fait qu'une frappe ordinaire ne
  déclenche jamais rien.
- **Bruit** — **une pose par armement** : un acte arme le guet, la pose désarme. Une bulle par
  commande, et rien pendant un `tail -f` qui défile.
- **Dérive** — la bulle **reste** où elle est si le caret s'éloigne ensuite. Le cadre gardé du
  [#11](11-offset-caret-capsule.md) n'est pas amendé — et la mesure montre qu'il ne coûte rien dans
  le TUI, où le caret ne bouge pas d'un point pendant le streaming.
- **Éclat** — elle **meurt à la frappe suivante comme partout ailleurs**, sans durée minimale de
  visibilité. Si on enchaîne vite, on ne la voit pas ; elle sert la pause, qui est le moment où on
  doute de sa langue. Aucun timer de vie réintroduit dans une machine qui n'en a plus.
- **Cadence** — un timer unique qui lit les compteurs d'actes *et* le rect du caret dès qu'un
  client de la liste blanche a le focus, coupé net à `deactivateServer:`.
  *Révisé à l'implémentation* : **60 Hz, pas 10**. Sur une commande rapide, la frappe d'Entrée, le
  passage en colonne 0 et l'écriture de l'invite tiennent dans **50 ms** — à 10 Hz ils tombent dans
  le même échantillon et l'ancre du déplacement serait fausse. Coût mesuré à ~0,3 % d'un cœur, et
  seulement quand Ghostty a le focus.
- **Vocabulaire** — c'est un **troisième mode**, le **mode invite**, à côté de langue et focus.
  Comme le mode focus il ne recouvre rien et n'a pas de plancher. Le signal porte son propre nom :
  un **déplacement spontané**. Posé dans [CONTEXT.md](../../../CONTEXT.md).

Trois points tranchés sans arbitrage, parce que les règles déjà écrites les forcent :

- Une **source muette** ne pose aucune bulle en mode invite non plus — la règle du
  [#13](13-repli-source-non-mappee.md) passe de « aucun des deux modes » à « aucun des trois ».
- Pendant le **plancher de recouvrement** d'une bulle en mode langue, le déclencheur invite est
  ignoré : reposer ailleurs découvrirait les deux lettres du HUD système, et le plancher est
  précisément la portée de l'indiscernabilité.
- La frappe d'Entrée ne peut pas tuer la bulle qu'elle fait naître : `pose()` relève
  `ActeCounters.now()` **au moment de la pose**, donc Entrée est déjà dans la ligne de base. Rien à
  ajouter.

## Mesure — le risque n°1 est levé

Détail complet dans [probes/17-caret-terminal](../probes/17-caret-terminal/NOTES.md).

Tout le dessin reposait sur une hypothèse invérifiable au dossier : Ghostty met-il son rect de
caret à jour en continu, ou seulement à la frappe suivante comme iTerm2 ? **Il le met à jour en
temps réel** — le rect bouge 3 s après Entrée à compteur d'actes identique.

La même mesure a invalidé le déclencheur pressenti et donné le bon :

| commande | avant Entrée | à Entrée | prêt |
| --- | --- | --- | --- |
| `echo hi` | 285,5 | 6,5 | **222,5** |
| `ls` | 240,5 | 6,5 | **222,5** |
| `sleep 2` | 285,5 | 6,5 | **222,5** (2 s plus tard) |
| TUI Claude Code | 132,5 | — | **24,5** |

`x=6,5` = colonne 0, `x=222,5` = après l'invite. Dans le shell l'état prêt est un déplacement vers
la **droite** ; dans le TUI, vers la **gauche**. Leur seul point commun est l'**immobilisation**.

## Vérification

Harnais dans [probes/17-caret-terminal](../probes/17-caret-terminal/NOTES.md) — `./verifier.sh`
ouvre une fenêtre Ghostty neuve, y joue trois cas et échantillonne la bulle toutes les 100 ms via
`CGWindowListCopyWindowInfo` sur le pid de Bubulle.

| cas | attendu | mesuré |
| --- | --- | --- |
| `sleep 2` | absente pendant que la commande tourne, présente à l'invite | 15 à 16 échantillons d'absence (~1,5 s) puis pose, sur 4 passes |
| `ls` | re-posée sur la nouvelle ligne d'invite | `y=100 -> y=140`, à l'écran |
| frappe sans Entrée | reste absente | `V...........` (le `V` est le fondu de la précédente) |

Le cas `sleep 2` est celui qui compte : c'est lui qui sépare « posée au retour de l'invite » de
« posée à Entrée », et il rejette aussi la version qui posait sur le parcage.

Sur `ls`, la visibilité ne prouve rien — la bulle est re-posée **avant** que la précédente ait fini
son fondu, donc elle ne disparaît jamais. D'où la comparaison de positions.

**Rougeur vérifiée** en vidant la liste blanche : les deux cas positifs virent au rouge, le cas
négatif reste vert (c'est normal, il affirme une absence). Vert 4 passes sur 4 avec la liste.

Le seuil du cas `sleep 2` est à 10 échantillons d'absence et non 15 : un échantillon coûte un fork
de sonde, donc il dure un peu plus de 100 ms et le compte varie de ±2 d'une passe à l'autre. 10
reste très au-dessus des deux modes d'échec à rejeter — « posée à Entrée » comme « posée sur le
parcage » donnent 0 à 2 échantillons.

Le **TUI de Claude Code** est vérifié à part (`./tui.sh`, qui consomme un vrai prompt et ne tourne
donc pas à chaque passe) : à la validation, `..VVVVVVVVVV` — la bulle se pose en 200 ms sur la
boîte de saisie vidée, par la branche « même ligne ».

## Angles morts

Tous du côté « pas de bulle », jamais « bulle au mauvais endroit » — c'est la bonne direction
d'échec, celle que le [#13](13-repli-source-non-mappee.md) a déjà choisie pour les sources muettes.

- **Un prompt très court dans un TUI.** Mesuré en essayant de valider `ok` : le retour à la boîte
  vide ne recule le caret que de 18 pt, sous le seuil de 20. Un prompt de longueur réelle passe.
- **La toute première commande d'une fenêtre**, si elle est assez rapide pour que la colonne 0 ne
  soit jamais échantillonnée : la marge gauche n'est pas encore connue. La commande suivante marche.
- **Un prompt multi-ligne validé dans un TUI** : la boîte se replie, donc ligne différente, et son
  bord gauche *est* à peu près la marge — la branche « ligne neuve » ne pose pas. Observé au
  lancement de `claude`, où la mise en place de la boîte ne pose rien non plus.
- **iTerm2 n'est pas mesuré.** La [recherche 03](../research/03-focus-dun-champ-texte.md) le donne
  muet jusqu'à une vraie frappe ; s'il l'est encore, le guet n'y verrait jamais rien. D'où la liste
  blanche réduite à Ghostty.

## Coûts assumés

- **~150 ms de latence** entre l'invite qui s'affiche et la bulle qui apparaît.
- Un **`tail -f` qui se tait** finit par poser une bulle — une seule, pas de clignotement, puisque
  l'armement est consommé.
- Le retour à la ligne automatique en tapant une commande plus large que la fenêtre **ne pose
  rien** : le caret y atterrit sur la marge gauche, donc sur un parcage. C'est un coût que le
  premier déclencheur imposait et que la forme finale supprime — comme elle supprime celui du
  Shift+Entrée dans un TUI.
- Un **collage** (⌘V) d'un texte long déplace le caret bien au-delà du seuil et peut poser une
  bulle. Elle meurt à la frappe suivante. Pas de contournement retenu.
