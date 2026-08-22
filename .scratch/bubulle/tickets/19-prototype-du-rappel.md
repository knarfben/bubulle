# Prototype du rappel

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:prototype`
Status: open
Assignee: —
Blocked by: — *(la mesure bloquante du [#18](18-le-rappel-a-la-demande.md) est levée)*

## Question

Le [#18](18-le-rappel-a-la-demande.md) a tranché onze décisions et levé son risque de fond : le
double-⌃ est détectable sans permission, à 4 ns la lecture, y compris sous secure input. Restent
deux inconnues, qui ne se règlent ni au papier ni à la sonde.

1. **Le rendu.** « ~200 pt de haut, opacité ~0,5, ~500 ms en tout » sont des chiffres de papier.
   Le [#05](05-clone-visuel-du-hud.md) a réglé le clone du HUD par prototype jetable plutôt que par
   raisonnement ; même méthode ici.
2. **Les faux positifs en usage réel.** La sonde a validé le geste en conditions de test — quelques
   minutes, gestes délibérés. Personne ne sait si ⌃⌃ part tout seul sur huit heures de travail
   normal. C'est la seule mesure qui pourrait faire revenir sur le choix du modificateur
   (décision 2 du #18), et elle ne s'obtient qu'en portant le prototype une journée.

Livrable : une app autonome que Frank laisse tourner, dont il règle les chiffres sans repasser par
un agent, et un verdict sur ces deux points.

## Ce qui est déjà tranché — ne pas rouvrir

Les onze décisions du [#18](18-le-rappel-a-la-demande.md) tiennent. En particulier :

- **Geste** : double ⌃ Control, fenêtre **350 ms**, disqualifié par tout `keyDown` ou `mouseDown`
  entre les deux appuis (compteurs du [#04](04-detecter-la-premiere-frappe.md)).
- **Guet** : un seul timer permanent à **60 Hz** sur `CGEventSource.flagsState(.combinedSessionState)`.
  Ne pas réintroduire le compteur `flagsChanged` comme signal de réveil — il **décroche sous secure
  input**, c'est mesuré au #18.
- **Écran** : centre de l'écran de la fenêtre focalisée, via
  `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` filtré sur le PID de `frontmostApplication`
  (474 µs, aucune permission — [#01](01-cadre-du-hud-au-vol.md)).
- **Registre** : massif et bref. Le prototype fait varier les chiffres, pas le registre.
- **Aucune permission** : ni Accessibility, ni Input Monitoring, ni Screen Recording. Si le
  prototype en réclame une, c'est qu'il a pris un mauvais chemin.

## À faire

Une app autonome dans `probes/18-modificateurs/prototype/`, bâtie sur le même moule que la sonde
(`build.sh`, bundle `.app`, `LSUIElement`, signature ad-hoc, lancée par `open`) — **pas** dans
`Sources/` : le rappel n'entre dans la palette qu'une fois réglé.

- Reprendre la détection de `probe.swift`, fenêtre à 350 ms.
- Poser un `NSPanel` non-activating, `ignoresMouseEvents`, `.fullScreenAuxiliary` +
  `.moveToActiveSpace` (le [#12](12-implementer-la-machine-a-etats.md) a payé cher l'absence du
  second : bulle invisible sans erreur hors de son Space d'origine), drapeau SVG de
  `Resources/Flags/` mis à l'échelle.
- **Chiffres réglables en tête de fichier** — hauteur, opacité, durées d'entrée / maintien / sortie.
  C'est le point du livrable : Frank itère seul.
- Journaliser chaque déclenchement dans `/tmp/bubulle-proto19.log` avec l'horodatage, l'app au
  premier plan et la source d'entrée courante — c'est le journal qui répondra sur les faux positifs.

## Ce qu'on attend en retour

- Les chiffres retenus pour hauteur, opacité et durées.
- Le nombre de déclenchements non voulus sur une journée, et dans quelles apps — le journal les
  nomme.
- Si les faux positifs sont nombreux : rouvrir la décision 2 du #18 (⌥⌥, ⌃⌃, Globe) avec des
  données, pas des suppositions.
