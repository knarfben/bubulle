# Régression : la palette IMK ne passe plus enabled=1 toute seule

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:research`
Status: closed
Assignee: Frank
Blocked by: —

> Ouvert depuis [Squelette du projet : bundle palette IMK installable](07-squelette-du-projet-swift.md).
> C'est un blocage direct pour [Machine à états de la bulle](08-machine-a-etats-de-la-bulle.md) et
> pour toute vérification en conditions réelles du reste de la carte : sans sélection, aucun
> `activateServer:` n'arrive jamais.

## Question

[Un canal universel vers le rect du caret](02-canal-universel-vers-le-caret.md) a établi, mesuré
bout en bout le 2026-08-18 : un bundle `InputMethodType=palette` enregistré (`TISRegisterInputSource`)
puis **lancé** passe automatiquement `enabled=0 → enabled=1` côté TIS, sans appel supplémentaire —
c'est ce qui permet ensuite `TISSelectInputSource` de réussir.

Le 2026-08-19, sur la **même machine** (macOS 26.5, build 25F71 inchangé), avec un bundle qui
reproduit fidèlement les clés Info.plist et le montage IMKServer de la sonde d'origine, **ce flip
ne se produit plus jamais** — `enabled` reste bloqué à `false` indéfiniment (testé jusqu'à 30 s de
poll), y compris avec un `TISInputSourceID` neuf, après redémarrage à froid d'`imklaunchagent` et
`TextInputMenuAgent`, et malgré une poignée de main IMK confirmée réussie côté `imklaunchagent`
(`Received setIMKXPCEndpoint:forBundleIdentifier:` vu dans `log stream`). `TISEnableInputSource`
appelé explicitement retourne `noErr` mais ne change rien, y compris relu dans le même process
juste après l'appel — ce qui élimine un simple problème de cache inter-process.

Pistes non encore essayées, dans l'ordre le plus prometteur :

- ~~**Reproduire la sonde ObjC d'origine telle quelle**~~ — **fait, la régression n'est pas dans le
  squelette Swift.** Sonde reconstruite en ObjC (`probes/09-objc-repro/`, jetable), montage identique
  à la description de la recherche 02 (`IMKServer initWithName:bundleIdentifier:`, protocole
  `IMKTextInput` redéclaré localement, mêmes clés Info.plist, `TISInputSourceID` neuf
  `local.bubulle.objcrepro` pour écarter tout résidu de cache). Même résultat exact : `enabled`
  reste `false` après 24 s de poll, poignée de main XPC pourtant identique. **La régression est
  donc dans l'environnement/le daemon, pas dans le code de la palette.** Sonde ObjC désinstallée,
  environnement restauré.
- **Se déconnecter/reconnecter** (ou redémarrer) pour repartir d'un état daemon garanti propre —
  aucun des redémarrages d'agents essayés n'a un effet équivalent à un vrai logout, et il reste
  possible qu'un état soit resté coincé après les nombreux cycles register/kill de la session de
  recherche elle-même.
- **`log stream` avec des sous-systèmes plus larges** (`eventMessage CONTAINS "TIS"`,
  `subsystem CONTAINS "HIToolbox"`) pendant tout le cycle register→launch→wait, pas seulement
  filtré par nom de process — la trace capturée ici s'arrête juste après la poignée de main XPC,
  sans visibilité sur ce qui décide (ou ne décide pas) du flip `enabled`.
- **TCC / Input Monitoring** : la lecture de `TCC.db` a été bloquée (base protégée, pas de Full
  Disk Access depuis ce contexte) — à vérifier depuis Réglages Système directement, ou avec accès
  disque complet, si une entrée liée à `local.bubulle` existe et est refusée silencieusement.
- Si rien ne marche : **rouvrir la piste Accessibility en repli pour le rect**, au moins pour
  débloquer la suite de la carte pendant que cette régression reste ouverte — mais ça dégraderait
  la couverture (plus d'apps où AX ne donne rien, cf. Chrome/Electron) et casserait la prémisse de
  [02](02-canal-universel-vers-le-caret.md). À ne considérer qu'en dernier recours, et à re-décider
  explicitement si on y arrive, pas glisser dessus en douce.

Livrable : soit le flip revient et on sait pourquoi il avait disparu (pour ne pas re-régresser),
soit on a une explication ferme de pourquoi il ne revient pas et une décision explicite sur la suite.

## Comments

**Résolu. Ce n'était pas l'environnement : c'était l'ordre des appels dans `install.sh`.**
Deux pièges distincts, cumulés, chacun mesuré par A/B dans la même session.

### Piège 1 — `TISEnableInputSource` doit être appelé AVANT de lancer le process

La recherche 02 décrivait le flip comme « automatique au lancement ». Il ne l'est pas : il
est *armé* par un `TISEnableInputSource` préalable. Cet appel renvoie `0` en laissant
`enabled=false` — ce qui l'a fait passer pour un échec, d'où sa suppression d'`install.sh` —
mais il dépose une intention que le daemon valide à la poignée de main IMK du process.

A/B `[OBSERVÉ]`, même bundle, même session, lectures en process neuf :

| Séquence | Résultat |
|---|---|
| register → lancer (sans enable) | `enabled=false` pendant 20 s |
| register → **enable** → lancer | `enabled=true` à t+6 s |
| disable → lancer (sans enable), *contrôle* | `enabled=false` pendant 16 s |

Relire la séquence de la recherche 02 § 1.3 : elle appelait bien `TISEnableInputSource` avant
le lancement, en l'annotant « ne prend pas ». C'est cette annotation qui était fausse, pas la
mesure — l'appel *prend*, avec un différé.

### Piège 2 — `TISCreateInputSourceList` sert une liste mise en cache PAR PROCESS

Une fois le piège 1 corrigé, `install.sh` échouait encore : son `wait-enabled` expirait alors
qu'une lecture externe voyait `enabled=true`. Sonde côte à côte, même run `[OBSERVÉ]` :

```
[fresh  t= 8.0s] enabled=false      ← un process neuf par lecture
[fresh  t=10.0s] enabled=true       ← flip vu
...
[inproc t=10.0s] enabled=false      ← une seule instance, boucle interne
[inproc t=40.0s] enabled=false      ← ne le verra jamais
```

Conséquence directe sur ce ticket : la phrase « `TISEnableInputSource` […] ne change rien, y
compris **relu dans le même process** juste après l'appel — ce qui élimine un simple problème
de cache inter-process » disait l'inverse de la vérité. C'était bien un problème de cache —
intra-process. Toute vérification d'état TIS doit se faire dans un process neuf.

### Ce que ça règle, et ce que ça n'était pas

- **Ce n'était pas l'environnement.** Le redémarrage du 2026-08-19 19:27 et la mise à jour
  26.5/25F71 → **26.6.2/25G83** (installée à ce même redémarrage, `InstallHistory.plist`
  `[OBSERVÉ]`) étaient déjà acquis en début de session : la régression se reproduisait
  identique après. La piste « se déconnecter/reconnecter » est donc **éliminée**, pas juste
  non essayée. Idem TCC : aucune permission n'est en jeu.
- **La sonde ObjC ne pouvait pas trancher.** Elle reproduisait fidèlement le *code*, mais
  était pilotée par la même séquence fautive — d'où sa conclusion trompeuse « la régression
  est dans l'environnement ».
- La poignée de main XPC (`Received setIMKXPCEndpoint:forBundleIdentifier:`) réussissait dans
  les deux cas : elle n'a jamais été un discriminant.
- **Repli Accessibility : sans objet.** La prémisse de [Un canal universel vers le rect du
  caret](02-canal-universel-vers-le-caret.md) tient.

### Correctifs posés

- `install.sh` : `enable` réinséré entre `register` et le lancement, avec l'ordre et ses deux
  raisons en en-tête.
- `Scripts/tisctl.swift` : `wait-enabled` refait — il *forke* une lecture neuve à chaque tour
  (nouveau sous-commande `is-enabled`), fenêtre portée à 40 s. Délai mesuré du flip : 5 à 11 s.

Vérifié bout en bout, `./install.sh` depuis un état propre `[OBSERVÉ]` :
`register → 0`, `enable → 0`, lancement, `enabled`, `select → 0`, état final
`local.bubulle enabled=true selected=true`. Layouts de Frank intacts (`US`, `French`,
`Persian-ISIRI2901`, `SCIM.WBH`, `PressAndHold` inchangés ; `AppleEnabledInputSources`
toujours 6 entrées ; `AppleSelectedInputSources` = `{PressAndHold, French, local.bubulle}`),
exactement comme la recherche 02 l'avait mesuré.

**Nouveau blocage, immédiatement derrière** : `activateServer:` arrive enfin, et le cast
Swift du client échoue — ouvert dans [Le cast du client IMK échoue côté Swift](10-cast-imktextinput-swift.md).
Le rect du caret reste donc non vérifié en conditions réelles.

Environnement restauré (bundle désinstallé, layouts revenus à `{PressAndHold, French}`).
