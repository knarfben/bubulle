# Lire le cadre du HUD système au vol

Parent: [Bubulle — drapeau à la place des lettres](../MAP.md)
Labels: `wayfinder:research`
Status: closed
Assignee: —
Blocked by: —

## Question

Quand l'utilisateur change d'input source, `CursorUIViewService.xpc` affiche une fenêtre sous le caret. Comment notre process apprend-il **qu'elle vient d'apparaître** et **où exactement**, assez vite pour la recouvrir sans qu'elle soit visible ?

À établir :

- `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)` liste-t-il cette fenêtre ? Sous quel `kCGWindowOwnerName` / `kCGWindowNumber` / `kCGWindowLayer` ? Ses `kCGWindowBounds` sont-ils exploitables tels quels ?
- Quelles permissions TCC sont réellement exigées : les *bounds* et l'*owner* passent-ils sans Screen Recording sur macOS 26, ou seulement le *titre* et la capture d'image sont-ils protégés ?
- Latence : un polling suffit-il, et à quelle fréquence, sachant que le HUD apparaît et s'estompe en ~1 s ? Coût CPU d'un polling à 60 Hz sur la liste de fenêtres.
- Alternative sans polling : les notifications CGS privées (`CGSRegisterNotifyProc`, `kCGSWindowIsVisible` / événements de création de fenêtre) sont-elles utilisables depuis un process utilisateur non privilégié ? Signatures, symboles, exemples open-source connus.
- Le HUD est-il une fenêtre persistante réutilisée (cachée puis re-montrée) ou recréée à chaque fois ? Ça change la stratégie de détection.

Livrable : un fait tranché sur la voie de détection à retenir, plus un bout de code de sonde qui dumpe la fenêtre observée.

## Comments

**Voie retenue : notification distribuée `kTISNotifySelectedKeyboardInputSourceChanged` comme top départ, puis rafale de 250 ms de `SLSGetWindowBounds` (SkyLight privé, `dlsym`) sur les fenêtres `CursorUIViewService`.** Pas de polling permanent, pas de notifications CGS.

Trois faits vérifiés sur la machine qui tranchent :

- `optionOnScreenOnly` **ne liste jamais** cette fenêtre, même quand elle est visiblement peinte (prouvé par capture au même instant). Il faut `.optionAll`. `SLSWindowIsOrderedIn` ment aussi.
- Les notifications CGS (912 ordered-in / 913 ordered-out, identifiées empiriquement) **ne franchissent pas la frontière de process** : un observateur séparé n'en reçoit aucune, `SLSRequestNotificationsForWindows` compris. Le HUD est un remote view hébergé dans la connexion CGS de l'app cliente.
- Aucune permission TCC requise : sans Screen Recording, `kCGWindowBounds`/`OwnerName`/`Layer` passent ; seul `kCGWindowName` est bridé.

Fenêtre **persistante et réutilisée**, une par client texte, créée à la prise de focus. Affichage = `64x64` → `84x77` ; la capsule bleue peinte = `bounds.insetBy(dx: 27.5, dy: 27.5)` = 29x22 pt, centrée sur le caret. Durée d'affichage 1,50 s. Marge entre « cadre final connu » et « HUD affiché » : **17-18 ms**, une frame à 60 Hz.

Trouvailles complètes, mesures et code de sonde : [research/01-cadre-du-hud-au-vol.md](../research/01-cadre-du-hud-au-vol.md)
