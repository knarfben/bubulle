# Mesurer l'offset caret → capsule

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:research`
Status: closed
Assignee: Frank (session wayfinder)
Blocked by: —

## Question

La [#08 — Machine à états de la bulle](08-machine-a-etats-de-la-bulle.md) place désormais la bulle à partir du **rect du caret IMK** seul, sans lire les bounds du HUD système. Ça met sur le chemin critique une géométrie qui n'a jamais été mesurée en entier.

Ce qu'on sait déjà, au pixel, de [#01 — Lire le cadre du HUD système au vol](01-cadre-du-hud-au-vol.md) : la capsule peinte fait **29 × 22 pt** et elle est **centrée sur le caret en x** (caret x=526, centre du cadre 484 + 42 = 526, exact).

Ce qui manque :

- **L'offset vertical.** Où se pose la capsule par rapport au rect du caret — au-dessus, en dessous, à quelle distance du haut ou du bas du rect ? Le rect du caret a une hauteur variable selon la police (17 à 24 pt dans les relevés de [research/03](../research/03-focus-dun-champ-texte.md)) : l'offset est-il constant en points, ou proportionnel à la hauteur du rect ?
- **Le comportement en bord d'écran.** Le HUD clampe-t-il quand le caret est près du bord droit, du bas, ou du haut de l'écran ? Si oui, selon quelle règle ? Notre dérivation doit clamper à l'identique, sinon les deux lettres dépassent.
- **Le second écran et le facteur d'échelle 1x.** L'inset de 27,5 pt n'a été mesuré qu'en @2x (55 px / 2), avec ±0,5 pt d'incertitude d'anti-aliasing, et aucun HUD réel n'a été mesuré sur l'écran secondaire.
- **Le libellé à plus de deux glyphes.** Le cadre 84 × 77 est vérifié pour `US` et `فا`. Le Wubihua chinois donne peut-être une capsule plus large — ce qui décalerait le centrage.

Méthode : la même que le ticket 01 — un `NSTextView` témoin qui donne le rect du caret par `firstRect(forCharacterRange:)`, `TISSelectInputSource` pour déclencher le HUD, `SLSGetWindowBounds` pour relever son cadre, et une comparaison des deux à chaque position testée. Balayer plusieurs positions de caret, dont les quatre bords, sur les deux écrans.

Livrable : la règle de dérivation caret → cadre gardé, écrite comme une formule utilisable telle quelle, avec sa règle de clamping.

## Answer

**La règle de dérivation est mesurée et vérifiée : 90 relevés sur 90 reproduits, zéro écart.**
Détail complet : [research/11-offset-caret-capsule.md](../research/11-offset-caret-capsule.md).

```swift
/// caret : rect du caret en CG (origine haut-gauche) · screen : cadre CG de l'écran du caret
func cadreGarde(caret: CGRect, screen: CGRect) -> CGRect {
    let W: CGFloat = 29, H: CGFloat = 22
    let ECART: CGFloat = 4.5     // écart constant caret <-> capsule
    let MARGE: CGFloat = 2.5     // marge minimale capsule <-> bord d'écran

    var x = (caret.minX + 0.6).rounded(.down) - W / 2   // centrée sur minX, arrondi seuil 0,4
    var y = caret.maxY + ECART                           // sous le caret…
    if y + H > screen.maxY - MARGE { y = caret.minY - ECART - H }   // …ou bascule au-dessus

    x = min(max(x, screen.minX + MARGE), screen.maxX - MARGE - W)   // pas de clamp vertical
    return CGRect(x: x, y: y, width: W, height: H)
}
```

Les quatre points que le ticket demandait :

- **Offset vertical : constant en points, ancré sur le bas du rect.** `capsule.top = caret.bottom
  + 4,50`, identique pour six hauteurs de rect de 13 à 56 pt. Ni proportionnel, ni mesuré depuis la
  ligne de base.
- **Bords : une seule constante, 2,5 pt.** À gauche et à droite la capsule est **clampée** à 2,5 pt
  du bord (le cadre HUD, lui, sort de l'écran — c'est de l'ombre). En bas ça ne clampe pas, **ça
  bascule** : la capsule passe au-dessus du caret avec le même écart de 4,5 pt, dès que
  `caret.bottom + 26,5 > screen.maxY − 2,5`. Le haut ne contraint rien — la capsule se pose
  volontiers par-dessus la barre de menus.
- **Second écran / facteur 1x : non mesuré**, un seul écran branché en séance (arbitrage pris avec
  Frank). Les trois constantes restent des mesures @2x.
- **Libellé à plus de deux glyphes : non mesuré**, la bascule manuelle vers le chinois ayant été
  remise à plus tard (arbitrage pris avec Frank).

Deux trouvailles hors question, qui vont directement au [#12](12-implementer-la-machine-a-etats.md) :

- **L'ancre horizontale est `rect.minX`, pas `rect.midX`** — et le canal IMK annonce une largeur de
  caret de **1,0 pt** là où AppKit annonce 0,0. Un ancrage sur `midX` décalerait donc la bulle d'un
  point entier après arrondi. Recoupement côte à côte sur six positions : origine et hauteur
  identiques au dernier décimal entre `firstRect` (AppKit) et `lineHeightRectangle` (IMK) — **la
  formule transfère telle quelle**.
- **`TISSelectInputSource` fait un `dispatch_assert_queue(main)`** sur macOS 26 : appelé hors du
  thread principal il tue le process sur SIGTRAP, sans code d'erreur.

L'arrondi n'est pas un `round()` : le seuil mesuré est ≈ **0,4**, pas 0,5 (encadré à [0,37 ; 0,41]).
`floor(x + 0,6)` reproduit 14/14 là où `round(x)` en rate 2 — soit un liseré de capsule système à
découvert. Côté vertical la question ne se pose pas pour une app AppKit, qui ne remonte jamais un
bas de rect fractionnaire ; pour Chrome/Electron, `floor(y + 0,6)` est un pari, pas une mesure.

Ouvre [#14 — Géométrie du HUD hors du cas nominal](14-geometrie-hors-cas-nominal.md), qui porte les
trois mesures restantes (écran 1x, libellé large, Dock visible). **Il ne bloque pas le #12** : la
géométrie nominale suffit pour l'écrire, le #14 la raffine.

Sonde : `probes/11-offset/` (`probe.swift`, `build.sh`, traces `run.log` / `runD.log` / `runE.log`
/ `runF.log`). Machine restaurée à l'identique en fin de séance : Bubulle désinstallé, six input
sources, French active.
