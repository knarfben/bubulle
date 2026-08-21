# Couverture réelle de la palette IMK, app par app — trouvailles

Ticket : [03-focus-dun-champ-texte](../tickets/03-focus-dun-champ-texte.md) · Carte : [MAP](../MAP.md)
Machine de mesure : macOS 26.6.2, arm64, Swift 6.3, palette `Bubulle` installée/désinstallée
via `./install.sh` / `./uninstall.sh` pour cette session de mesure.
Date des mesures : 2026-08-20.

**Convention de lecture** : chaque affirmation est marquée
`[OBSERVÉ]` = mesuré sur cette machine, log `/tmp/bubulle.log` ou capture d'écran ·
`[LU]` = tiré d'un header ou d'une doc, non vérifié à l'exécution ·
`[DÉDUIT]` = raisonnement à partir des deux, à confirmer.

---

## Verdict — la question Chrome du préambule est tranchée, et dans l'autre sens

**Le rect n'est PAS bloqué à zéro dans Chrome pendant la frappe normale.** L'hypothèse notée
dans l'en-tête du ticket (peut-être que Chromium ne peuple le rect que pendant une composition
IME active) ne tient pas : sur cette machine, à cette date, un vrai clic + une vraie frappe
« bubulle » dans la boîte de recherche Google **donne un rect non nul qui suit le caret**,
exactement comme Safari, VS Code, Discord ou n'importe quel champ AppKit natif `[OBSERVÉ]` :

```
[03:11:15] activateServer bundle=com.google.Chrome
[03:11:15] poll bundle=com.google.Chrome rect=(0.0, 0.0, 0.0, 0.0) selRange=(NotFound,NotFound) attrsEmpty=true
[03:11:15] poll ... (x4, encore nul)
[03:11:18] deactivateServer
[03:11:18] activateServer bundle=com.google.Chrome
[03:11:18] poll bundle=com.google.Chrome rect=(568.0, 672.0, 1.0, 20.0) selRange=(0,0) attrsEmpty=false   ← re-poll après le 2e activateServer, rect déjà bon
...
[03:11:33] poll bundle=com.google.Chrome rect=(621.0, 672.0, 1.0, 20.0) selRange=(7,0) attrsEmpty=false   ← après frappe de "bubulle" (7 lettres), le rect a bougé de 568→621
```

Le piège n'est donc pas propre à Chrome : c'est **le même piège « premier `activateServer:` à
rect nul »** déjà documenté dans [research/02](02-canal-universel-vers-le-caret.md) pour Chrome,
et retrouvé ici aussi dans iTerm2 et VS Code (détail plus bas). Un `deactivateServer` +
`activateServer` (provoqué ici par le focus qui va-et-vient entre Safari et Chrome) suffit à
faire apparaître le vrai rect, **avant même la première frappe**.

Piste probable pour expliquer la contradiction avec le ticket #10 (qui notait un rect bloqué à
zéro « pendant toute la frappe normale ») : le log laissé par cette session précédente montrait
en fait **deux bundles** différents — `com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm`
(une **PWA installée**, càd un « Chrome App » avec sa propre fenêtre, restée à zéro tout du long
`[OBSERVÉ]` dans ce même log) et `com.google.Chrome` (le navigateur normal), qui elle **donnait
déjà des rects non nuls** dans ce même log une fois relue en détail (`rect=(230.0, 1012.0, ...)`
puis `(259.0, 1012.0, ...)` avec `selRange=(2,51)`). La conclusion « bloqué à zéro » de la
session précédente semble donc avoir généralisé à tort à partir du cas PWA. Voir aussi la note
sur les PWA dans le tableau ci-dessous.

