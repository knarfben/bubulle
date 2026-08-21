# Un canal universel vers le rect du caret

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:research`
Status: closed
Assignee: —
Blocked by: —

## Question

Le HUD système connaît la position du caret dans **toutes** les apps, y compris celles où l'API Accessibility ne donne rien. Peut-on s'abonner au même canal, plutôt que de dépendre du HUD (qui n'apparaît qu'au changement de langue) ?

Pistes à instruire, de la plus prometteuse à la plus spéculative :

- **Bundle Input Method (InputMethodKit)** : un input method sélectionné reçoit `IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:)`, soit le rect du caret en coordonnées écran, fourni par l'app via `NSTextInputClient`. Question bloquante : peut-on recevoir ça **sans** se substituer aux layouts de l'utilisateur ? Un input method « passthrough » qui ne modifie aucun événement est-il viable, ou casse-t-il la saisie ?
- **TSM / Text Services Manager** (Carbon, semi-privé) : `TSMGetActiveDocument`, `TSMGetDocumentProperty`, les tags de propriété qui exposent le rect du caret. Accessible hors du contexte d'un input method ?
- **`TextInputUIMacHelper.framework`** (privé) : que dumpe `class-dump` ? Y a-t-il une classe/notification qui publie la position du caret courant, consommable par un tiers ?
- **Notification distribuée** ou XPC émis par `CursorUIViewService` que l'on pourrait écouter.

Livrable : dire si un canal universel existe et lequel, ou constater qu'il n'y en a pas et que le trigger « prise de focus » devra se contenter d'Accessibility + repli. Cette réponse commande la forme de tout le reste de la carte.

## Comments

Trouvailles : [research/02-canal-universel-vers-le-caret.md](../research/02-canal-universel-vers-le-caret.md) — vérifié bout en bout sur macOS 26.5, palette IMK réellement construite, installée, interrogée, désinstallée.

**Le canal existe et il est à nous.** Un bundle avec `InputMethodType = palette` + `ComponentInvisibleInSystemUI = true` s'enregistre en catégorie `TISCategoryPaletteInputSource`, dont le header dit « zero or more of these can be selected » : il est sélectionné **en parallèle** des layouts, pas à leur place. Vérifié : `local.bubulle.probeim` `selected=1` en même temps que `French` `selected=1`, `AppleEnabledInputSources` inchangé, rien dans le menu de saisie. Le précédent est Apple lui-même : `PressAndHold` est exactement ça, et c'est pour ça que son popup d'accents tombe pile sur le caret dans Chrome.

**Le passthrough n'est pas un compromis, c'est structurel** : `handleEvent:client:` implémenté, **0 appel** pendant qu'on tapait « azerty » dans Chrome, qui a tout reçu. TSM ne met jamais une palette sur le chemin des touches. Zéro risque pour la saisie, zéro interaction avec le SCIM chinois côté événements.

**Le rect est là, à la demande** : on retient le client et on appelle `attributesForCharacterIndex:0 lineHeightRectangle:` quand on veut, hors de tout callback. Chrome : `{{-50,2117},{1,22}}`, qui suit le caret en direct. Coordonnées écran Cocoa (origine en bas à gauche, multi-écrans), largeur 1, hauteur = hauteur de ligne. `selectedRange` vient avec.

**Les trois autres pistes sont mortes, pour une seule raison établie** : `TUINSCursorUIController` (TextInputUIMacHelper) se charge **dans le process de l'app focalisée** et son `client` est le `NSTextInputClient` de cette app — vérifié en le lisant dans ma propre sonde AppKit. Le HUD ne lit pas un bus, il lit l'app. Donc : pas de propriété TSM géométrique (liste exhaustive des tags dans le header) et `TSMDocumentID` intra-process ; `CursorUIViewService` est un view service ViewBridge sans nom mach ni notification distribuée (aucun symbole `CFNotificationCenter`).

**Pour le déclencheur « prise de focus »** : c'est `activateServer:`, sans Accessibility. Piège : le premier `activateServer:` peut donner un rect nul (Chrome l'a fait), il faut re-interroger. Et `rect == NSZeroRect` + `selRange == NSNotFound` est le signal fiable « pas de champ texte » — c'est le test de focus, gratuit. Conséquence sur la carte : l'agent devient un `.app` dans `~/Library/Input Methods`, lancé **avant** d'être activé côté TIS (sinon `TISSelectInputSource` → `-50`), et Accessibility recule au rang de repli.

Trous à combler avant l'implémentation : Electron confirmé seulement par transitivité via Chrome (VS Code et Discord testés sans champ focalisé), Java non testable (aucun JRE ici), et coût/latence de l'appel non mesurés.
