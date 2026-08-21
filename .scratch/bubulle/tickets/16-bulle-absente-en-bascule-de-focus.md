# Une bulle sur deux ne s'affiche pas en bascule de focus

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:bug`
Status: closed
Assignee: Frank (session wayfinder)
Blocked by: —

## Question

Deux fenêtres Ghostty côte à côte. La bulle s'affiche bien sur la première. On donne le focus à la
seconde : la bulle disparaît de la première et **rien ne s'affiche** sur la seconde. On revient sur
la première : toujours rien. Elle ne revient plus tant qu'on enchaîne les bascules.

Contredit le mode focus de [CONTEXT.md](../../../CONTEXT.md) : chaque prise de focus dans un champ
texte doit poser une bulle sur l'app qui prend le focus.

Livrable : chaque bascule de focus pose une bulle visible, et une boucle de repro qui l'atteste.

## Réponse

**Cause : `BubblePanel.beginFadeOut` retirait de l'écran la bulle qu'on venait de poser.**

La séquence, relevée au log instrumenté :

```
perteDeFocus etat=affichee        <- la fenêtre A perd le focus
beginSortie epoch=7               <- fondu de sortie de 0,40 s lancé
priseDeFocus etat=sortie          <- la fenêtre B prend le focus 3 ms plus tard
cancelFadeAndRepose epoch 7 -> 8  <- on périme le fondu...
panel.beginPose fromAlpha=1.0     <- ...et on pose la bulle de B
panel.fadeOut completion -> orderOut (alpha=1.0)   <- la complétion périmée passe quand même
sortie completion epoch=7 courant=9                <- la garde epoch filtre bien, elle, mais trop tard
```

Le fait mal connu qui fait tout : **AppKit tire le `completionHandler` d'un
`NSAnimationContext.runAnimationGroup` dès qu'une nouvelle animation remplace la propriété animée**,
pas seulement à l'échéance de la durée. `beginPose` réanimait `alphaValue` → la complétion du fondu
partait dans la foulée → `orderOut(nil)` sur la bulle fraîchement posée.

La garde `animationEpoch` du [#08](08-machine-a-etats-de-la-bulle.md) faisait son travail — on la
voit rejeter la transition d'état (`epoch=7 courant=9`). Elle ne couvrait simplement pas le
`orderOut`, qui vit dans `BubblePanel`, hors de sa portée. **Un seul invariant — « cette bulle
est-elle encore la courante ? » — gardé dans un objet, et agi dans l'autre.**

Signature du bug, et ce qui a orienté le diagnostic dès la première mesure : la bulle avait la
**bonne frame et alpha = 1** tout en étant **hors écran**. Donc placement correct puis retrait —
jamais un échec de résolution du rect du caret.

Ce n'est pas propre à deux fenêtres de la même app : ça se produit à **toute** reprise de focus
survenant dans les 0,40 s d'un fondu de sortie, y compris entre apps, et par la transition
`Sortie --notif TIS--> annule le fondu` du [#08](08-machine-a-etats-de-la-bulle.md) tout autant que
par `activateServer:`. La première bascule après un repos marche toujours — il n'y a pas de fondu en
vol à supplanter — ce qui donnait au bug son air intermittent.

**Correctif** : `BubblePanel` porte sa propre `generation`, incrémentée par `beginPose`,
`beginFadeOut` et `vanishImmediately`. La complétion d'un fondu ne retire la fenêtre que si sa
génération est encore la courante. Le panneau devient propriétaire de sa propre péremption, au lieu
de dépendre d'une garde tenue par l'appelant.

**Vérifié** — boucle de repro dans [probes/16-focus-multi-fenetres](../probes/16-focus-multi-fenetres/),
sonde `CGWindowListCopyWindowInfo` sur le pid de Bubulle (aucune permission requise pour
owner/bounds/alpha/onscreen), échantillonnée à 0,15 / 0,30 / 0,55 / 0,85 s après chaque bascule :

| boucle | avant | après |
| --- | --- | --- |
| `./repro.sh axraise` (bascule sans acte) | ROUGE 3/3 passes | VERT 10/10 passes |
| `./repro.sh clic` (vrai clic CGEvent) | ROUGE 1/1 passe | VERT 6/6 passes |

Sur le binaire buggé, 3 des 4 bascules de chaque passe sont rouges — la première marche toujours,
il n'y a pas encore de fondu en vol.

Les deux modes comptent : `axraise` isole la bascule de focus pure, `clic` reproduit le geste réel,
qui incrémente en plus les compteurs d'actes du [#04](04-detecter-la-premiere-frappe.md) et fait
donc partir le fondu *avant* le `deactivateServer:`. Rougeur re-vérifiée en désactivant la garde sur
le binaire corrigé — la boucle repart au rouge, donc elle attrape bien *ce* bug et pas un voisin.

La boucle a d'abord flaké à ~1 passe sur 5, avec un motif distinct de celui du bug : `V V V .`
avec `alpha = 0`, soit une bulle **posée puis fondue normalement**, là où la régression donne
`. . . .` avec `alpha = 1`. Cause : un acte externe — une frappe, un clic, un scroll ailleurs dans
la session pendant les ~12 s de la boucle — qui ferme la bulle tout à fait légitimement. La sonde
rend donc aussi les compteurs d'actes du [#04](04-detecter-la-premiere-frappe.md), et une bascule
pendant laquelle ils bougent est **annulée**, pas comptée en échec. Rougeur re-vérifiée après cet
ajout : l'annulation ne masque pas le bug, qui ne touche pas aux compteurs.

Piège écarté en chemin : `tell application "System Events" to click at {x, y}` ne produit **aucun
événement** ici — la boucle passait au vert sans que rien ne se soit produit, la bulle observée
étant celle d'avant. Le clic doit être posté en `CGEvent` (`clic.swift`), et la boucle vérifie
désormais que la frame suit bien la fenêtre visée.
