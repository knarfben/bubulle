# Le rappel — afficher la langue courante à la demande

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:task`
Status: open
Assignee: Frank (session wayfinder)
Blocked by: — *(une mesure bloquante interne, voir plus bas)*

## Question

La bulle ne naît que d'un événement : bascule de langue, prise de focus, retour de l'invite. Entre
deux, Frank n'a aucun moyen de **demander** la langue courante. Or le coût d'une méprise n'est pas
un caractère à effacer : croire qu'on est en français AZERTY alors qu'on est en anglais QWERTY
transforme un ⌘A de sélection en **⌘Q qui ferme l'app**. Le besoin d'afficher la langue survit
donc à l'absence de champ texte — il ne s'agit plus de savoir dans quelle langue on va *écrire*,
mais **quel clavier va interpréter la prochaine frappe**, y compris une frappe qui n'écrit rien.

Contrainte auto-référentielle : le geste qui pose la question **ne peut pas contenir de caractère**,
puisqu'on l'utilise précisément quand on ne sait plus ce que produit une touche. Seuls les
modificateurs sont identiques dans tous les layouts — ⇧ est ⇧ en AZERTY comme en persan.

Livrable : un geste sans caractère qui affiche la langue courante, n'importe où, sans permission
supplémentaire.

## Décisions

Prises en session de grilling, dans l'ordre où elles se sont résolues.

1. **Un objet nouveau, pas un quatrième mode de la bulle : le rappel.** Position, taille, opacité
   et durée diffèrent toutes de la bulle, et il n'imite aucun objet système — il n'y a rien à
   recouvrir au centre de l'écran. L'invariant « une seule à la fois, jamais deux » de
   [CONTEXT.md](../../CONTEXT.md) porte sur la bulle et ne s'étend pas à lui.

2. **Geste : double ⌃ Control.** Écartés — ⇧⇧ (le modificateur le plus pressé au monde : hésiter
   sur une majuscule produit un faux positif que la règle du compteur ne rattrape pas, et JetBrains
   l'utilise déjà), ⌥⌥ (mnémonique puisque ⌥Espace est la bascule de langue de Frank, mais trop
   proche du geste de bascule lui-même), Globe (potentiellement déjà lié à « changer de source »,
   auquel cas le geste changerait la langue au lieu de l'afficher).

3. **Disqualification par les compteurs d'actes du [#04](04-detecter-la-premiere-frappe.md).** La
   séquence n'est un rappel que si **aucun `keyDown` ni `mouseDown`** n'est survenu entre les deux
   appuis, dans une fenêtre de **350 ms** (mesurée : les doubles-appuis réels tombent entre 149 et
   233 ms). Ça élimine gratuitement ⌃C/⌃D dans un terminal, ⌃↑ de Mission Control, et deux ⌃clic
   d'affilée. Aucun code neuf : `ActeCounters` existe déjà.

4. **Guet : un seul timer permanent à 60 Hz sur `CGEventSource.flagsState`.** ~~Repos lent sur le
   compteur `flagsChanged` + rafale sur l'état~~ — **tué par la mesure, voir plus bas**. Deux raisons
   indépendantes : le montage à deux étages n'existait que pour éviter un coût qui s'est révélé être
   de **4 ns par lecture** (0,24 µs par seconde à 60 Hz), et son canal de réveil — le compteur — est
   précisément celui qui **gèle sous secure input**. 60 Hz et non 30 : les appuis mesurés durent 66 à
   100 ms, soit 4 à 6 échantillons ; à 33 ms il n'en resterait que deux. C'est aussi la cadence des
   deux timers déjà présents (`compteursTimer`, `guetTimer`), donc rien de neuf à régler. Écarté :
   `CGEventTap` + *Input Monitoring* (Bubulle perdrait « aucune permission système requise »,
   argument de tête du README, et deviendrait aveugle sous secure input — [#04](04-detecter-la-premiere-frappe.md)).

5. **Le rappel se pose au centre de l'écran de la fenêtre focalisée**, résolu par
   `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` filtré sur le PID de `frontmostApplication` —
   **474 µs, aucune permission** : `kCGWindowBounds` et `kCGWindowOwnerPID` passent sans TCC, seuls
   les titres et la capture sont protégés ([#01](01-cadre-du-hud-au-vol.md), testé en bundle non
   autorisé). Écarté : l'écran de la souris, faux précisément après un ⌘Tab — le geste après lequel
   on est perdu.

6. **Registre : massif et bref.** ~200 pt de haut, opacité ~0,5, ~500 ms en tout. Chiffres exacts
   au prototype, comme le [#05](05-clone-visuel-du-hud.md) l'a fait pour le clone du HUD.

7. **Repli sur source sans drapeau : le code de langue en texte** (`de`, `ru`). C'est une
   **divergence assumée avec le [#13](13-repli-source-non-mappee.md)**, et les deux raisons qui y
   fondaient « rien » tombent ici : un glyphe en mode passif ne rend pas le service (le rappel est
   demandé), et sans plafond de durée il resterait indéfiniment (le rappel dure 500 ms). Surtout,
   **un geste explicite qui ne produit rien est indiscernable d'une panne** — le pire retour
   possible quand on est justement perdu. `Languages[0]` est déjà lu par `FlagTable`, toujours
   présent, toujours vrai. Vaut aussi pour une source **volontairement muette** (`null` dans
   `flags.json`) : le `null` tait la bulle, pas une réponse demandée. Coût réel : premier rendu de
   texte du projet, qui n'a jamais dessiné que des SVG.

8. **Le rappel coexiste avec une bulle vivante.** Un geste explicite doit toujours répondre, même
   quand la réponse est déjà à l'écran. Écarté : l'inhiber (le geste marcherait ou non selon un
   état que Frank ne contrôle pas), et tuer la bulle (en mode langue elle recouvre le HUD système —
   la tuer redécouvre les deux lettres).

9. **Le rappel joue son animation jusqu'au bout** : un acte ne le tue pas. Il est bref et il a été
   demandé. Un second ⌃⌃ pendant un rappel **relance** l'animation au lieu d'être ignoré.

10. **Le rappel ne se déclenche pas au changement de langue.** Cet événement est déjà servi par la
    bulle, qui doit rester puisqu'elle recouvre le HUD. Un rappel en plus, ce serait deux artefacts
    pour une seule information ; un rappel à la place, ce serait redécouvrir les deux lettres —
    la thèse du projet.

## Mesure — le risque de fond est levé

Sonde [`probes/18-modificateurs`](../probes/18-modificateurs/NOTES.md), bundle `.app` séparé et
jamais autorisé, lancé par `open` pour être son propre *responsible process* (protocole du
[#01](01-cadre-du-hud-au-vol.md)). macOS 26.6.2 (25G83), arm64.

**Lire *quel* modificateur est enfoncé ne demande aucune permission** :

```
AXIsProcessTrusted()             = false
CGPreflightListenEventAccess()   = false
CGPreflightScreenCaptureAccess() = false
```

…et les deux lectures d'état répondent juste malgré tout. Elles **n'ont jamais divergé** sur
l'ensemble du log.

| Appel | Coût |
|---|---|
| `CGEventSource.flagsState(.combinedSessionState)` | **4 ns** |
| `NSEvent.modifierFlags` | **28 ns** |
| `CGEventSourceCounterForEventType(.flagsChanged)` | **4 ns** |

(Élision de l'optimiseur défaite en accumulant les résultats dans un puits imprimé — sans cette
précaution `-O` supprime les appels et donne des chiffres faux.)

**Détection** : double-⌃ reconnu 5 fois sur 5, Δ entre 149 et 233 ms. Deux ⌃ isolés espacés de
~1,8 s rejetés. Un ⌃ suivi d'une touche annule bien la séquence, par le compteur `keyDown`.

**Le compteur `flagsChanged` décroche sous secure input** — et c'est ce qui tue la décision 4
d'origine :

```
138000.0  CG=⌃··· NS=⌃···  flagsChanged=+0  SECURE
138066.6  CG=···· NS=····  flagsChanged=+0  SECURE
138183.3  CG=⌃··· NS=⌃···  flagsChanged=+0  SECURE
   ✅ DOUBLE-⌃ détecté — Δ = 183.3 ms
