# Bubulle

Utilitaire macOS local : une **bulle au drapeau** posée sur le caret, à la place des deux lettres
du HUD système de changement d'input source. Elle apparaît dans trois cas — changement de langue
(elle *recouvre* le HUD système, indiscernable de lui), prise de focus d'un champ texte, et retour
de l'invite dans un terminal — et disparaît à la première frappe, au clic, au scroll ou à la perte
de focus.

Le vocabulaire du domaine est dans [CONTEXT.md](CONTEXT.md). Les décisions sont dans les tickets,
depuis [.scratch/bubulle/MAP.md](.scratch/bubulle/MAP.md).

## Prérequis

- macOS 13+ déclaré, mais **tout a été mesuré sur macOS 26.6.2 (25G83) / arm64**. Le projet utilise
  des comportements TIS/IMK non documentés : une version plus ancienne n'a jamais été testée.
- Xcode Command Line Tools (`swiftc`, `swift`, `codesign`). `xcode-select --install` si absent.
- Ghostty, **uniquement** si tu veux le mode invite (liste blanche en dur, voir plus bas).

**Aucune permission système n'est demandée** — ni Accessibilité, ni Surveillance de la saisie. La
position du caret arrive par le canal `NSTextInputClient`/TSM, ouvert parce que Bubulle est
enregistré comme input method de catégorie *palette*. C'est le cœur du design, pas un détail.

## Installer

```sh
./install.sh
```

Le script compile, pose le bundle dans `~/Library/Input Methods/Bubulle.app`, l'enregistre auprès
de TIS, l'active, le lance, attend le flip `enabled`, puis le sélectionne.

> **N'inverse pas ces étapes.** L'ordre est le seul contenu réel du script, et chaque étape a coûté
> un ticket : `TISEnableInputSource` doit être appelé **avant** le lancement du process (il renvoie
> 0 sans effet visible, mais arme une intention que le daemon valide à la poignée de main IMK —
> sans lui le flip `enabled` n'arrive jamais, ticket #09) ; le process doit tourner **avant**
> `TISSelectInputSource`, sinon `-50` ; et il faut désélectionner **avant** de tuer une instance,
> sinon `imklaunchagent` en relance une deuxième (ticket #15). L'en-tête de `install.sh` redit tout ça.

Bubulle se sélectionne **en parallèle** de tes layouts clavier, il ne les remplace pas et n'est
jamais sur le chemin des touches.

## Vérifier

```sh
tail -f /tmp/bubulle.log
```

Au démarrage : `Bubulle démarré, pid=…`. Ensuite, bascule de langue ou clique dans un champ texte —
une capsule avec drapeau doit se poser sur le caret.

## Adapter `flags.json` à ta machine

`Resources/flags.json` mappe les **quatre input sources de Frank**. Sur une autre machine, la
plupart des claviers tomberont juste quand même : la résolution se fait par échelons (ticket #13).

1. ID exact dans `flags.json` → ce drapeau.
2. Valeur `null` explicite → source muette, aucune bulle, aucun log.
3. Langue primaire (`Languages[0]`) contre une table **déduite** de `flags.json`
   (`en→us.svg`, `fr→fr.svg`, `zh-Hans→cn.svg`, `fa→ir.svg`) → French-PC, ABC-AZERTY, Colemak,
   Dvorak, British, Pinyin, Wubi… tombent juste sans toucher un fichier.
4. Rien → source muette, **plus une ligne de log**.

Pour mapper une langue vraiment neuve (`de`, `ru`, `he`…), bascule dessus une fois et lis le log :

```
source muette (non mappée) id=com.apple.keylayout.German nom=Allemand langue=de
```

Ajoute le SVG dans `Resources/Flags/`, l'entrée dans `Resources/flags.json`, relance `./install.sh`.
`null` sert à taire volontairement une source (ex. `"com.apple.keylayout.Canadian-CSA": null` pour
ne pas hériter du drapeau français).

## Désinstaller

```sh
./uninstall.sh
```

Désélectionne, désactive, tue le process, retire le bundle. Le cycle est réversible :
`AppleSelectedInputSources` revient à tes layouts normaux.

## Outils

- `./build.sh` — compile et pose le bundle dans `.build/`, sans installer.
- `swift Scripts/tisctl.swift list|register|enable|select|deselect|disable|is-enabled|wait-enabled` —
  pilotage TIS à la main, utile pour diagnostiquer.

## Ce que ça ne fait pas

- **Pas de notarization, signature ad-hoc, usage strictement local.** Frameworks privés et
  comportements non documentés assumés : **ça peut casser à chaque mise à jour de macOS**.
- **Mode invite = Ghostty seulement** — liste blanche en dur dans `Sources/BubbleStateMachine.swift`.
  iTerm2 a été écarté sur mesure, pas par oubli.
- Le HUD système est **recouvert**, jamais neutralisé. Si Bubulle ne pose rien en mode langue, tu
  revois les deux lettres système : c'est le repli, et il n'est jamais faux.

## Si tu es un agent

Avant de modifier quoi que ce soit : lis [CONTEXT.md](CONTEXT.md), puis
[.scratch/bubulle/MAP.md](.scratch/bubulle/MAP.md). Les 17 tickets sont clos et portent les mesures
qui justifient le code — notamment que **toute lecture d'état TIS doit se faire dans un process
neuf**, sauf `TISCopyCurrentKeyboardInputSource()` : une boucle de poll interne ne voit jamais un
changement d'état, et ça a déjà déguisé un bug de séquence en régression système pendant une
session entière (#09).

Le seul juge est « ça marche sur la machine ». Installe, regarde `/tmp/bubulle.log`, teste à l'œil.
