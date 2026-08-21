# Mesurer l'offset caret → capsule — trouvailles

Ticket : [11-offset-caret-capsule](../tickets/11-offset-caret-capsule.md) · Carte : [MAP](../MAP.md)

Machine de vérification : macOS **26.6.2 (25G83)**, arm64, Swift 6.3.1, **un seul écran**
(interne 3456×2234 @2x = 1728×1117 pt ; `visibleFrame` 1728×1084, barre de menus 33 pt, Dock masqué).
Le DELL U2419H @1x de la [recherche 01](01-cadre-du-hud-au-vol.md) n'était pas branché.

**Convention de lecture** : ✅ = mesuré moi-même · 📄 = lu dans un header/une trace · ❓ = non testé.

Toutes les coordonnées ci-dessous sont en **points, repère CG global** (origine en haut à gauche de
l'écran principal, y vers le bas) — c'est ce que renvoie `kCGWindowBounds`.

---

## Réponse courte : la formule

✅ **90 relevés sur 90 reproduits exactement**, sur trois passes indépendantes (offsets, bords,
arrondis). Zéro écart, à 0,01 pt près.

```swift
/// Cadre gardé : où peindre la capsule 29 × 22, à partir du seul rect du caret.
/// `caret` : le rect du caret en CG (origine haut-gauche). `screen` : le cadre CG de l'écran
/// qui contient le caret.
func cadreGarde(caret: CGRect, screen: CGRect) -> CGRect {
    let W: CGFloat = 29, H: CGFloat = 22
    let ECART: CGFloat = 4.5     // écart constant caret <-> capsule, en points
    let MARGE: CGFloat = 2.5     // marge minimale entre la capsule et le bord d'écran

    // x : centrée sur le bord GAUCHE du rect, arrondie à l'entier avec un seuil de 0,4
    var x = (caret.minX + 0.6).rounded(.down) - W / 2

    // y : sous le caret ; si ça ne tient pas, bascule au-dessus, même écart
    var y = caret.maxY + ECART
    if y + H > screen.maxY - MARGE { y = caret.minY - ECART - H }

    // clamp horizontal seulement (le haut ne clampe jamais, voir plus bas)
    x = min(max(x, screen.minX + MARGE), screen.maxX - MARGE - W)

    return CGRect(x: x, y: y, width: W, height: H)
}
```

Le cadre de la fenêtre HUD système, si on en a besoin, est `cadreGarde.insetBy(dx: -27.5, dy: -27.5)`
— soit 84 × 77 (recherche 01). **Bubulle n'en a pas besoin** : il peint la capsule, pas le cadre.

---

## Les cinq faits mesurés

### 1. L'offset vertical est **constant en points**, ancré sur le **bas** du rect

✅ C'était la question centrale du ticket, et la réponse est nette. Six tailles de police,
donc six hauteurs de rect de caret de **13 à 56 pt**, à position fixe :

| police | hauteur du rect | `capsule.top − caret.bottom` | `capsule.top − caret.top` |
|---|---|---|---|
| 11 | 13,00 | **+4,50** | +17,50 |
| 13 | 16,00 | **+4,50** | +20,50 |
| 18 | 21,00 | **+4,50** | +25,50 |
| 24 | 28,00 | **+4,50** | +32,50 |
| 36 | 43,00 | **+4,50** | +47,50 |
| 48 | 56,00 | **+4,50** | +60,50 |

`capsule.top = caret.bottom + 4,50` sur les six, au centième. La colonne de droite, elle, suit la
hauteur — donc **l'ancre est le bas du rect, et l'écart ne dépend pas de la hauteur**. Ni constante
proportionnelle, ni écart mesuré depuis la ligne de base : le bas du rect, plus 4,5 pt.

C'est la réponse à « constant en points, ou proportionnel à la hauteur du rect ? » — **constant**.

### 2. Horizontalement : centrée sur `rect.minX`, arrondie à l'entier avec un seuil de 0,4

✅ La recherche 01 avait vu « centrée sur le caret » sur un seul point. Sur 14 positions à pas
fractionnaire (caret déplacé caractère par caractère dans une suite de `i`, avance 3,135 pt), la
règle exacte apparaît :

```
caret.minX   371,00  374,14  377,27  380,41  383,54  ...  405,49  408,63
centre HUD   371     374     377     381     384     ...   406     409
```

Les deux valeurs en gras (`.41` et `.49`) montent alors qu'un `round()` classique les descendrait :
✅ **le seuil d'arrondi est ≈ 0,4, pas 0,5** (encadré par les mesures à [0,37 ; 0,41]).
`floor(x + 0,6)` reproduit **14/14**. `round(x)` en rate 2 sur 14 — soit une capsule décalée d'un
point, donc un liseré de la capsule système à découvert.

✅ **L'ancre horizontale est `rect.minX`, pas `rect.midX`.** Distingué par le seul cas où les deux
diffèrent : un rect de largeur non nulle (sélection de 4 `M`, rect de 413,00 de large départ). Le
centre de la capsule est tombé sur **413,00 = `rect.minX`**, pas sur le milieu. Pour un caret
ponctuel (largeur 0), les deux coïncident — c'est le cas courant.

### 3. Verticalement, l'arrondi ne se pose pas côté AppKit

✅ Tentative de produire un bas de rect fractionnaire via `textContainerInset` : AppKit **arrondit
l'inset vertical à l'entier**. Sur neuf insets de 0,00 à 1,04, le bas du rect n'a pris que deux
valeurs, 651 puis 652 — jamais une décimale. Le x, lui, reste franchement fractionnaire (435,20).

Donc : ✅ **une app AppKit ne remonte jamais un bas de rect fractionnaire**, et la question de
l'arrondi vertical est sans objet pour elles. ❓ Chrome et Electron calculent leur rect eux-mêmes
et peuvent remonter du fractionnaire — non mesuré. Par symétrie avec l'horizontale, `floor(y + 0,6)`
est le pari raisonnable, mais **ce n'est pas une mesure**.

### 4. Bords latéraux : un clamp symétrique à **2,5 pt**, sur la capsule et non sur le cadre

✅ Balayage fin des deux bords. Le HUD laisse son **cadre** sortir de l'écran (`minX` mesuré à
**−25,00**, la partie hors écran n'étant que de l'ombre) et clampe la **capsule peinte** :

