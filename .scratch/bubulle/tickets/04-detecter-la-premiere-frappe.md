# Détecter la première frappe, y compris en secure input

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:research`
Status: closed
Assignee: —
Blocked by: —

## Question

Le drapeau disparaît à la première frappe. Comment l'observer sans perturber la saisie, et que faire quand macOS nous aveugle ?

À établir :

- `CGEventTap` en `listenOnly` sur `keyDown` : permission requise (Accessibility), impact sur la latence de frappe, placement (`cgSessionEventTap` vs `cgAnnotatedSessionEventTap`).
- Comportement en **secure input** (`EnableSecureEventInput`) : le tap cesse de recevoir les événements. Peut-on au moins savoir qu'on y est, via `IsSecureEventInputEnabled()` ? Si oui, on peut basculer sur le timeout dès l'entrée dans un champ mot de passe plutôt que d'attendre l'expiration bêtement.
- Quels événements comptent comme « frappe » : caractères seulement, ou aussi flèches, retour arrière, modificateurs seuls (non) ?
- Le tap survit-il à un `timeout` système qui le désactive (`kCGEventTapDisabledByTimeout`) ? Stratégie de réarmement.
- Valeur du timeout de sécurité : point à trancher avec Frank sur prototype, pas à décider ici.

Livrable : la mécanique de détection de frappe retenue et le comportement exact en champ sécurisé.

## Comments

Trouvailles : [research/04-detecter-la-premiere-frappe.md](../research/04-detecter-la-premiere-frappe.md) — mesuré sur macOS 26.5 / Swift 6.3.1, 8 sondes, taps toujours en `listenOnly`.

**Deux détecteurs, et le principal n'est pas celui qu'on croyait.** Le tap (`kCGSessionEventTap`, `listenOnly`, thread dédié) est strictement passif : un callback qui dort 400 ms ne retarde la livraison de la frappe que de 4,7 ms. Permission requise = **Input Monitoring** (`CGPreflightListenEventAccess()`, qui ne prompte pas), pas Accessibility — le header du SDK est périmé sur ce point, comme sur « tap HID réservé à root » (créé sans root ici). Mais **`CGEventSourceCounterForEventType(.combinedSessionState, .keyDown)` fonctionne sans aucune permission** (vérifié en relançant le même binaire sous launchd) **et continue de compter sous secure input**. C'est lui la source de vérité ; le tap n'est qu'un accélérateur (immédiat vs ≤ 16 ms à 60 Hz), pour 0,005 µs par appel.

**Secure input** : le tap est aveugle aux trois emplacements, HID compris — descendre plus bas ne contourne rien. Mais il **reste `enabled`** et reprend seul à la sortie, sans réarmement. `IsSecureEventInputEnabled()` répond juste, sans permission (à déclarer soi-même : aucun header public ne l'expose, lier `-framework Carbon`), et `CGSessionCopyCurrentDictionary()["kCGSSessionSecureInputPID"]` donne le pid du détenteur. Donc **on ne bascule pas sur le timeout** dans un champ mot de passe : on bascule sur le compteur, et la bulle disparaît à la vraie première frappe, comme partout ailleurs.

**Frappe = tout `kCGEventKeyDown`**, sans exception. Les modificateurs seuls sont des `flagsChanged` et les touches média ne génèrent rien : ils sont exclus gratuitement par le type d'événement. Flèches et retour arrière comptent.

**Timeout** : `kCGEventTapDisabledByTimeout` **n'a jamais été reçu** en trois tentatives, alors que le tap passait bien à `enabled=false`. Réarmement retenu = chien de garde qui poll `CGEventTapIsEnabled()` toutes les 2 s, la notification n'étant gérée que par acquit de conscience.

À vérifier une fois bubulle lancé : le compteur sous secure input avec un **clavier physique** (testé ici avec des frappes synthétiques uniquement), et le retour de `CGEventTapCreate` avant l'octroi de la permission.
