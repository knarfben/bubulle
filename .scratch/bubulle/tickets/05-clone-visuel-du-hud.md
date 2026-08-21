# Clone visuel du HUD, à l'écran

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:prototype`
Status: closed
Assignee: —
Blocked by: —

## Question

À quoi ressemble notre bulle, et est-ce qu'on sait la poser à un endroit arbitraire de l'écran de façon indiscernable du HUD système ?

Prototype jetable, position en dur (pas de détection) : une `NSPanel` non-activating, `isFloatingPanel`, `level` au-dessus des HUD système, `ignoresMouseEvents`, `collectionBehavior` qui la rend présente sur tous les Spaces et pendant le plein écran.

À faire réagir Frank sur :

- Fidélité du matériau : `NSVisualEffectView` (quel `material` ? `.hudWindow` ?) vs rendu custom. Comparaison côte à côte avec une vraie capture du HUD système.
- Géométrie exacte : taille, rayon des coins, marges, ombre portée — mesurées sur capture d'écran du vrai HUD.
- Animations d'apparition et de fondu, et leurs durées.
- Rendu du drapeau à cette taille : lisibilité de 🇺🇸 vs 🇫🇷 vs 🇮🇷 en tout petit, besoin d'une bordure ou d'un liseré.
- **Le niveau de fenêtre passe-t-il réellement au-dessus du HUD de `CursorUIViewService`** ? C'est la condition de tout le recouvrement — à vérifier en vrai, pas sur la doc.

Livrable : une bulle affichable à la demande, validée visuellement par Frank, liée au ticket comme asset.

## Comments

Prototype : [prototypes/05-clone-visuel/](../prototypes/05-clone-visuel/) — 4 variantes sous le curseur, sélecteur de niveau de fenêtre, gel par raccourci global ⌃⌥⌘B. Jugé à l'œil par Frank contre la vraie bulle.

**Le recouvrement est acquis, et à bon compte.** Un niveau de fenêtre **bas suffit** (≤ `statusBar`, 25) pour passer au-dessus du HUD de `CursorUIViewService` — pas besoin de `screenSaver` ni de `shielding`. C'est le meilleur résultat possible : on ne masque pas au passage les menus, alertes et éléments système qu'un niveau haut aurait recouverts. À re-vérifier au chiffre exact (`floating` 3 suffit-il ?) quand le vrai binaire tournera, le test ayant groupé les deux paliers bas.

**Géométrie confirmée** : 22 pt de haut colle à la vraie bulle, ce qui valide au jugé la mesure de 29×22 pt relevée dans [Lire le cadre du HUD système au vol](01-cadre-du-hud-au-vol.md).

**Variante retenue : A — clone strict.** `NSVisualEffectView` en matériau `.hudWindow`, `blendingMode = .behindWindow`, rayon de coin `h * 0.26`, drapeau seul centré à `h * 0.58`. L'illusion l'emporte sur la lisibilité renforcée de B.

**Drapeaux : SVG embarqués pour les quatre langues.** Le FR dessiné en vectoriel a battu tous les emoji, mais dessiner l'emblème iranien et les cinq étoiles chinoises à la main n'a pas de sens — on garde la netteté du vectoriel via des fichiers SVG. L'emoji est écarté.

**Animation : les durées du prototype (0,15 s / 0,25 s) sont trop rapides.** Viser ~0,25 s à l'entrée et ~0,40 s à la sortie, à régler sur le vrai binaire.
