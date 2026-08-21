# Géométrie du HUD hors du cas nominal : écran 1x, libellé large, Dock visible

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:research`
Status: closed
Assignee: Frank (session wayfinder)
Blocked by: —

## Question

Le [#11 — Mesurer l'offset caret → capsule](11-offset-caret-capsule.md) a livré la formule de
dérivation, vérifiée sur 90 relevés. Trois conditions n'ont pas pu être mesurées en séance, faute
de matériel branché et de bascule manuelle. Chacune est une mesure courte, mais elles demandent
toutes que Frank soit devant la machine.

**1. Écran secondaire et facteur d'échelle 1x.** Les trois constantes de la formule — écart 4,5 pt,
marge de bord 2,5 pt, seuil d'arrondi 0,4 — sont mesurées **@2x uniquement**. Deux questions
distinctes : (a) tiennent-elles à 1x, où la grille de pixels est deux fois plus grossière ; (b) le
clamp se réfère-t-il au cadre de **l'écran qui contient le caret** ou à l'union des écrans ? La
formule suppose le premier — comportement naturel, non prouvé. Méthode : rebrancher le DELL U2419H
et rejouer les phases C et D de `probes/11-offset/probe.swift` sur l'écran secondaire.

**2. Libellé à plus de deux glyphes.** Le cadre 84 × 77 (capsule **29 × 22**) est confirmé pour
`US`, `FR` et `فا`. Le Wubihua chinois n'a jamais été déclenché : `TISSelectInputSource` renvoie
`-50` sur un input method depuis un process tiers. **Si sa capsule dépasse 29 pt de large**, la
bulle de Bubulle — figée à 29 pt par le [#05](05-clone-visuel-du-hud.md) — laisse dépasser un liseré
des deux côtés au changement de langue. C'est le seul cas connu où le recouvrement peut échouer, et
il concerne un clavier de l'usage quotidien de Frank. Méthode : sonde en mode observateur,
⌘Espace vers le chinois **à la main**, relever la largeur du cadre. La même manip vérifie au passage
que la bascule clavier réelle produit bien la même notif que `TISSelectInputSource` — incertitude
n°1 restée ouverte depuis la [recherche 01](../research/01-cadre-du-hud-au-vol.md).

**3. Dock visible.** Le Dock était masqué pendant les mesures, donc `screen.frame.maxY ==
screen.visibleFrame.maxY` et les deux lectures du bord bas sont indiscernables. La formule utilise
`frame` (le bord physique). Si le HUD se référait en fait à `visibleFrame`, un Dock affiché
décalerait le seuil de bascule d'une hauteur de Dock. Une seule mesure tranche.

**Ce ticket ne bloque pas le [#12](12-implementer-la-machine-a-etats.md)** : la géométrie nominale
mesurée au #11 suffit pour l'écrire. Il la raffine — et le point 2 peut imposer un ajustement de la
largeur de la bulle.

Livrable : les trois constantes confirmées ou corrigées hors du cas nominal, et la largeur de
capsule du chinois.

---

## Résolution

**Les trois constantes tiennent hors du cas nominal, le chinois ne déborde pas, et la référence
d'écran est `visibleFrame` — pas `frame`.** Détail complet :
[research/14-geometrie-hors-cas-nominal.md](../research/14-geometrie-hors-cas-nominal.md).

**1. Écran secondaire et 1x** — les trois constantes sont **inchangées** à 1x : écart 4,50 pt
(six tailles de police, rect de 13 à 56 pt), marge de bord 2,50 pt (clamp gauche et droit, bascule
en bas), seuil d'arrondi 0,4 sur `floor(x + 0,6)` (14 positions au centième près). Rien n'est
proportionnel au facteur d'échelle, et l'arrondi se fait sur des **points entiers**, pas sur des
pixels d'écran. **(b) La référence est bien l'écran qui contient le caret, pas l'union** : sur le
DELL — dont le bord bas touche le bord haut du portable, sans discontinuité de coordonnées — la
capsule bascule au bord bas du DELL alors que l'union lui laissait 1117 pt de rab.

**2. Le chinois ne déborde pas — la capsule est un 29 × 22 fixe.** Sur 85 cadres relevés en mode
observateur (bascules clavier réelles), il n'existe que deux tailles de fenêtre
`CursorUIViewService` : 84 × 77 (capsule à deux lettres, **quel que soit le libellé** — `US`, `FR`,
`فا` et le Wubihua chinois) et 264 × 83 (le sélecteur ⌘Espace maintenu, autre chose). Le liséré
qui motivait ce point **n'existe pas** : rien à changer au [#05](05-clone-visuel-du-hud.md), la
bulle reste à 29 pt. Au passage, l'**incertitude n°1 de la [recherche 01](../research/01-cadre-du-hud-au-vol.md)
tombe** : une bascule clavier réelle produit exactement la même notif que `TISSelectInputSource`.

**3. Dock : la référence est `visibleFrame`, sur les trois bords.** Le bord gauche tranche seul et
sans bruit — Dock posé à gauche (réserve 49 pt), le clamp se pose à `visibleFrame.minX + 2,5`, huit
positions sur huit. Le bord bas confirme : Dock en bas, la bascule remonte de ~70 pt. La fenêtre
`Dock` n'est d'aucun secours (`CGWindowList` la donne plein écran) — `visibleFrame` suffit, et c'est
du NSScreen pur. **Trouvaille au passage** : quand le caret est si bas que même la capsule basculée
buterait, elle est **clampée** sur la butée basse — la bascule n'est pas seule, il y a une butée basse dure.

**Zone d'ombre assumée** : le seuil de bascule bas, Dock affiché, jitte de ±2 pt — deux rejeux à
configuration identique donnent deux seuils distants de 1 pt. La constante retenue reste **2,5 pt
sur les trois bords** : exacte sur les côtés, exacte en bas sans Dock (1x et 2x), au bruit près en
bas avec Dock. Rejeu de la formule sur tous les relevés : **174 / 183 conformes**, les 9 écarts
étant tous à moins de 2 pt du seuil, Dock en bas. Conséquence possible : une bulle posée du mauvais
côté du caret dans cette bande de 2 pt. Cosmétique, non persistant, et **inexistant chez Frank,
dont le Dock est en masquage automatique**.

**Code corrigé et posé** : `cadreGarde` prenait `screen.frame`, il prend maintenant le
`visibleFrame` de l'écran du caret, et borne aussi la capsule basculée
(`Sources/BubbleGeometry.swift` + appelant dans `BubbleStateMachine.swift`, qui passait déjà le
`visibleFrame` sans que la fonction le prenne — le projet ne compilait plus). Reconstruit,
réinstallé, palette relancée.