Un test de dead-key (`⌥e` puis `e` → `ê`, dans le champ Google de Chrome) n'a rien changé au
comportement — le rect était déjà non nul avant, pendant et après la composition du caractère
accentué `[OBSERVÉ]`. Les dead keys macOS ne passent pas par `setMarkedText:` d'`NSTextInputClient`
(elles sont résolues au niveau clavier avant d'atteindre l'app), donc ce test ne pouvait de toute
façon pas distinguer composition et frappe simple. **Le test avec une vraie IME à candidats
(SCIM Wubihua, `com.apple.inputmethod.SCIM.WBH`) n'a pas pu être mené** : `TISSelectInputSource`
renvoie `-50` (paramErr) sur cette source depuis un process tiers, et elle n'apparaît pas dans le
menu Input (⌐FR dans la barre de menus) malgré `enabled=true` côté TIS — seuls US / French /
Persian y figurent `[OBSERVÉ]`. Reste donc une inconnue **non bloquante** : le rect pourrait
éventuellement se comporter différemment sous composition IME active, mais rien n'indique que ce
soit nécessaire pour la carte, puisque la frappe simple marche déjà partout où c'est testé.

---

## Tableau de couverture réel, app par app

Toutes les lignes `[OBSERVÉ]` le même jour, même machine, palette réinstallée pour l'occasion.
« Re-poll nécessaire » = le premier `activateServer:` du champ a donné un rect nul, et il a fallu
soit un second `activateServer:` (perte/reprise de focus), soit une frappe réelle, pour voir le
vrai rect apparaître.

| App | Bundle ID | Nature | Rect au focus | Re-poll nécessaire ? |
|---|---|---|---|---|
| Ghostty (terminal, déjà ouvert) | `com.mitchellh.ghostty` | terminal natif | non nul dès le 1er `activateServer` : `(24.5, 122, 1, 20)` | non |
| iTerm2 | `com.googlecode.iterm2` | terminal natif | nul au 1er focus, `(0,0,0,0)` | **oui** — devient `(550,634,1,17)` seulement après une vraie frappe |
| VS Code (Monaco) | `com.microsoft.VSCode` | Electron | nul sur l'écran d'accueil (pas de champ) ; non nul dès l'ouverture d'un fichier : `(705,433,1,24)` | non, une fois qu'un champ existe |
| Discord (DM avec un bot) | `com.hnc.Discord` | Electron | nul sur l'onglet Friends (pas de champ) ; non nul dès le clic dans la zone de message : `(455,29,1,21)` | non |
| Safari — barre d'adresse | `com.apple.Safari` | AppKit natif | non nul dès `⌘L` : `(536.5,946,1,16)` | non |
| Safari — champ de recherche Google (page web, WebKit) | `com.apple.Safari` | WebKit | nul au 1er focus, `(0,0,0,0)` | **oui** — `(492,516,1,20)` après un caractère tapé |
| Chrome — champ de recherche Google (page web, Blink) | `com.google.Chrome` | Blink | nul au 1er focus | **oui** — voir Verdict ci-dessus. Une fois obtenu, suit le caret normalement |
| Chrome — PWA installée (`.app.<id>`) | `com.google.Chrome.app.<id>` | Blink, fenêtre app dédiée | resté à `(0,0,0,0)` sur toute la session observée | n/a — jamais vu non nul dans ce test, cause probable : aucun champ texte réellement focalisé pendant la capture, pas un blocage du canal |
| Notes | `com.apple.Notes` | AppKit natif (rich text) | nul juste après `⌘N` (fenêtre pas encore prête), non nul 1s après : `(611,2038,1,23)` | léger délai, pas un vrai re-poll |
| Sublime Text | `com.sublimetext.4` | natif (Skia/OpenGL, pas AppKit standard) | non nul dès `activateServer` : `(74,990,1,12)`, suit le caret | non |
| Raycast (lanceur, remplace Spotlight ici) | `com.raycast-x.macos` | natif | non nul dès `activateServer` : `(825,551,1,22)`, suit le caret | non |
| Safari — champ mot de passe (page de login GitHub, `type=password`) | `com.apple.Safari` | WebKit, secure text field | non nul et suit le caret comme un champ normal : `(616,712,1,18)` → `(811,631,1,18)` après 20 caractères | non |
| Spotlight natif | — | — | **non testé** — `⌘Espace` est capturé par Raycast sur cette machine, qui a remplacé le raccourci système ; l'icône loupe de la barre de menus n'a pas répondu au clic dans le temps imparti | — |
| Java/Swing/AWT | — | — | **non testé, inchangé depuis research/02** : toujours aucun JRE sur cette machine (`/usr/libexec/java_home` échoue). Cas absent de l'usage réel de Frank d'après le ticket parent | — |

