# #14 — Géométrie du HUD hors du cas nominal

Sonde : `probes/14-geometrie/probe.swift` (fork du #11 : index d'écran, mode observateur,
relevé systématique de `frame` **et** `visibleFrame`).
Relevés : `dell*.log` (écran 1x), `dock-*.log` / `dock48.log` / `dock128*.log` (Dock),
`obs2.log` (observateur, bascule clavier réelle).
Rejeu de la formule sur tous les relevés : `probes/14-geometrie/check2.py`.

---

## Réponse courte

| # | Question | Réponse |
|---|---|---|
| 1a | Les trois constantes tiennent-elles à 1x ? | **Oui, à l'identique.** 4,5 / 2,5 / seuil d'arrondi 0,4. Rien n'est proportionnel au facteur d'échelle. |
| 1b | Le clamp se réfère-t-il à l'écran du caret ou à l'union ? | **À l'écran qui contient le caret** — décisif : sur le DELL, la capsule bascule au bord bas du DELL alors que l'union continuait 1117 pt plus bas. |
| 2 | La capsule chinoise dépasse-t-elle 29 pt ? | **Non. La capsule est un 29 × 22 fixe, quel que soit le libellé.** `US`, `FR`, `فا` **et** le Wubihua chinois donnent tous un cadre 84 × 77. Aucun ajustement de largeur à faire au [#05](../tickets/05-clone-visuel-du-hud.md). |
| 3 | Le HUD se réfère-t-il à `frame` ou `visibleFrame` ? | **`visibleFrame`** — donc **le Dock est respecté**, et sur les trois bords. |

**Correction apportée au code** : `cadreGarde` prenait le `frame` de l'écran. Il prend désormais son
`visibleFrame` (`Sources/BubbleGeometry.swift`), et la capsule basculée est elle aussi bornée par le
plancher.

Bonus, incertitude n°1 de la [recherche 01](01-cadre-du-hud-au-vol.md) enfin levée :
**une bascule clavier réelle produit exactement la même notif** que `TISSelectInputSource` —
81 notifs relevées sur le seul chinois, aucune bascule manuelle silencieuse.

---

## 1. Écran secondaire, facteur d'échelle 1x

DELL U2419H rebranché, 1920 × 1080 @1x, posé **au-dessus** du portable dans l'arrangement
(AppKit y 1117 → 2197). Phases A / S / K / X rejouées **en coordonnées locales à cet écran**.

- **Écart vertical** : 4,50 pt sur les six tailles de police (rect de caret de 13 à 56 pt).
  Identique au 2x, **constant en points**.
- **Bords latéraux** : `S-droite-10` et `S-droite-2` clampent à `caps.maxX = 1809,5`, soit
  **`écran.maxX − 2,5`** ; `S-gauche-0` clampe à `écran.minX + 2,5`. Même constante qu'au 2x.
- **Arrondi horizontal** : les 14 positions de `X-arrx` suivent `floor(x + 0,6)` au centième près.
  Le seuil est bien **0,4 et pas 0,5**, y compris sur une grille de pixels deux fois plus grossière.
  L'arrondi se fait sur des **points entiers**, pas sur des pixels de l'écran : à 1x les deux
  coïncident, mais à 2x il ne descend pas au demi-point.
- **Bord bas** : bascule à `caret.bottom = −29` (CG local), capsule prévue à `maxY = −2,5`, donc
  **la même marge de 2,5 pt**. Un point plus bas, ça bascule.

**1b — la référence est l'écran du caret, pas l'union.** C'est le seul point où les deux
hypothèses divergeaient franchement, et il est tranché net : le bord bas du DELL touche le bord
haut du portable, sans discontinuité de coordonnées. Une référence « union des écrans » n'aurait
jamais fait basculer la capsule là — elle avait 1117 pt de rab en dessous. Elle a basculé.

⚠️ Le premier passage (`dell-K.log`) montre une série de cadres figés : `kCGWindowBounds` sert la
position précédente pendant quelques centaines de ms. Rejeu propre dans `dell-K2.log` — c'est
celui-là qui fait foi. Même piège qu'au #11, même parade.

## 2. Libellé à plus de deux glyphes — le chinois

`TISSelectInputSource` renvoyant `-50` sur un input method depuis un process tiers, la seule voie
était le **mode observateur** : la sonde n'appelle rien, Frank bascule au clavier, elle relève.

Sur 85 cadres relevés, il n'existe que **deux tailles de fenêtre `CursorUIViewService`** :

| cadre | capsule peinte | ce que c'est |
|---|---|---|
| 84 × 77 | **29 × 22** | la capsule à deux lettres — celle que Bubulle recouvre |
| 264 × 83 | 209 × 28 | le **sélecteur** d'input source (⌘Espace maintenu), autre chose |

`com.apple.inputmethod.SCIM.WBH` (« Stroke – Simplified », `lang=zh-Hans`) produit un
**84 × 77 comme tout le monde** : la capsule ne s'élargit pas pour son libellé. Le risque de liséré
qui motivait ce point n'existe pas, et la bulle reste à 29 pt.

Au passage, le canal de lecture du #13 se confirme en conditions réelles : la notif remonte
`id=com.apple.inputmethod.SCIM.WBH`, `name=Stroke – Simplified`, `lang=zh-Hans` — les trois champs
justes, sur une bascule clavier faite à la main.

## 3. Dock visible — `frame` ou `visibleFrame` ?

**`visibleFrame`, sur les trois bords.** Deux mesures indépendantes le montrent.

**Le bord gauche tranche sans ambiguïté** (`dock-left.log`, Dock posé à gauche, réserve 49 pt) :
le clamp se pose à `caps.minX = 51,50`, soit **`visibleFrame.minX + 2,5`** — 51,5 pt à droite du
bord physique de l'écran. Reproduit sur les huit positions de la phase G, sans une seule exception.

**Le bord bas confirme** : Dock en bas, la bascule remonte de ~70 pt par rapport à l'écran nu.
Le HUD ne descend pas sous le Dock.

**La fenêtre `Dock` n'est pas une piste** : `CGWindowListCopyWindowInfo` la donne plein écran
(`0,0 1728×1117`), elle ne dit rien de la hauteur des tuiles. Rien à lire là — `visibleFrame` suffit,
et c'est du NSScreen pur, sans API privée.

**Comportement de la capsule basculée** : quand le caret est si bas que même la capsule basculée
buterait, elle est **clampée** sur la butée basse (`dock-M.log`, `M-bas-51` à `M-bas-46` : la capsule ne
bouge plus). La bascule n'est donc pas seule : il y a bien une butée basse dure.

### La marge basse jitte de ±2 pt, seule zone d'ombre du ticket

Le seuil de bascule, Dock affiché, n'est **pas reproductible au point près** :

| relevé | réserve `visibleFrame` | marge observée sous le bord de la zone visible |
|---|---|---|
| `dock-L` / `dock-M` / `dock-big` (session du 20/08) | 72 pt | ~0,5 pt |
| `dock48` | 73 pt | ~2,5 pt |
| `dock128` | 73 pt | ~1,5 pt |
| `dock128b` (rejeu à configuration identique) | 73 pt | ~2,5 pt |

`dock128` et `dock128b` sont **la même configuration rejouée deux fois** et donnent deux seuils
distants de 1 pt : c'est du bruit, pas une dépendance à la taille du Dock. Le Dock, lui, refuse de
grossir (tuiles 48 → 128 sans changer la réserve : il est contraint par la largeur de l'écran).

**Constante retenue : 2,5 pt sur les trois bords.** Elle est mesurée exactement sur les bords
latéraux (y compris derrière un Dock à gauche), exactement sur le bord bas sans Dock (1x et 2x), et
au bruit près sur le bord bas avec Dock. Une constante unique, cohérente avec le #11.

**Rejeu sur l'ensemble des relevés : 174 / 183 conformes** (`check2.py`). Les 9 écarts sont tous
des positions de caret à moins de 2 pt du seuil de bascule, Dock en bas affiché — 8 viennent de la
session à réserve 72, 1 du run qui jitte. Avec 0,5 au lieu de 2,5 le score tombe, *et* ça casse le
bord bas sans Dock et le clamp gauche : 2,5 est bien la bonne valeur.

**Risque résiduel accepté** : si le caret tombe dans cette bande de ~2 pt juste au-dessus d'un Dock
affiché en bas, Bubulle peut poser sa bulle du mauvais côté du caret et laisser les deux lettres à
découvert le temps d'une bulle. Cosmétique, non persistant, et **inexistant chez Frank, dont le Dock
est en masquage automatique** (réserve 0 pt, donc c'est le cas « sans Dock », mesuré au point près).

---

## Observation annexe — le sélecteur ⌘Espace

Maintenir ⌘Espace fait apparaître le **sélecteur** d'input source (264 × 83, capsule 209 × 28),
centré sur le caret lui aussi, à 1,5 pt sous lui. La capsule à deux lettres apparaît quand même à
la fin du geste, donc Bubulle fait son travail — mais sa bulle de 29 pt se pose *dans* la zone du
sélecteur pendant que celui-ci est affiché. Le #12 a exercé ⌘Espace en usage réel sans que ça
ressorte. Noté au brouillard de la carte, pas tranché ici.
