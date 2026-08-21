# Machine à états de la bulle

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:grilling`
Status: closed
Assignee: Frank
Blocked by: —

## Question

Une fois connus les signaux réellement disponibles, quelle est la machine à états exacte de la bulle ?

À trancher avec Frank, en `/grilling` + `/domain-modeling` :

- Les états (cachée, affichée-suite-à-changement-de-langue, affichée-suite-à-focus, en-fondu) et les transitions.
- Priorité et courses entre triggers : changement de langue **pendant** qu'une bulle de focus est affichée ; focus sur un autre champ pendant l'affichage ; changement de langue sans champ actif du tout (faut-il afficher quelque chose ?).
- Valeur du timeout de sécurité, et si elle diffère selon le trigger. **Sa justification d'origine a sauté** : la recherche sur la détection de frappe montre que le compteur d'événements voit les frappes même en secure input, donc le timeout n'est plus un filet anti-blocage pour les champs mot de passe. Reste à décider s'il garde une raison d'être (perte de focus non détectée, app qui n'expose rien) ou s'il disparaît.
- Que fait-on quand la position n'est pas connue de façon fiable pour le trigger focus : repli souris, dernière position connue, ou pas d'affichage du tout — décision que la couverture réelle mesurée dans le ticket focus rendra concrète.
- Ce qui se passe au changement d'écran, de Space, ou en plein écran.
- **Valeurs déjà acquises au prototype**, à intégrer sans les re-discuter : niveau de fenêtre bas (≤ `statusBar`, 25) ; durées d'animation à rallonger vers ~0,25 s à l'entrée et ~0,40 s à la sortie.
- **Règle de stabilisation du cadre** (soulevée par la recherche sur le HUD) : la rafale `SLSGetWindowBounds` voit passer plusieurs valeurs. Déclencher trop tôt afficherait la bulle à la position de parking de la fenêtre. Deux événements quand le caret a bougé, un seul sinon — à régler, sachant qu'il n'y a que 17-18 ms de marge.
- **Cadence de sondage du caret** : le canal IMK est *pull*, aucune notification quand le caret bouge. À quelle fréquence ré-interroger pour que la bulle ne traîne pas, sans marteler l'app focalisée ?

Livrable : la machine à états écrite noir sur blanc, et le vocabulaire du domaine posé — c'est ce qui débloque l'implémentation.

## Comments

**La machine à états est arrêtée**, en `/grilling` + `/domain-modeling` avec Frank. Onze décisions.

Le fait marquant : **trois des points du ticket ont disparu au lieu d'être tranchés**, dissous par les décisions amont. La règle de stabilisation du cadre, la cadence de sondage du caret et le timeout de sécurité n'existent plus comme questions.

### Vocabulaire du domaine

| Terme | Définition |
|---|---|
| **Bulle** | La fenêtre au drapeau. **Une seule à la fois**, jamais deux. |
| **Mode langue** / **mode focus** | La provenance de la bulle. Apparence strictement identique — sinon on apprend à les distinguer et l'illusion se fissure — mais règles de vie différentes. |
| **Plancher de recouvrement** | Les 1,5 s pendant lesquelles une bulle en mode langue a le HUD système sous elle. |
| **Rect du caret** | `attributesForCharacterIndex:0 lineHeightRectangle:` du client IMK, en coordonnées écran Cocoa. |
| **Cadre gardé** | La position d'écran où la bulle est peinte. **Fixe pour toute sa vie.** |
| **Compteurs d'actes** | `CGEventSourceCounterForEventType(.combinedSessionState, …)` sur `keyDown`, `mouseDown`, `scrollWheel`. Relevés **à neuf à chaque pose**, comparés à 60 Hz. |

Glossaire tenu à part dans [CONTEXT.md](../../../CONTEXT.md).

### États

- **`Repos`** — aucune bulle, aucun timer. On écoute la notif TIS et `activateServer:`.
- **`Placement`** — transitoire : on interroge le rect du caret.
- **`Recouvrement`** — mode langue, plancher en cours (≤ 1,5 s).
- **`Affichée`** — règles normales.
- **`Sortie`** — fondu ~0,40 s.

### Transitions

| Depuis | Événement | Vers |
|---|---|---|
| `Repos` | notif `kTISNotifySelectedKeyboardInputSourceChanged` | `Placement` (mode langue) |
| `Repos` | `activateServer:` avec client valide | `Placement` (mode focus) |
| `Placement` | rect non nul | pose : cadre gardé, compteurs relevés à neuf, entrée ~0,25 s → `Recouvrement` ou `Affichée` |
| `Placement` | rect nul | re-poll **unique** à 80 ms ; toujours nul → `Repos`, **rien affiché** |
| `Recouvrement` | frappe / clic / scroll | **ignorés** |
| `Recouvrement` | `deactivateServer:` | `Sortie` — la perte de focus **perce** le plancher |
| `Recouvrement` | notif TIS | re-pose sur place : drapeau mis à jour, plancher réarmé à 1,5 s, compteurs à neuf |
| `Recouvrement` | `activateServer:` (autre champ) | `Sortie` puis `Placement` (mode focus) |
| `Recouvrement` | t = 1,5 s | `Affichée` |
| `Affichée` | un compteur d'actes a bougé | `Sortie` |
| `Affichée` | `deactivateServer:` | `Sortie` |
| `Affichée` | notif TIS | re-pose, plancher 1,5 s → `Recouvrement` |
| `Sortie` | notif TIS ou `activateServer:` pendant le fondu | on annule le fondu et on repose depuis l'alpha courant |
| `Sortie` | fondu terminé | `Repos` |

### Les onze décisions

1. **La position vient du rect du caret IMK, pas des bounds SkyLight.** Le ticket [#01 — Lire le cadre du HUD système au vol](01-cadre-du-hud-au-vol.md) avait tranché « SkyLight » avant que le canal caret ne soit prouvé partout ; il l'est depuis [#03 — Couverture réelle de la palette IMK, app par app](03-focus-dun-champ-texte.md). L'argument décisif est la latence : le rect est **déjà en mémoire** quand la notif TIS arrive, donc on peint à t+15 ms, soit 25 à 45 ms **avant** que le HUD système ne devienne visible (t+39-62 ms). La voie SkyLight, elle, ne connaît le cadre final qu'à t+44 ms et court derrière avec 17-18 ms de marge — mesurés sur une app témoin, jamais dans Chrome ni Electron. SkyLight ne reste qu'en **canari au démarrage** (« existe-t-il encore des fenêtres `CursorUIViewService` de 64×64 ? »).
2. **La bulle de langue ne peut pas disparaître avant le HUD système** — plancher de 1,5 s. Collision que le ticket ne voyait pas : le HUD tient 1,49-1,51 s fermes, donc la règle « part à la première frappe » aurait découvert les deux lettres pendant 1,2 s dans le cas d'usage le plus fréquent.
3. **Un seul objet `Bulle`, deux modes.** Le mode langue *recouvre* quelque chose (contrainte dure) ; le mode focus ne recouvre rien — aucun HUD système n'apparaît à la prise de focus.
4. **Le trigger focus tire à chaque prise de focus**, sans suppression de répétition. C'est le service rendu : savoir dans quelle langue on va taper *avant* de taper.
5. **Rect nul : re-poll unique à 80 ms, puis rien.** Pas de repli souris (aucun rapport avec le caret), pas de dernière position connue (pointe un champ qui n'a plus le focus). Corollaire assumé : si le HUD système apparaît quand même sans champ texte — **non mesuré** — on ne le couvre pas.
6. **Après son plancher, la bulle mode langue repasse aux règles normales** — elle ne s'arrête pas net à 1,5 s. C'est une **divergence voulue** avec le HUD système, et c'est la raison d'être de Bubulle : le HUD système part à 1,50 s que l'on ait tapé ou non, alors que l'information est utile *au moment où l'on tape*. J'avais recommandé une durée fixe au motif qu'une bulle encore à l'écran à t+2 s montre quelque chose que le système n'affiche jamais — **objection retirée** : elle posait l'indiscernabilité comme un but permanent. Elle n'est une contrainte que **pendant le plancher**, tant que le HUD système est dessous. Passé le plancher, il n'y a plus rien dont il faille être indiscernable.
7. **Aucun plafond de durée, et le timeout de sécurité est supprimé.** Sa justification d'origine — le champ mot de passe où l'on se croyait aveugle aux frappes — a été tuée par [#04 — Détecter la première frappe, y compris en secure input](04-detecter-la-premiere-frappe.md) : le compteur voit les frappes même en secure input. Il ne restait qu'une solution sans problème.
8. **La bulle est peinte une fois et ne bouge jamais**, comme le HUD système. Ça supprime tout sondage du caret une fois posée.
9. **Détection par compteur seul, sondé à 60 Hz** pendant l'affichage uniquement. Coût mesuré 0,005 µs/appel. Pas de `CGEventTap`, donc **aucune permission TCC** : ni Input Monitoring, ni Accessibility, ni Screen Recording.
10. **Quatre signaux la tuent** : frappe, clic, scroll, perte de focus. Le scroll bouche le trou ouvert par « bulle fixe + aucun plafond » — sans lui, un défilement laisse la capsule sur du contenu périmé indéfiniment. Le **rect devenu nul** a été écarté comme redondant : le seul cas qu'il couvrait (clic dans une zone non-texte de la même app) est déjà tué par le clic. La perte de focus **perce le plancher**.
11. **Les compteurs sont relevés à neuf à chaque pose**, ce qui règle gratuitement la course du raccourci de changement de langue : ⌘Espace est lui-même une frappe, comptée par `keyDown`. La notif TIS arrive 6-14 ms après, le tick 60 Hz jusqu'à 16 ms après — la notif gagne le plus souvent et la frappe est avalée sans jamais être vue. Quand elle perd, le fondu a couru ~2 ms sur 400 et la nouvelle pose repart de l'alpha courant.

Deux points tranchés par recommandation, sans objection de Frank : un changement de langue **préempte toujours** une bulle mode focus, et deux changements rapides **réarment** le plancher au lieu de s'empiler — calqué sur le HUD système, dont le compteur repart à zéro.

### Space, plein écran, multi-écrans

La bulle **reste sur son Space** (comportement par défaut) plus `.fullScreenAuxiliary` pour exister dans le Space d'une app en plein écran. Pas de `.canJoinAllSpaces` : sans plafond de durée, ce serait une capsule flottant au-dessus d'un autre Space en pointant un caret qui n'y est pas. Et changer de Space change l'app focalisée, donc la perte de focus la tue de toute façon.

### Valeurs reprises telles quelles du prototype

Niveau de fenêtre bas (≤ `statusBar`, 25) · entrée ~0,25 s, sortie ~0,40 s · clone strict `.hudWindow`, 22 pt, drapeaux SVG embarqués. Voir [#05 — Clone visuel du HUD, à l'écran](05-clone-visuel-du-hud.md).

### Ce que la résolution supprime

- **La règle de stabilisation du cadre** et **la course de 17-18 ms** — SkyLight sort du chemin chaud (décision 1).
- **La cadence de sondage du caret** — la recommandation 10 Hz / 1-2 Hz de [research/03](../research/03-focus-dun-champ-texte.md) devient sans objet : bulle fixe, un seul relevé au moment de poser (décision 8).
- **Le timeout de sécurité** (décision 7).
- **La réconciliation de coordonnées Cocoa/CG**, qui était un point de brouillard de la carte : le rect du caret arrive en Cocoa, la `NSPanel` est en Cocoa, plus aucune conversion. Le multi-écrans devient mécanique — on pose sur la `NSScreen` qui contient le rect.
- **Toute permission TCC** (décision 9).

### Ce que la résolution ouvre

L'**offset vertical** caret → capsule n'a **jamais été mesuré** — seul le centrage en x l'est, au pixel — et le comportement du HUD en **bord d'écran** non plus. Sans importance tant qu'on lisait les bounds du HUD ; désormais sur le chemin critique. Ticket créé : [#11 — Mesurer l'offset caret → capsule](11-offset-caret-capsule.md).
