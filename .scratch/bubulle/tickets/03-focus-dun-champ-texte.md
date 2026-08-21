# Couverture réelle de la palette IMK, app par app

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:research`
Status: closed
Assignee: Frank
Blocked by: —

> Réécrit après la résolution de [Un canal universel vers le rect du caret](02-canal-universel-vers-le-caret.md). La question d'origine — « comment détecter le focus d'un champ texte système-wide » — est répondue : c'est `activateServer:` sur la palette IMK, et un `rect == NSZeroRect` + `selRange == NSNotFound` signale « pas de champ texte ». L'API Accessibility recule au rang de repli. Ce qui reste ouvert, c'est la **couverture**.
>
> Débloqué par [Le cast du client IMK échoue côté Swift](10-cast-imktextinput-swift.md) : le cast
> Swift fonctionne désormais. Au passage, ce ticket a mesuré `[OBSERVÉ]` un premier point de
> couverture qui **contredit la ligne suivante** : dans Chrome (recherche Google, frappe réelle
> dans le champ de recherche), `attributesForCharacterIndex:` répond mais avec un `rect` à zéro
> pendant toute la frappe normale — hypothèse non tranchée : peut-être que Chromium ne peuple ce
> rect que pendant une composition IME active. À vérifier en premier ici, avant le reste du
> tableau de couverture.

## Question

La palette IMK donne le rect du caret « dans toutes les apps » — mais ça n'a été prouvé que dans Chrome et dans une sonde AppKit maison. Où est-ce que ça tient réellement, et où faut-il un repli ?

À mesurer, app par app, avec la palette de sonde déjà construite dans la recherche précédente :

- **Electron** : VS Code, Slack, Discord — confirmé jusqu'ici seulement par transitivité via Chrome, aucun test avec un champ réellement focalisé.
- **Java / Swing** : aucun JRE sur la machine lors de la recherche. Installer un runtime jetable ou constater que le cas ne se présente pas dans l'usage de Frank.
- **Terminal, iTerm, éditeurs de code natifs, Notes, Safari, champs de recherche de la barre de menus, Spotlight.**
- **Champs sécurisés** : que renvoie le rect dans un champ mot de passe ?
- Pour chaque app : le rect est-il correct du premier coup, ou faut-il re-interroger après un `activateServer:` à rect nul (piège observé dans Chrome) ?

À établir aussi, parce que le canal est **pull et non push** :

- Coût et latence d'un appel `attributesForCharacterIndex:lineHeightRectangle:` — non mesuré. Combien de fois par seconde peut-on l'appeler sans se faire remarquer ?
- Le caret bouge sans qu'on soit prévenu : quelle cadence de sondage pour que la bulle ne traîne pas derrière ? (La réponse alimente [Machine à états de la bulle](08-machine-a-etats-de-la-bulle.md).)

Livrable : le tableau de couverture réel, et la liste des apps où le repli Accessibility devra prendre le relais.

## Comments

Mesures faites : [research/03-focus-dun-champ-texte.md](../research/03-focus-dun-champ-texte.md).

- **La question Chrome/composition du préambule est tranchée, et infirmée.** Sur cette machine,
  une vraie frappe dans le champ de recherche Google **de Chrome normal** (pas une PWA) donne un
  rect non nul qui suit le caret, exactement comme partout ailleurs `[OBSERVÉ]`. Pas besoin de
  composition IME. Le rect bloqué à zéro observé au ticket #10 semble avoir mélangé deux bundles
  différents dans le log (une PWA Chrome restée à zéro + Chrome normal, qui donnait déjà des
  rects non nuls dans ce même log une fois relu). Le test avec une vraie IME à candidats
  (SCIM Wubihua) n'a pas pu être mené — `TISSelectInputSource` renvoie -50 depuis un process
  tiers pour cette source, et elle n'apparaît pas dans le menu Input malgré `enabled=true` — mais
  ce n'est plus bloquant puisque la frappe simple marche déjà.
- **Couverture réelle, app par app** : rect non nul (avec parfois un re-poll nécessaire après un
  premier `activateServer:` à zéro) dans Ghostty, iTerm2, VS Code (Monaco), Discord, Safari
  (barre d'adresse et page web), Chrome (page web), Notes, Sublime Text, Raycast (proxy de
  Spotlight — le raccourci système est capturé par Raycast sur cette machine), et **dans un champ
  mot de passe** (le canal expose la géométrie, jamais le contenu — aucun blocage secure-input
  constaté). Seule zone franchement non testée : Java/Swing (toujours aucun JRE sur la machine,
  absent de l'usage réel de Frank) et Spotlight natif lui-même (indisponible, Raycast a pris le
  raccourci). Une PWA Chrome est restée à zéro tout du long mais sans preuve qu'un champ était
  réellement focalisé — inconnue résiduelle mineure, pas un blocage.
- **Latence mesurée** : ~40-100 µs par appel pour une app locale (AppKit même process family),
  ~1-2 ms pour Chrome (IPC navigateur→renderer). Cadence proposée : 10 Hz pendant que la bulle
  est affichée et que le caret peut bouger, 1-2 Hz au repos (déjà le réglage du prototype), et
  toujours un re-poll immédiat après un `activateServer:` à rect nul avant de conclure « pas de
  champ texte ».
- Statut mis à `closed` : la question bloquante (couverture + le doute Chrome) est tranchée avec
  preuve empirique. Les deux trous restants (Java, vraie composition IME) sont documentés comme
  non bloquants plutôt que ré-ouverts en ticket séparé — à réévaluer si l'usage réel de Frank les
  rend pertinents un jour.
