# install.sh laisse parfois deux instances de la palette

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:task`
Status: closed
Assignee: Frank (session wayfinder)
Blocked by: —

## Question

`install.sh` termine parfois avec **deux process Bubulle vivants**, donc deux `IMKServer` et deux
bulles superposées — contre la règle « une seule bulle à la fois, jamais deux » de
[CONTEXT.md](../../../CONTEXT.md).

Relevé dans `/tmp/bubulle.log` : deux lignes `Bubulle démarré` à la même seconde, le
2026-08-20 20:48:24 (session du [#12](12-implementer-la-machine-a-etats.md), donc **antérieur** au
[#14](14-geometrie-hors-cas-nominal.md)) puis trois fois de suite le 2026-08-21 vers 07:13.

Cause probable, à confirmer : `install.sh` lance le binaire lui-même **puis** appelle
`TISSelectInputSource` (l'ordre est imposé par le [#09](09-regression-auto-enable-palette.md)) — et
la sélection fait lancer une seconde instance par le système quand la palette n'était pas déjà
sélectionnée. Quand elle l'était déjà, la sélection est un no-op et il n'y a qu'une instance : ça
expliquerait le caractère intermittent.

Deux effets invisibles à l'œil mais réels : deux fenêtres animées au même endroit, et deux jeux de
compteurs d'actes. Le second process ne se relance pas tout seul après un `pkill` — c'est bien le
lancement manuel qui double.

Livrable : `install.sh` termine avec exactement une instance, ou la règle est révisée si deux
instances sont bénignes.

## Réponse

**Cause confirmée — mais pas celle du ticket.** La cause probable écrite ci-dessus (la
*sélection* qui lancerait une seconde instance) est **infirmée** : reproduite 5/5 en relançant
`install.sh` alors que la source était encore sélectionnée d'une session précédente — la
sélection y est un no-op, comme prévu — et pourtant 2 instances à chaque fois, toujours
démarrées à la même seconde.

La vraie cause est le **`pkill` du haut de script**, pas le `select` du bas : si la source est
encore `selected` au moment où `install.sh` tue le process en cours, le superviseur système
(`imklaunchagent`) le relance tout seul dans l'instant — en plus de la relance manuelle faite
quelques lignes plus bas par le script. Deux relances indépendantes de la même source
sélectionnée = deux instances. Quand la source n'est *pas* sélectionnée (juste après un
`uninstall.sh`, ou à la toute première installation), il n'y a pas de superviseur à réveiller :
une seule instance.

**Correctif** : `install.sh` désélectionne et désactive la source *avant* le `pkill`, comme le
fait déjà `uninstall.sh`, pour couper le superviseur avant de tuer le process. Le reste de la
séquence (enregistrer, activer, lancer, attendre le flip, sélectionner) est inchangé — l'ordre
imposé par le [#09](09-regression-auto-enable-palette.md) tient toujours.

**Vérifié sur machine réelle** : 5/5 relances à chaud (source déjà sélectionnée, le scénario qui
reproduisait 100% du bug) → 1 instance à chaque fois ; cycle `uninstall.sh` puis `install.sh`
(source pas encore sélectionnée) → 1 instance. TIS termine `enabled=true selected=true` dans les
deux cas. 8/8 au total, aucune régression du chemin déjà couvert par le [#12](12-implementer-la-machine-a-etats.md).

La règle « une seule bulle à la fois » de [CONTEXT.md](../../../CONTEXT.md) n'a pas eu besoin
d'être révisée : deux instances n'étaient pas bénignes (deux `IMKServer`, deux jeux de compteurs
d'actes), et le bug est éliminé à la source plutôt que masqué en aval.
