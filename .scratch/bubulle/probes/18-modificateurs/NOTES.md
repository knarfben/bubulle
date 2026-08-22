# Sonde #18 — lire *quel* modificateur est enfoncé, sans permission

Mesure bloquante du [ticket 18](../../tickets/18-le-rappel-a-la-demande.md).

## Lancer

```
./build.sh
open .build/Probe18.app
tail -f /tmp/bubulle-probe18.log
```

Puis, à la main : ⌃⌃ rapide, ⌃ isolés espacés, et ⌃⌃ pendant un `sudo -v`. Les événements
synthétiques ne conviennent pas — le [#01](../../research/01-cadre-du-hud-au-vol.md) a établi
qu'ils ne suivent pas les chemins système. `./cout` re-mesure les coûts seuls, hors bundle.

Le bundle est **volontairement séparé et jamais autorisé**, lancé par `open` pour être son propre
*responsible process* : lancé depuis un terminal, il hériterait des permissions de celui-ci et la
mesure ne voudrait rien dire (piège documenté au #01).

## Ce que ça mesure

Trois canaux côte à côte, échantillonnés à 60 Hz :

- `CGEventSource.flagsState(.combinedSessionState)` — les modificateurs enfoncés **maintenant** ;
- `NSEvent.modifierFlags` — la même chose, autre vocabulaire ;
- `CGEventSourceCounterForEventType(.flagsChanged)` — combien d'événements modificateur ont eu
  lieu, sans dire lesquels.

Plus une machine à double-tap (appui → relâche → appui, fenêtre 500 ms, annulée par tout `keyDown`
ou `mouseDown`) et un chronomètre sur chaque appel. `IsSecureEventInputEnabled()` est journalisé
sur chaque ligne, sans quoi on déduit du minutage — ce que la première passe faisait, à tort.

## Résultats

- **Aucune permission requise** : les trois préflights à `false`, les lectures d'état justes quand
  même. `flagsState` et `modifierFlags` n'ont **jamais divergé**.
- **Coûts** : `flagsState` 4 ns, `modifierFlags` 28 ns, compteur 4 ns. Attention au piège : sous
  `-O`, si le résultat n'est pas consommé, l'optimiseur supprime l'appel et la mesure ment.
  `cout.swift` accumule dans un puits imprimé.
- **Détection** : 5/5, Δ de 149 à 233 ms — la fenêtre retenue au ticket passe à 350 ms.
- **Le compteur `flagsChanged` décroche sous secure input** : `+0` sur quatre transitions d'état
  réelles, puis `+4` groupés 100 ms plus tard. L'état reste juste et immédiat, et le double-⌃ est
  bien détecté pendant le secure input. Asymétrie avec le [#04](../../tickets/04-detecter-la-premiere-frappe.md),
  qui l'avait établi pour `keyDown` — ça ne se transporte pas à `flagsChanged`.