138250.0  CG=···· NS=····  flagsChanged=+0  SECURE
138365.7  CG=···· NS=····  flagsChanged=+4  SECURE   ← rattrapage 100 ms plus tard
```

Quatre transitions d'état réelles, compteur à `+0` sur les quatre, puis un `+4` groupé après coup.
L'état, lui, est juste et immédiat, et **le geste est détecté pendant le secure input**. C'est une
asymétrie avec le [#04](04-detecter-la-premiere-frappe.md), qui avait établi que le compteur
`keyDown` continuait de compter sous secure input : ça vaut pour `keyDown`, **pas** pour
`flagsChanged`.

Conséquence : le compteur ne peut pas servir de signal de réveil. L'état est le seul canal fiable,
et il est assez bon marché pour être lu en permanence.

**Reste à faire** : le rendu et la tenue en usage réel, sortis dans
[#19 — Prototype du rappel](19-prototype-du-rappel.md) ; puis le repli texte de la décision 7, et le
vocabulaire à poser dans [CONTEXT.md](../../CONTEXT.md) à la fermeture.

## Écarté en route

**Poser la bulle en haut de l'écran quand l'app focalisée n'a pas de champ texte** (une fenêtre
Chrome en plein écran, par exemple, où la barre de menus est cachée et où rien n'annonce la langue).
Exploré en grilling jusqu'à huit décisions — dont une bulle *persistante* tant que l'app garde le
focus, qui contredisait à la fois « ni icône barre de menus, ni cérémonie » (cadrage) et « toute
bulle meurt au premier acte » ([#08](08-machine-a-etats-de-la-bulle.md)). Abandonné au profit du
rappel, qui répond au même besoin — savoir quel clavier interprète la prochaine frappe — **sur
demande plutôt qu'en permanence**, et donc sans capsule posée en continu au-dessus d'une vidéo.