| bord | dernière position libre | valeur clampée |
|---|---|---|
| gauche | caret x = 17,20 → capsule à 2,50 | capsule.minX = **2,50** pour tout caret x ≤ 17,2 (testé jusqu'à −0,80) |
| droite | caret x = 1707,20 → capsule à 1692,50 | capsule.maxX = **1725,50** = `W − 2,50` pour tout caret x ≥ 1717,2 |

Les deux bords donnent la **même marge de 2,50 pt**. En cadre HUD, ça donne `minX ∈ [−25, W−59]`.

### 5. Bord bas : ça ne clampe pas, **ça bascule** — et le seuil est la même marge de 2,5 pt

✅ C'est la trouvaille qui manquait le plus, parce qu'une dérivation qui clamperait au lieu de
basculer laisserait les deux lettres à découvert sur toute la moitié basse de la capsule.

Quand la capsule ne tient plus sous le caret, elle passe **au-dessus**, avec le **même écart de
4,5 pt** :

```
capsule.bottom = caret.top − 4,50        (mode basculé)
```

✅ Le seuil est épinglé au point près :

| bas du rect de caret | capsule.maxY prévue en mode normal | observé |
|---|---|---|
| 1088 | 1114,50 = `H − 2,50` | **normal** (dernière valeur qui tient) |
| 1089 | 1115,50 > `H − 2,50` | **bascule** |

Donc : bascule dès que `caret.bottom + 4,5 + 22 > screen.maxY − 2,5`. **Exactement la même marge de
2,5 pt** que les bords latéraux — les trois bords obéissent à une seule constante.

✅ **Le bord haut, lui, ne contraint rien** : caret placé à cheval sur le haut de l'écran
(`caret.minY = −6`, donc au-dessus du bord), la capsule s'est posée à y = 14,50 — **par-dessus la
barre de menus**, sans clamp ni bascule. Cohérent : le sens naturel étant vers le bas, le haut
n'est jamais une contrainte, et la bascule (qui, elle, va vers le haut) ne se déclenche que près du
bas. ❓ Un écran assez court pour déclencher la bascule *et* buter en haut n'existe pas ici.

### 6. Le rect IMK est le rect AppKit — recoupement côte à côte

✅ La formule est mesurée contre `firstRect(forCharacterRange:)`, mais Bubulle lira le rect par
`attributes(forCharacterIndex:lineHeightRectangle:)` côté IMK. Les deux canaux passent par TSM,
mais ça n'avait jamais été vérifié. Bubulle a donc été **installé le temps du test** et sa palette
a loggé son rect pendant que la sonde loggait le sien, sur le même caret, six positions :

| sonde — `firstRect` (AppKit) | palette — `lineHeightRectangle` (IMK) |
|---|---|
| `(299.20, 700.00, 0.00, 16.00)` | `(299.2041015625, 700.0, 1.0, 16.0)` |
| `(899.20, 300.00, 0.00, 16.00)` | `(899.2041015625, 300.0, 1.0, 16.0)` |
| `(499.60, 500.00, 0.00, 21.00)` | `(499.6039123535156, 500.0, 1.0, 21.0)` |
| `(1199.73, 800.00, 0.00, 33.00)` | `(1199.734375, 800.0, 1.0, 33.0)` |
| `(199.17, 200.00, 0.00, 13.00)` | `(199.1748046875, 200.0, 1.0, 13.0)` |
| `(699.77, 600.00, 0.00, 56.00)` | `(699.7734375, 600.0, 1.0, 56.0)` |

**Origine et hauteur identiques au dernier décimal, sur les six.** La seule différence est la
largeur : le canal IMK annonce **1,0 pt** (largeur nominale de caret) là où AppKit annonce 0,0.

Ça compte, parce que ça aurait pu décaler la formule d'un point entier après arrondi : la formule
s'ancre sur **`minX`**, `maxY` et `minY` — jamais sur `midX`, qui est le seul champ où les deux
canaux divergent. ✅ **La formule transfère telle quelle du témoin AppKit à la palette Bubulle.**

Les deux canaux rendent des coordonnées **AppKit écran** (origine bas-gauche) : la conversion vers
CG reste à la charge de Bubulle.

📄 Au passage, deux défauts de l'outillage existant, trouvés en installant :

- **`install.sh` fait pendre tout appelant qui pipe sa sortie.** `"$BIN" & disown` hérite de stdout,
  donc le tube ne voit jamais d'EOF et un `./install.sh | tail` ne rend jamais la main — alors que
  l'installation, elle, a parfaitement réussi. Correctif d'une ligne : `"$BIN" >/dev/null 2>&1 &`.
- ✅ La **boîte de consentement macOS** évoquée par la carte est bien apparue (process
  `UserNotificationCenter` visible pendant l'installation). Elle n'a pas bloqué l'installation.

---

## Méthode

Une seule sonde, `probes/11-offset/probe.swift`, bundle `.app` autonome (`local.bubulle.probe11`) :

- une `NSWindow` **borderless** (donc non contrainte par `constrainFrameRect`, ce qui permet de
  pousser le caret jusqu'au-delà des bords) avec un `NSTextView` ;
- le rect du caret lu par `firstRect(forCharacterRange:actualRange:)` — c'est **littéralement la
  méthode `NSTextInputClient` que le canal TSM appelle**, donc la même valeur que reçoit
  `CursorUIViewService` ;
- la fenêtre est translatée pour poser le caret sur une cible, par convergence (≤ 6 itérations,
  tolérance 0,05 pt) ;
- `TISSelectInputSource` bascule US ↔ French pour déclencher le HUD ;
- le cadre du HUD lu à t+260 ms par `CGWindowListCopyWindowInfo(.optionAll)`, filtré sur
  `kCGWindowOwnerName == "CursorUIViewService"` et `height > 70` (déployé = 84×77, au repos 64×64).

✅ **Aucune API privée et aucune permission** : contrairement à la recherche 01, `SkyLight`/`SLS`
n'a pas servi du tout. `kCGWindowBounds` suffit, parce qu'on lit à t+260 ms et non dans le chemin
chaud. La sonde ne demande rien à TCC.

📄 **Piège rencontré, et il compte pour le [#12](../tickets/12-implementer-la-machine-a-etats.md)** :
sur macOS 26, `TISSelectInputSource` fait un `dispatch_assert_queue(main)` dans
`TSMSelectInputSource` — **appelé hors du thread principal, il fait tomber le process sur
SIGTRAP**, pas un code d'erreur. Toute lecture/écriture TIS doit être sur le main thread.
(La notification TIS arrivant sur la main queue, le #12 y est naturellement, mais la contrainte
mérite d'être écrite.)

Phases : A = 6 tailles de police à position fixe · B = 13 positions dont les quatre bords ·
C = balayages fins bord droit (9) et bord bas (8) · D = arrondi horizontal (14), arrondi vertical
(9), seuil du clamp gauche (11), seuil de bascule (10) · E = inset fractionnaire (9) + rect de
largeur non nulle (1). Traces brutes : `probes/11-offset/run.log`, `runD.log`, `runE.log`.

---

## Ce qui reste ouvert

1. ❓ **Le second écran et le facteur d'échelle 1x.** Non mesurable aujourd'hui — un seul écran
   branché (arbitrage pris avec Frank en séance). Les trois constantes (4,5 · 2,5 · seuil d'arrondi
   0,4) sont mesurées **@2x uniquement**. Deux inconnues précises restent : (a) l'écart de 4,5 pt et
   la marge de 2,5 pt sont-ils les mêmes à 1x, où la grille de pixels est deux fois plus grossière ;
   (b) le clamp se réfère-t-il au cadre de **l'écran qui contient le caret** ou à l'union des
   écrans — la formule suppose le premier, ce qui est le comportement naturel mais n'est pas prouvé.
   Une passe de 5 minutes avec le DELL rebranché tranche les deux : rejouer les phases C et D sur
   l'écran secondaire.
2. ❓ **Le libellé à plus de deux glyphes.** Le cadre 84 × 77 (capsule 29 × 22) est confirmé pour
   `US`, `FR` et `فا`. Le Wubihua chinois n'a pas pu être déclenché : `TISSelectInputSource` renvoie
   `-50` sur un input method depuis un process tiers, et la bascule à la main a été remise à plus
   tard (arbitrage pris avec Frank en séance). **Si la capsule chinoise est plus large que 29 pt, la
   formule tient toujours** — elle est centrée, donc elle reste centrée — mais la bulle de Bubulle,
   figée à 29 pt de large par le [#05](../tickets/05-clone-visuel-du-hud.md), laisserait dépasser un
   liseré des deux côtés. C'est le seul cas connu où le recouvrement pourrait échouer.
   Mesure à faire : lancer la sonde en mode observateur, faire ⌘Espace vers le chinois à la main,
   lire la largeur du cadre.
3. ❓ **Le Dock visible.** Ici le Dock est masqué, donc `screen.frame.maxY == screen.visibleFrame.maxY`
   et les deux lectures du bord bas sont indiscernables. La formule utilise `frame` (le bord physique).
   Si le HUD se référait en fait à `visibleFrame`, un Dock visible décalerait le seuil de bascule
   d'une hauteur de Dock. Une seule mesure avec le Dock affiché tranche.
4. ❓ **L'arrondi vertical pour un client non-AppKit** — voir §3 ci-dessus. Le recoupement IMK du
   §6 ne le tranche pas : il a été fait dans une app AppKit, donc avec des bas de rect entiers des
   deux côtés.
