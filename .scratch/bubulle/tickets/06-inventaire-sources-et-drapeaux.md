# Inventaire des input sources et assets drapeaux

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:task`
Status: closed
Assignee: Frank
Blocked by: —

## Question

Rien à décider : il faut la table de correspondance exacte, sans quoi aucune bulle ne peut afficher le bon drapeau.

Travail :

- Dumper via `TISCreateInputSourceList` les input sources **réellement sélectionnables** avec leur `kTISPropertyInputSourceID` littéral, leur `kTISPropertyLocalizedName` et leur `kTISPropertyInputSourceLanguages`. Les valeurs lues dans `com.apple.HIToolbox` (`KeyboardLayout Name`) ne sont pas les IDs utilisés à l'exécution.
- Produire les 4 assets **en SVG embarqué** : US, France, Chine, Iran. Tranché au prototype — le vectoriel bat l'emoji à cette taille, mais on ne dessine pas l'emblème iranien à la main. Cible de rendu : ~13 pt de haut dans une capsule de 29×22 pt, donc des tracés simplifiés qui tiennent en tout petit.
- Écrire le fichier de config (JSON) qui mappe `inputSourceID → asset`, rechargeable sans recompiler.
- Noter le comportement attendu pour une source non mappée (repli : afficher les 2 lettres comme le système ? ne rien afficher ?) — proposition à soumettre, pas à trancher seul. L'emoji ayant été écarté, il n'est plus un repli possible.

Livrable : le JSON de mapping + les assets dans le repo, et les IDs littéraux confirmés.

## Comments

**Résolu.** Table de correspondance dumpée par un petit script Swift jetable
(`TISCreateInputSourceList`, filtré `IsSelectCapable && IsEnabled`), croisée avec
`defaults read com.apple.HIToolbox AppleEnabledInputSources` pour ne garder que les sources
*réellement* choisies par Frank (le dump TIS brut listait aussi `com.apple.inputmethod.AinuIM.Ainu`
et `Kotoeri.KanaTyping/RomajiTyping.Japanese` comme `enabled=true` — des compagnons système
auto-activés, absents d'`AppleEnabledInputSources`, donc jamais dans le sélecteur de langue).

Les IDs littéraux confirmés — identiques à ceux notés au charting, donc pas de surprise :

| `kTISPropertyInputSourceID` | `kTISPropertyLocalizedName` | `kTISPropertyInputSourceLanguages` | Drapeau |
|---|---|---|---|
| `com.apple.keylayout.US` | U.S. | `en, …` | US |
| `com.apple.keylayout.French` | French | `fr, …` | France |
| `com.apple.inputmethod.SCIM.WBH` | Stroke – Simplified | `zh-Hans` | Chine |
| `com.apple.keylayout.Persian-ISIRI2901` | Persian – Standard | `fa, ar, mzn` | Iran |

(`com.apple.CharacterPaletteIM` et `com.apple.PressAndHold` apparaissent aussi dans
`AppleEnabledInputSources` mais sont catégorie `TISCategoryPaletteInputSource`, pas
`TISCategoryKeyboardInputSource` — jamais un changement de langue, donc pas mappés.)

Livré dans le repo :

- `Resources/flags.json` — mapping `inputSourceID → chemin d'asset`, rechargeable sans recompiler.
- `Resources/Flags/{us,fr,cn,ir}.svg` — SVG embarqués, `viewBox="0 0 30 20"` (ratio 3:2),
  tracés simplifiés pour rester lisibles à ~13 pt de haut : US à 5 bandes (pas 13) + canton
  uni avec une grille de points au lieu d'étoiles individuelles ; Chine à une grande étoile
  + 4 petites (formule polygone standard, positions/rotations approximées) ; Iran tricolore
  seul, sans emblème (conforme à la décision de charting) ; France tricolore trivial.
  `build.sh` ne les embarque pas encore dans le bundle — hors périmètre de ce ticket, à
  brancher avec l'intégration visuelle (ticket 12).

Repli pour une source non mappée : **pas tranché ici**, comme demandé — proposition envoyée à
[#13 — Repli pour une source d'entrée non mappée](13-repli-source-non-mappee.md).