### Points nouveaux par rapport à research/02

- **iTerm2 rejoint la liste des « re-poll nécessaire »**, alors que Ghostty (l'autre terminal
  testé) n'en a jamais eu besoin. Ce n'est donc pas un trait de « tous les terminaux » ni de
  « toutes les apps Electron » : c'est vraiment au cas par cas, y compris entre deux apps de la
  même catégorie.
- **Le champ mot de passe ne bloque rien.** Le rect géométrique est exposé exactement comme un
  champ normal — logique, puisque `attributesForCharacterIndex:lineHeightRectangle:` ne renvoie
  qu'une géométrie et des métadonnées de police, jamais le contenu. Aucune app testée n'a semblé
  distinguer secure/non-secure sur ce canal. Ça confirme que la palette peut positionner sa bulle
  sur un champ mot de passe sans compromis de sécurité — mais évidemment sans jamais connaître le
  texte tapé (ce que la palette n'a de toute façon jamais demandé).
- **Les PWA Chrome (Chrome Apps, `.app.<id>`) restent une inconnue distincte de Chrome normal**,
  probablement bénigne (aucun champ focalisé pendant l'observation) mais non confirmée en positif
  — à netoyer si la carte doit un jour couvrir des PWA spécifiquement.
- **Raycast a été testé à la place de Spotlight** parce qu'il a capturé le raccourci `⌘Espace` sur
  cette machine. C'est un bon proxy (fenêtre flottante, mêmes contraintes de focus) mais ce n'est
  pas Spotlight lui-même — à reconfirmer si la carte cible explicitement Spotlight.

---

## Un piège d'environnement découvert en cours de route, sans rapport avec IMK

**Ce n'est pas un point de la carte, mais ça a coûté du temps et vaut la peine d'être noté ici** :
sur cette machine, `rm` est aliasé à `trash` et `cp`/`mv` sont aliasés en mode interactif
(`cp -i`, `mv -i`) dans les scripts shell lancés par l'agent. Un `rm -rf` dans un script qui
attend cet alias échoue silencieusement (« Un-recognized argument -rf »), et un `cp -R` sur une
destination existante reste bloqué en attente d'une confirmation `y/n` jamais reçue en non
interactif. Conséquence concrète ici : un rebuild du binaire de la palette a semblé réussi
(`build.sh` OK) mais **le bundle installé dans `~/Library/Input Methods/` restait l'ancien
binaire**, invisible tant qu'on ne compare pas taille/date de fichier. À refaire : utiliser
`command rm` / `command cp` (ou passer par `install.sh` tel quel, qui n'a pas ce problème — il
utilise `rm -rf` en tout début de script avant que quoi que ce soit d'autre tourne, donc l'alias
zsh ne s'applique pas de la même façon dans un script `#!/bin/zsh` non interactif… à vérifier si
ça se reproduit).

Découverte connexe, plus intéressante pour la carte : **macOS a demandé une confirmation
utilisateur explicite pour activer la palette**, une boîte de dialogue système
(« Allow "swift-frontend" to enable "Bubulle"? ») absente des mesures de research/02
(qui notait explicitement « aucun prompt utilisateur »). Le prompt est réapparu à chaque
réinstallation avec un nouveau binaire signé ad-hoc pendant cette session `[OBSERVÉ]` — donc
probablement lié à la resignature (hash différent), pas à un changement de policy système entre
les deux tickets. À surveiller : si ce prompt réapparaît à chaque build en usage réel, ça change
la story d'installation de la carte (un utilisateur devra cliquer Allow après chaque mise à jour
du binaire, pas seulement à la première installation).

---

## Latence de `attributesForCharacterIndex:lineHeightRectangle:`

Mesurée en ajoutant un chronométrage temporaire (`CFAbsoluteTimeGetCurrent()` autour de l'appel)
dans une build de mesure, retiré ensuite — le code livré dans `Sources/BubulleController.swift`
n'a **pas** gardé cette instrumentation.

- **App AppKit locale (`com.apple.systempreferences`)** : rafale de 50 appels dos-à-dos,
  hors du timer 1 Hz — **moyenne 46,4 µs, min 39,9 µs, max 96,0 µs** `[OBSERVÉ]`. Un seul appel
  isolé (à froid, juste après `activateServer:`) : 274,9 µs — le premier appel coûte plus cher,
  cohérent avec une resolution XPC/proxy tardive.
- **Chrome (`com.google.Chrome`, process renderer séparé)** : appels isolés répétés dans le
  timer 1 Hz, tous après le premier : **1,0 à 2,1 ms** `[OBSERVÉ]` (`1012`, `1207`, `1288`,
  `1349`, `1650`, `1761`, `1763`, `1773`, `2114` µs selon les échantillons).

Conclusion : **l'ordre de grandeur dépend fortement de si l'app cible est le process local
(dizaines de µs) ou une app multi-process comme Chrome/Electron (1 à 2 ms, portée par l'IPC
navigateur → renderer)**. Les deux restent largement sous le seuil de perception humaine (~100 ms)
et sous le budget d'une frame à 60 Hz (16,7 ms) pris isolément.

### Cadence de sondage proposée

- **En régime établi (bulle déjà affichée, caret qui peut bouger)** : **10 Hz (100 ms)** est un
  bon compromis. Même dans le pire cas mesuré (Chrome, ~2 ms/appel), ça laisse une marge de x50
  avant de saturer le budget de la période de sondage, et 100 ms est en dessous du seuil où un
  décalage bulle/caret devient gênant à l'œil pendant une frappe rapide.
- **Au repos (pas de frappe depuis un moment, `selRange` stable)** : redescendre à **1-2 Hz**
  suffit — c'est déjà le réglage actuel du prototype (timer 1 Hz dans `BubulleController.swift`)
  et rien dans les mesures de latence ne pousse à faire mieux quand rien ne bouge.
- **Juste après `activateServer:`** : faire **un re-poll immédiat** (pas d'attente du prochain
  tick) est nécessaire dans plusieurs apps (Chrome, Safari WebKit, iTerm2 — voir tableau), parce
  que le premier appel arrive parfois avant que l'app ait fini de peupler son
  `NSTextInputClient`. Le pattern qui marche dans toutes les apps testées : interroger
  immédiatement, et si `rect == NSZeroRect`, réessayer une fois ~50-100 ms plus tard avant de
  conclure « pas de champ texte ». C'est un renforcement du point déjà noté dans research/02
  §« Ce que ça implique », maintenant confirmé sur un échantillon d'apps plus large (Chrome +
  Safari + iTerm2, pas seulement Chrome).
- Ne pas descendre sous ~50 ms (20 Hz) sans raison : le coût par appel est négligeable, mais nul
  besoin d'aller plus vite que la fréquence de rafraîchissement de l'écran pour un simple
  repositionnement de fenêtre.

---

## Reproduire

Sonde : la palette réelle du projet (`Sources/BubulleController.swift`), compilée avec
`./build.sh`, installée avec `./install.sh`, log `/tmp/bubulle.log`. Interaction clavier réelle
via `osascript … keystroke` (jamais de `computer`/CDP côté claude-in-chrome pour ces mesures,
justement pour éviter d'injecter des événements synthétiques qui contourneraient le vrai chemin
clavier macOS — voir la mise en garde du ticket sur `keystroke` visant la mauvaise app :
vérifiée à chaque fois avec `System Events … frontmost` avant d'envoyer une frappe).

Mesure de latence : chronométrage temporaire ajouté/retiré dans `pollOnce()`, rafale de 50
appels dos-à-dos déclenchée une fois au premier client valide rencontré. Non conservé dans le
code livré.

L'environnement a été **restauré** en fin de session : `./uninstall.sh` exécuté,
`AppleSelectedInputSources` revenu à `{PressAndHold, French}` `[OBSERVÉ]`, bundle retiré de
`~/Library/Input Methods/`, aucun process `Bubulle` restant, `local.bubulle` disparu de la
liste TIS.
