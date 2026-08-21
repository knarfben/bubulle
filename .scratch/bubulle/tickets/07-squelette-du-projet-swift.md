# Squelette du projet : bundle palette IMK installable

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:task`
Status: closed
Assignee: —
Blocked by: —

> Réécrit après [Un canal universel vers le rect du caret](02-canal-universel-vers-le-caret.md). L'hypothèse d'origine — un exécutable SwiftPM nu lancé à la main — ne tient plus : pour recevoir le rect du caret, bubulle **doit** être un `.app` enregistré comme input source de catégorie palette. Voir la note de cadrage sur la carte.

## Question

Rien à décider sur le fond : il faut le squelette installable, sans quoi aucun autre ticket ne peut être vérifié en conditions réelles.

Travail :

- Bundle `.app` avec les clés d'`Info.plist` établies par la recherche : `InputMethodType = palette`, `ComponentInvisibleInSystemUI = true`, `InputMethodConnectionName`, `tsInputMethodCharacterRepertoireKey`, identifiant `local.bubulle`.
- Installation dans `~/Library/Input Methods/`, enregistrement via `TISRegisterInputSource`, activation via `TISEnableInputSource` + `TISSelectInputSource`. **Piège établi** : le `.app` doit tourner **avant** d'être activé côté TIS, sinon `TISSelectInputSource` renvoie `-50`.
- Un script `install.sh` / `uninstall.sh` qui pose et retire proprement le bundle, et restaure `AppleSelectedInputSources` — la recherche a démontré que le cycle complet est réversible, il faut le garder tel.
- `IMKServer` + classe de contrôleur qui retient le client sur `activateServer:` et expose une méthode « donne-moi le rect du caret maintenant ».
- Vérifier que l'activation de la palette laisse les layouts de Frank (US, French, SCIM chinois, Persan) strictement intacts dans `AppleEnabledInputSources`.
- Signature ad-hoc, quarantaine, et stabilité de l'octroi TCC quand la signature change entre deux builds (piège classique — la permission Input Monitoring du tap y est sensible).

Livrable : `install.sh` qui pose un bundle qui se lance, s'enregistre, et logge le rect du caret de l'app focalisée.

## Comments

Squelette posé, à la racine du projet (pas dans `.scratch/`) :

```
Sources/main.swift              — NSApplication + IMKServer(name:bundleIdentifier:)
Sources/BubulleController.swift — IMKInputController, activateServer:/deactivateServer:,
                                   polling 1 Hz du client retenu, log vers /tmp/bubulle.log
Resources/Info.plist            — clés établies par la recherche 02, identifiant local.bubulle
Scripts/tisctl.swift            — CLI TIS (register/enable/select/deselect/disable/wait-enabled/list),
                                   exécuté via `swift`, faute d'équivalent shell aux API Carbon/HIToolbox
build.sh / install.sh / uninstall.sh
```

**Vérifié en conditions réelles, ce qui marche** (bout en bout sur cette machine) :
- `build.sh` compile et scelle un `.app` valide (`codesign -s -`), signature ad-hoc acceptée sans prompt.
- `install.sh` copie dans `~/Library/Input Methods/`, lève la quarantaine, `TISRegisterInputSource` → `0`.
- Le binaire lancé crée son `IMKServer` sans erreur (`_IMKServerLegacy` non nil) et complète la
  poignée de main IMK avec `imklaunchagent` : confirmé dans `log stream`
  (`imklaunchagent: Received setIMKXPCEndpoint:forBundleIdentifier: from InputMethod`).
- `uninstall.sh` retire le bundle et restaure les layouts sélectionnés — testé, `AppleSelectedInputSources`
  revient à l'état d'avant.
- `TISInputSourceID` apparaît bien en catégorie `TISCategoryPaletteInputSource` / type
  `TISTypeCharacterPalette`, `isEnableCapable=true`, exactement comme la sonde de la recherche 02.

**Casse trouvée, non résolue** : le flip automatique `enabled=0 → enabled=1` que la recherche 02
avait observé au simple lancement du process **ne s'est pas reproduit** ici, sur la même machine
(macOS 26.5, build 25F71), le lendemain. Testé et éliminé comme causes :
- signature ad-hoc qui change à chaque rebuild (essayé avec un `TISInputSourceID` jamais vu
  auparavant : même résultat) ;
- cache `imklaunchagent`/`TextInputMenuAgent` périmé (les deux agents relancés à froid : même résultat) ;
- appel explicite `TISEnableInputSource` après lancement (retourne `0` mais l'état ne change pas,
  y compris relu dans le même process juste après l'appel) ;
- attente insuffisante (poll 1×/2 s pendant 30 s : jamais de flip) ;
- `NSPrincipalClass` absent (ajouté : aucun effet).

Conséquence directe : `TISSelectInputSource` échoue en `-50` (paramErr), donc impossible de vérifier
en vrai le log du rect du caret pour l'instant. Ouvert : [09-regression-auto-enable-palette](09-regression-auto-enable-palette.md).

L'environnement a été restauré (bundle désinstallé, `AppleSelectedInputSources` revenu à
`{PressAndHold, French}`).
