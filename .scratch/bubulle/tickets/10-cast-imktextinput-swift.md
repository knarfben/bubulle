# Le cast du client IMK échoue côté Swift

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:task`
Status: closed
Assignee: Frank
Blocked by: —

> Trouvé en résolvant [Régression : la palette IMK ne passe plus enabled=1 toute seule](09-regression-auto-enable-palette.md).
> Une fois la sélection TIS rétablie, `activateServer:` arrive enfin — et c'est la ligne
> suivante qui casse. Bloque la vérification du rect, donc
> [Couverture réelle de la palette IMK, app par app](03-focus-dun-champ-texte.md) et
> [Machine à états de la bulle](08-machine-a-etats-de-la-bulle.md).

## Question

Rien à décider : c'est un bug de typage Swift, à corriger.

`BubulleController.activateServer:` reçoit bien son client maintenant, mais le `guard` échoue
et on repart sans jamais interroger le rect `[OBSERVÉ]` :

```
[2026-08-20 00:26:38 +0000] activateServer: sender ne conforme pas à BubulleTextInput
                            (Optional(<_IPMDServerClientWrapperLegacy: 0xbfac21d60>))
```

Cause : `sender as? BubulleTextInput` compile en `conformsToProtocol:`. Le wrapper
`_IPMDServerClientWrapperLegacy` **répond** aux sélecteurs (`attributesForCharacterIndex:
lineHeightRectangle:`, `selectedRange`, `bundleIdentifier`) mais ne **déclare** pas la
conformance au protocole local `BubulleTextInput` — qui n'existe que dans notre binaire. La
sonde ObjC de la recherche 02 ne voyait pas le problème : un cast `id<IMKTextInput>` en ObjC
n'est pas vérifié à l'exécution.

Travail :

- Remplacer le `as?` par une vérification par sélecteur (`responds(to:)`) suivie d'un
  `unsafeBitCast(sender as AnyObject, to: BubulleTextInput.self)`, ou passer par
  `perform(_:with:)`. Garder un log explicite si un sélecteur manque, pour ne pas retomber
  dans un échec silencieux.
- Vérifier que le rect remonte bien dans `/tmp/bubulle.log`, dans au moins deux apps (une
  AppKit, plus Chrome) — c'est le livrable que [Squelette du projet : bundle palette IMK
  installable](07-squelette-du-projet-swift.md) n'a jamais pu atteindre.

Livrable : `/tmp/bubulle.log` qui logge un rect de caret non nul, dans une vraie app.

## Comments

**Résolu.** Cause confirmée exactement comme suspecté : `sender as? BubulleTextInput` compile en
`conformsToProtocol:`, et `_IPMDServerClientWrapperLegacy` ne déclare pas cette conformance même
s'il répond à tous les sélecteurs. Remplacé par `castToTextInput(_:)` :
`responds(to:)` sur chacun des trois sélecteurs du protocole, puis `unsafeBitCast` vers
`BubulleTextInput`. Log explicite du sélecteur manquant si un jour un client ne répond pas à l'un
d'eux, pour ne pas retomber dans un échec silencieux.

Vérifié `[OBSERVÉ]`, `/tmp/bubulle.log`, environnement propre (`./install.sh`, cast neuf) :

- Le message d'erreur `sender ne conforme pas à BubulleTextInput` a disparu : `activateServer`
  aboutit désormais dans toutes les apps qui prennent le focus (`com.apple.systempreferences`,
  `com.anthropic.claudefordesktop`, `com.apple.TextEdit`, `com.google.Chrome.app.*`…).
- **TextEdit (AppKit)** : rect non nul confirmé — `rect=(190.0, 920.0, 1.0, 14.0)`, `selRange=(0,0)`,
  `attrsEmpty=false`. Livrable atteint pour la branche AppKit.
- **Claude for Desktop (Electron)** : rect non nul aussi, sans rien avoir demandé — `rect=(584.0,
  1226.0, 1.0, 24.0)`. Bonne nouvelle collatérale pour la couverture Electron.
- **Chrome** : le cast réussit (bundle résolu, plus d'erreur), mais le rect reste à zéro pendant
  la frappe normale dans le champ de recherche Google — testé avec focus + frappe réelle (`test`),
  confirmé à l'écran. Pas creusé plus loin : ça ressemble à une particularité connue de
  Chromium (`attributesForCharacterIndex:lineHeightRectangle:` répondu seulement pendant une
  composition IME active, pas en frappe simple), mais ce n'est qu'une hypothèse — pas
  `[OBSERVÉ]` faute d'avoir réussi à déclencher une composition dans cette session. Question
  distincte du bug de cast ; à trancher par
  [Couverture réelle de la palette IMK, app par app](03-focus-dun-champ-texte.md), qui hérite
  maintenant d'un canal qui fonctionne pour poser la question, plutôt que d'un cast cassé qui
  l'empêchait.

Environnement restauré : `./uninstall.sh`, `AppleSelectedInputSources` revenu à
`{PressAndHold, French}` `[OBSERVÉ]`, `local.bubulle` absent des deux clés TIS.

**Incident de session, sans rapport avec le code** : un `osascript keystroke` visant TextEdit est
parti vers l'app frontmost du moment (Claude for Desktop) et a tapé "bonjour" dans son champ de
saisie — jamais soumis (pas d'Entrée envoyée), signalé et laissé tel quel pour Frank.
