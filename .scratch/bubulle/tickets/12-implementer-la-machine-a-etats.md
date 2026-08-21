# Implémenter la machine à états dans la palette

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:task`
Status: closed
Assignee: Frank (session wayfinder)
Blocked by: 06, 13

## Question

Rien à décider : la [#08 — Machine à états de la bulle](08-machine-a-etats-de-la-bulle.md) est écrite noir sur blanc, les assets viennent de [#06 — Inventaire des input sources et assets drapeaux](06-inventaire-sources-et-drapeaux.md), la formule de placement vient de [#11 — Mesurer l'offset caret → capsule](11-offset-caret-capsule.md), le choix du drapeau vient de [#13 — Repli pour une source d'entrée non mappée](13-repli-source-non-mappee.md). Il reste à la poser dans le bundle palette existant.

Travail, en partant de `Sources/BubulleController.swift`, qui ne fait aujourd'hui que logger le rect :

- La fenêtre : `NSPanel` non-activating, `isFloatingPanel`, `ignoresMouseEvents`, niveau ≤ `statusBar` (25), `.fullScreenAuxiliary` sans `.canJoinAllSpaces`. Reprendre la variante A du [#05 — Clone visuel du HUD, à l'écran](05-clone-visuel-du-hud.md) — `NSVisualEffectView` en `.hudWindow`, `blendingMode = .behindWindow`, rayon `h * 0.26`, drapeau centré à `h * 0.58`, capsule 29 × 22 pt.
- Les cinq états et toutes les transitions du tableau, y compris le réarmement des compteurs à chaque pose et l'annulation du fondu en cours.
- L'observateur de `kTISNotifySelectedKeyboardInputSourceChanged`. **Pas de filtre palette à écrire** :
  le #13 a mesuré que `TISCopyCurrentKeyboardInputSource()` ne remonte jamais qu'une source
  `TISCategoryKeyboardInputSource` — Bubulle ne se voit pas lui-même, ni `CharacterPaletteIM`, ni
  `PressAndHold`. C'est aussi le canal de lecture de la langue : contrairement à
  `TISCreateInputSourceList` (#09), il **n'est pas caché par process** et est déjà à jour quand la
  notification arrive, donc aucun fork.
- Le choix du drapeau, échelle du #13 : ID exact dans `flags.json` → valeur `null` = source muette →
  langue primaire `Languages[0]` contre la table **déduite** de `flags.json` → rien. Décoder le JSON
  en `[String: String?]` (le `null` est signifiant). Collision de langue entre deux sources mappées
  ⇒ cette langue sort de la table (l'ordre des clés JSON n'est pas déterministe, mesuré).
- **Source muette = aucune bulle**, dans les deux modes, plus une ligne de log dédupliquée par ID
  pour la session (ID littéral, nom localisé, langue primaire). Un asset introuvable ou illisible
  tombe dans le même état, avec une cause distincte dans le log. Attention : `build.sh` n'embarque
  pas encore `Flags/` dans le bundle, donc **le chemin de repli est le chemin nominal** tant que
  l'embarquement n'est pas branché — à faire ici.
- **Amendement au #08** : une bulle vivante qui bascule vers une source muette **disparaît net, sans
  fondu** — c'est la seule transition où le drapeau posé est connu-faux, et le fondu de 0,40 s le
  laisserait recouvrir un HUD système juste.
- Le relevé du rect au `Placement` avec le re-poll unique à 80 ms, puis plus aucun sondage du caret.
- **Le placement, formule du [#11](11-offset-caret-capsule.md), à reprendre telle quelle** — elle est
  vérifiée sur 90 relevés. Trois pièges qu'elle encode et qu'il ne faut pas « simplifier » :
  l'ancre horizontale est `rect.minX` et **pas** `rect.midX` (le canal IMK annonce une largeur de
  caret de 1,0 pt, donc les deux diffèrent d'un demi-point, ce qui fait un point entier après
  arrondi) ; l'arrondi est `floor(x + 0,6)` et **pas** `round(x)` (seuil mesuré ≈ 0,4) ; le bord bas
  ne clampe pas, il **bascule** la capsule au-dessus du caret. Le rect IMK est en coordonnées
  **AppKit écran** (origine bas-gauche) — conversion vers CG à faire.
- **`TISSelectInputSource` fait un `dispatch_assert_queue(main)`** sur macOS 26 : hors du thread
  principal, c'est un SIGTRAP, pas un code d'erreur (mesuré au #11). La notif TIS arrive sur la main
  queue, donc le chemin nominal est bon — mais tout appel TIS déporté sur un thread tuerait Bubulle.
- **Corriger `install.sh` au passage** : `"$BIN" & disown` hérite de stdout, donc `./install.sh | tail`
  ne rend jamais la main alors que l'installation a réussi. Une ligne : `"$BIN" >/dev/null 2>&1 &`.
- Le tick 60 Hz des compteurs d'actes (`keyDown`, `mouseDown`, `scrollWheel`), actif **uniquement** pendant qu'une bulle est affichée.
- Animations : entrée ~0,25 s, sortie ~0,40 s.
- Placement sur la `NSScreen` qui contient le rect du caret.

Vérifications attendues avant de fermer, dans les apps déjà couvertes par [#03 — Couverture réelle de la palette IMK, app par app](03-focus-dun-champ-texte.md) — au minimum une app AppKit, une Electron, un navigateur et un terminal :

- Les deux lettres du HUD système ne sont **jamais** visibles au changement de langue.
- La bulle part bien à la frappe, au clic, au scroll et à la perte de focus, et jamais avant.
- ⌘Espace sur une bulle mode focus déjà affichée ne produit aucun clignotement.
- Aucune permission TCC n'est demandée au premier lancement.
- **Quel ID le chinois remonte-t-il ?** Ouvert par le #13, qui n'a pas pu le mesurer :
  `TISSelectInputSource` renvoie `-50` sur un input method depuis un process CLI. Lancer
  `probes/13-repli/watch`, faire ⌘Espace vers le chinois **à la main**, et lire si c'est
  `com.apple.inputmethod.SCIM.WBH` (mappé) ou son sosie `com.apple.keylayout.WubihuaKeyboard`
  (`Languages[0]` **vide**, donc muet aux deux échelons). Si c'est le second, ajouter l'ID à
  `flags.json` — sans quoi le clavier chinois quotidien n'affiche rien.

Livrable : le binaire qui tourne sur la machine de Frank et fait ce que dit la carte.

## Résolution

Posé dans `Sources/BubbleStateMachine.swift`, `BubblePanel.swift`, `BubbleGeometry.swift`,
`FlagTable.swift`, `InputSources.swift`, `BubulleController.swift` — cinq états, formule de
placement du #11, table de drapeaux du #06/#13. `build.sh` embarque déjà `Flags/`, `install.sh`
avait déjà le correctif stdout. Deux ajustements faits pendant la vérification :

- **Repoll étendu** (`kRepollMaxAttempts = 5`, au lieu d'1) : une fenêtre neuve (ex. Sublime au
  lancement) peut mettre plus de 80 ms à finir son layout ; un seul repoll ratait la pose.
- **`collectionBehavior` + `.moveToActiveSpace`** (`BubblePanel.swift`) : sans lui, le panel reste
  épinglé au Space actif lors de son premier affichage et devient invisible, sans erreur, sur tout
  autre Space — bug réel trouvé en testant Raycast/Sublime sur un Space différent.

Checklist de vérification (toutes cochées) :
- Deux lettres du HUD système jamais visibles au changement de langue — confirmé (TextEdit,
  Ghostty, Chrome, Sublime).
- Départ de la bulle sur frappe/clic/scroll/perte de focus, jamais avant — confirmé ; investigation
  poussée sur un faux négatif apparent (voir plus bas).
- ⌘Espace sur bulle déjà affichée (mode focus) : pas de clignotement — confirmé.
- Aucune permission TCC au premier lancement — confirmé. La seule boîte vue (« Allow
  swift-frontend to enable Bubulle? ») est la boîte TIS déjà documentée par le #11/#03, pas un
  prompt Accessibilité/Surveillance des entrées ; elle **revient à chaque rebuild**, pas seulement
  au premier après changement de signature (répond à la question ouverte de la carte) — cohérent
  avec un `codesign --force --deep -s -` ad-hoc qui produit une signature différente à chaque
  compilation.
- Chinois : confirmé en conditions réelles (⌘Espace manuel) que l'ID remonté est bien
  `com.apple.inputmethod.SCIM.WBH` (mappé), pas le sosie `WubihuaKeyboard`. Rien à ajouter à
  `flags.json`. Piège : dans le sélecteur de langues macOS, l'entrée correspondante s'appelle
  **« Stroke – Simplified »**, pas « Wubi – Simplified » (qui est un ID différent, `WBX`).

**Fausse piste explorée en profondeur, résolue** : le drapeau semblait ne jamais apparaître sur le
document de démarrage restauré par Sublime Text au lancement. Après investigation (logs de pose
temporaires, sonde `CGEventTap` dédiée `probes/mousewatch.swift`), la cause n'est ni géométrique
ni un bug Bubulle : Sublime rejoue plusieurs clics synthétiques à des positions différentes dans
la seconde qui suit l'ouverture de ce document précis (restauration de sélection/scroll/sidebar),
indiscernables d'un vrai clic pour `CGEventSourceCounterForEventType` (#04) — la bulle se ferme
donc elle-même avant d'être vue. N'affecte que ce document restauré ; un nouveau document (⌘N) ou
un fichier ouvert normalement fonctionnent. Documenté en commentaire dans
`BubbleStateMachine.swift`, pas de contournement retenu (casserait le dismiss immédiat voulu
partout ailleurs).

**Doublon de process observé, sans rapport** : `install.sh` lance le binaire, et
`TISSelectInputSource` déclenche en plus un lancement système (`imklaunchagent`) — deux process
vivants après un `install.sh`, un seul après un simple kill+relance manuel. Un seul des deux reçoit
réellement les callbacks IMK (confirmé via un log de `pid` dans `pose()`, retiré depuis) ; le
second est inerte. Sans impact fonctionnel, non retouché.

Hors scope, non bloquant : [#14 — Géométrie du HUD hors du cas nominal](14-geometrie-hors-cas-nominal.md)
reste ouvert (écran 1x, largeur de capsule pour un libellé chinois large, Dock visible).
