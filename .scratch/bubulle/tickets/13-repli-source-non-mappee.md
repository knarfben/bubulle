# Repli pour une source d'entrée non mappée

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:grilling`
Status: closed
Assignee: Frank
Blocked by: —

## Question

[#06 — Inventaire des input sources et assets drapeaux](06-inventaire-sources-et-drapeaux.md) mappe les
quatre sources réellement sélectionnées par Frank aujourd'hui vers un drapeau. Que fait Bubulle
quand `activateServer:`/le changement de langue livre un `inputSourceID` absent de
`Resources/flags.json` — un cinquième clavier ajouté plus tard, ou un des claviers désactivés vus
au dump (`Czech`, `Dvorak`, etc.) réactivé un jour ?

Options en jeu (non tranchées) :

- Afficher les deux lettres système, comme le HUD — mais ça réintroduit le comportement que
  Bubulle existe pour recouvrir, et suppose qu'on ait sous la main une abréviation correcte
  (pas juste les 2 premières lettres de l'ID).
- Ne rien afficher (pas de bulle du tout pour cette source) — simple, mais silencieux : Frank ne
  saurait pas qu'un clavier manque tant qu'il ne l'aurait pas remarqué à l'usage.
  L'émoji est écarté (décision de charting), donc ce n'est plus un repli disponible.
- Un glyphe générique (point d'interrogation, pastille neutre) — signale l'absence sans
  prétendre être un drapeau.

Livrable : une décision explicite, actée dans `Resources/flags.json` ou dans le code qui le lit.

## Comments

**Résolu** en `/grilling` + `/domain-modeling` avec Frank. Neuf décisions — et **deux des trois options du
ticket sont mortes de fait, pas d'arbitrage**.

### Ce que les mesures ont tué

Probe `probes/13-repli/`, 311 sources catégorie clavier dumpées, macOS 26.6.2 (25G83).

- **Aucune abréviation deux lettres n'existe dans TIS.** La liste des propriétés publiques est
  complète — Category, InputSourceID, BundleID, InputModeID, LocalizedName, Languages,
  UnicodeKeyLayoutData, IconRef, IconImageURL, plus les booléens — et le badge `US`/`FR`/`فا` du
  HUD n'en fait pas partie. « Afficher les deux lettres comme le système » demanderait une table
  codée en dur : même charge d'entretien que `flags.json`, pour un résultat strictement pire.
- **`kTISPropertyIconRef` est une image de clavier générique**, identique pour toutes les
  dispositions : `US`, `Czech`, `German` et `Arabic` rendent le **même PNG au byte près**
  (`md5 5f082c4d03ebfa360cd0327755728c52`). Ni un drapeau, ni les lettres.
- **`kTISPropertyIconImageURL` n'existe que pour 42 sources sur 311** — les input *methods*
  (SCIM, Kotoeri, Korean), jamais un `com.apple.keylayout.*` — et c'est un glyphe 拼/あ/한.

Ce qui reste debout : **`Languages[0]`**, code de langue primaire fiable (`fr` pour French-PC,
ABC-AZERTY, Canadian-CSA, Swiss French ; `en` pour US International, British, Colemak, les quatre
Dvorak ; `zh-Hans` pour tous les SCIM ; `fa` pour Afghan Dari), **vide** pour une poignée de shims
(`PinyinKeyboard`, `WubihuaKeyboard`, `3SetHangul`). Ça ouvre une quatrième option, absente du
ticket, et c'est elle qui devient la réponse.

### L'échelle de résolution

À la notification TIS comme à `activateServer:`, pour l'`inputSourceID` courant :

1. **Correspondance exacte** dans `flags.json` → ce drapeau.
2. **Valeur `null` explicite** → **source muette** : aucune bulle, aucun log.
3. **Correspondance par langue primaire** : `Languages[0]` de la source courante contre une table
   **déduite de `flags.json`** (`en→us.svg`, `fr→fr.svg`, `zh-Hans→cn.svg`, `fa→ir.svg`).
4. **Rien** — source muette, plus une ligne de log.

L'échelon 3 fait tomber juste, sans toucher un fichier : French-PC, ABC-AZERTY, Swiss French,
Canadian-CSA, US International, British, Colemak, les quatre Dvorak, Pinyin, Wubi, Shuangpin,
Afghan Dari. Le repli réel ne sert plus qu'à une langue **véritablement neuve** (`de`, `ru`, `he`…).

### Les neuf décisions

1. **Deux échelons avant le repli : ID exact, puis langue primaire.** La table langue→drapeau est
   *déduite* de `flags.json`, pas déclarée : le fichier reste seule source de vérité, et ajouter un
   drapeau étend automatiquement sa langue.
2. **Le repli est « rien », dans les deux modes.** En **mode langue**, ne rien poser laisse le HUD
   système à découvert — deux lettres justes, disparition à 1,50 s : le comportement d'avant
   Bubulle, jamais faux, jamais pire. En **mode focus**, un glyphe muet ne dit pas dans quelle
   langue on va taper, donc **ne rend pas le service** (décision 4 du #08) ; et comme aucune bulle
   n'a de plafond de durée (décision 7 du #08), ce serait une capsule « ? » persistante à *chaque*
   prise de focus. C'est ça qui écarte le glyphe générique — pas un manque d'assets.
3. **Le silence n'est pas silencieux : une ligne de log, dédupliquée par ID pour la session** — ID
   littéral, nom localisé, langue primaire : exactement ce qu'il faut pour compléter `flags.json`.
   `Log.write` existe déjà, coût nul.
4. **Un asset mappé mais introuvable ou illisible tombe dans le même état.** Un seul état « pas de
   drapeau à peindre », quelle qu'en soit la cause : une branche à écrire, une à tester ; la ligne
   de log nomme la cause. Cas immédiat — `build.sh` n'embarque pas encore `Flags/` dans le bundle
   (noté au #06), donc **aujourd'hui les quatre assets sont introuvables à l'exécution** : le chemin
   de repli est le chemin nominal tant que #12 n'a pas branché l'embarquement.
5. **Collision de langue → la langue sort de la table.** Le jour où deux sources mappées déclarent
   la même `Languages[0]` (`British→gb.svg` à côté de `US→us.svg`), `en` ne tombe plus par langue ;
   les deux IDs restent mappés exactement. **Mesuré** : `JSONSerialization` ne préserve pas l'ordre
   des clés et cet ordre **change d'un lancement à l'autre** (3 runs, 2 ordres) — une règle « le
   premier du fichier gagne » aurait été non déterministe. Une entrée `null` ne porte pas d'asset,
   donc ne collisionne jamais.
6. **`null` comme valeur = silence explicite**, court-circuitant les échelons 3 et 4. C'est
   l'échappatoire de l'échelon langue : `"com.apple.keylayout.Canadian-CSA": null` évite d'hériter
   du drapeau français pour un clavier canadien. Et ça sépare « pas encore mappé » (accident →
   loggué) de « volontairement muet » (choix → silencieux). Conséquence pour #12 : le JSON se
   décode en `[String: String?]`, pas `[String: String]`.
7. **Une bulle vivante qui bascule vers une source muette disparaît net, sans fondu.** Seule
   transition où le contenu de la bulle est *connu-faux* : pendant les 0,40 s du fondu normal, un
   drapeau FR resterait posé sur le HUD système affichant déjà « DE » — un drapeau faux recouvrant
   l'information juste, exactement ce que Bubulle existe pour éviter. **Amendement au #08**, dont la
   règle « notif TIS → re-pose, drapeau mis à jour, plancher réarmé » supposait qu'il y ait toujours
   un drapeau à poser.
8. **#13 ne livre que la décision.** `flags.json` n'a rien à changer aujourd'hui — aucun `null` à
   écrire, les quatre entrées restent identiques — et le code qui lit `flags.json` n'existe pas
   encore : `BubulleController.swift` ne connaît ni drapeau ni JSON. #12 écrira le chargeur avec le
   reste de la machine à états.
9. **Le domaine gagne un terme : « source muette »**, posé dans [CONTEXT.md](../../../CONTEXT.md).

### Faits acquis en chemin, utiles ailleurs

- **`TISCopyCurrentKeyboardInputSource()` n'est PAS frappé par le cache par process** qui rend
  `TISCreateInputSourceList` inutilisable dans un process long (#09). Mesuré : un process vivant,
  abonné à `kTISNotifySelectedKeyboardInputSourceChanged`, a lu correctement 4 bascules successives
  (French→US→Persian→US→French) avec `inputSourceID`, `LocalizedName` et `Languages[0]` justes à
  chaque fois — et la source courante était **déjà à jour au moment où la notification arrive**.
  C'est donc le canal de lecture de la langue pour #12, sans aucun fork.
- **Il ne remonte jamais une palette** : `cat=TISCategoryKeyboardInputSource` sur les 5 lectures.
  Bubulle ne se verra donc jamais lui-même, ni `CharacterPaletteIM`, ni `PressAndHold`.
- **`TISSelectInputSource` sur un input method renvoie `-50`** depuis un process CLI ordinaire
  (vérifié sur `com.apple.inputmethod.SCIM.WBH`) : seuls les `keylayout` se sélectionnent par
  programme.

### Ce que la résolution ouvre

Conséquence directe de ce `-50` : **impossible de confirmer quel ID le chinois remonte**.
`com.apple.inputmethod.SCIM.WBH` (mappé, `lang0=zh-Hans`) ou son sosie
`com.apple.keylayout.WubihuaKeyboard` (`lang0` **vide**, non mappé) ? Si c'est le second, le clavier
chinois quotidien de Frank devient une source muette et **n'affiche rien** — les deux échelons le
manquent, celui de la langue compris. Vérification de 20 s (lancer `probes/13-repli/watch`, faire
⌘Espace vers le chinois à la main), ajoutée à
[#12 — Implémenter la machine à états dans la palette](12-implementer-la-machine-a-etats.md).

Probe : `probes/13-repli/` — `dump.swift`, `icon.swift`, `watch.swift`, `order.swift`.
