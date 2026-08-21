# Lire le cadre du HUD système au vol — trouvailles

Ticket : [01-cadre-du-hud-au-vol](../tickets/01-cadre-du-hud-au-vol.md) · Carte : [MAP](../MAP.md)

Machine de vérification : macOS 26.5 (25F71), arm64, Swift 6.3.1, deux écrans
(interne 1728×1117 @2x + DELL U2419H 1920×1080 @1x). `CursorUIViewService` pid 79519.

**Convention de lecture** : ✅ = observé moi-même sur cette machine · 📄 = lu dans un header du
SDK · ❓ = non testé.

---

## Réponse courte

**Voie retenue : notification distribuée `kTISNotifySelectedKeyboardInputSourceChanged` comme
déclencheur, puis rafale de `SLSGetWindowBounds` (SkyLight privé, via `dlsym`) sur les fenêtres de
`CursorUIViewService` pour lire le cadre. Pas de polling permanent, pas de notification CGS.**

Les trois faits qui tranchent :

1. ✅ **`CGWindowListCopyWindowInfo(.optionOnScreenOnly)` ne liste JAMAIS cette fenêtre**, même
   quand le HUD est visiblement peint à l'écran (prouvé par capture d'écran au même instant).
   `.optionAll` la liste, elle. Toute stratégie basée sur « elle apparaît dans la liste onscreen »
   est morte.
2. ✅ **Les notifications CGS ne sortent pas du process propriétaire.** Un observateur séparé qui
   enregistre `SLSRegisterNotifyProc` pour les types 912/913 (ordered in/out) ne reçoit **rien**
   pour le HUD — y compris après un `SLSRequestNotificationsForWindows` qui retourne pourtant 0.
   Le process qui a le focus, lui, les reçoit. Un agent séparé n'a donc pas de voie événementielle
   côté fenêtres.
3. ✅ **Le signal d'input source arrive ~20 ms avant que le cadre soit connu et ~40 ms avant que la
   fenêtre soit affichée.** C'est ce qui rend le recouvrement jouable : marge nette mesurée
   **~17-18 ms**, soit une frame à 60 Hz. Serré mais positif.

Aucune permission TCC n'est requise : ✅ un process sans Screen Recording lit `kCGWindowBounds`,
`kCGWindowOwnerName`, `kCGWindowNumber`, `kCGWindowLayer` sans problème. Seul `kCGWindowName` est
bridé.

---

## Anatomie de la fenêtre HUD

✅ Observé de façon reproductible sur une dizaine d'exécutions.

| Propriété | Valeur |
|---|---|
| `kCGWindowOwnerName` | `CursorUIViewService` |
| `kCGWindowOwnerPID` | 79519 (le pid du service) |
| `kCGWindowLayer` | **3** quand le HUD est déployé · **0** quand la fenêtre est au repos |
| `kCGWindowName` | `""` (chaîne vide) quand Screen Recording est accordé · absent sinon |
| `kCGWindowAlpha` | 1.0 en permanence (aucun fondu visible via cette clé) |
| `kCGWindowBounds` déployé | `84 × 77` pt, origine haut-gauche CG |
| `kCGWindowBounds` au repos | `64 × 64` pt, à une position de parking |
| `kCGWindowStoreType` | 1 · `kCGWindowMemoryUsage` 2368 |

### Le cadre est exploitable tel quel, moyennant un inset constant

✅ Mesuré au pixel. Capture d'écran de exactement `R=484,642,84,77` pendant l'affichage, puis
profil par ligne des pixels bleus saturés :

- capsule bleue visible = **58 × 44 px @2x = 29 × 22 pt**
- elle occupe x 27,5…56,5 pt et y 27,5…49,5 pt dans un cadre de 84 × 77

soit **une marge uniforme de 27,5 pt sur les quatre côtés** (27,5 + 29 + 27,5 = 84 ✓ ;
27,5 + 22 + 27,5 = 77 ✓). Le reste du cadre, c'est la place réservée à l'ombre portée.

```
kCGWindowBounds  (484, 642, 84, 77)   <- ce que renvoie l'API
capsule peinte   (511.5, 669.5, 29, 22)  = bounds.insetBy(dx: 27.5, dy: 27.5)
```

✅ Vérifié aussi que la capsule est **centrée sur le caret en x** : caret à x=526 (via
`firstRect(forCharacterRange:)` d'un `NSTextView` dans un champ témoin), centre du cadre
484 + 42 = **526**. Exact.

✅ Le cadre est identique (84 × 77, capsule 29 × 22) pour `com.apple.keylayout.US` et pour
`com.apple.keylayout.Persian-ISIRI2901` — donc stable pour les libellés à deux glyphes. ❓ Non
testé pour `com.apple.inputmethod.SCIM.WBH` (absent des sources sélectionnables au moment du test :
seules US, French et Persian – Standard étaient `IsEnabled && IsSelectCapable`).

Captures de référence : `hud_exact.png` (US, « US ») et `hud_alt.png` (Persian, « فا ») dans le
répertoire de sondes.

### Persistante et réutilisée, une par client texte

✅ C'est le point qui change la stratégie, et la réponse est nette :

- Au repos, `CursorUIViewService` détient **~20 fenêtres** de 64×64 (ou 54×54 pour les plus
  anciennes), garées à des positions fixes (`0,617`, `0,1053`, `1155,134`, `93,-987`…). L'une
  d'elles est sur le second écran — cohérent avec « une fenêtre par client texte, garée près de
  son propriétaire ».
- ✅ **Une nouvelle fenêtre est créée quand une app prend le focus texte** : au lancement de ma
  sonde avec un `NSTextField` focalisé, une fenêtre neuve apparaît dans la liste ~250 ms après
  l'activation (`nouvelles: [81758]`).
- ✅ **Elle est ensuite réutilisée** pour tous les affichages suivants du HUD dans cette app :
  même `kCGWindowNumber` sur deux bascules successives, redimensionnée/déplacée puis
  ordered-in / ordered-out. Elle n'est pas recréée.

Conséquence pratique : on peut se contenter d'un `CGWindowListCopyWindowInfo(.optionAll)` **rare**
(sur `NSWorkspace.didActivateApplicationNotification`, avec ~250 ms de délai) pour tenir à jour la
liste des candidats, et ne jamais le refaire dans le chemin chaud.

---

## `optionOnScreenOnly` : non, et c'est contre-intuitif

✅ La démonstration est directe. Au moment exact où le HUD est peint :

```
DICT COMPLET: [... "kCGWindowLayer": 3, "kCGWindowNumber": 81289,
               "kCGWindowBounds": {X=484; Y=642; Width=84; Height=77}, ...]
présente dans optionOnScreenOnly ? false
screencapture -R 484,642,84,77 status=0
```

et le PNG produit à ce même instant montre la capsule bleue « US ». Donc : peinte à l'écran,
absente de la liste onscreen.

✅ Même verdict côté SkyLight : `SLSWindowIsOrderedIn(cid, wid, &b)` renvoie `b = false` sur cette
fenêtre depuis un process tiers, alors qu'elle est visible. L'appel coûte ~9,7 µs (aller-retour
réel), donc il répond bien — il répond juste faux pour une fenêtre étrangère. À ne pas utiliser
comme critère.

**Le seul indicateur fiable depuis l'extérieur est le cadre lui-même** : `64×64` → `84×77` =
apparition, `84×77` → `64×64` = disparition.

📄 Note SDK : `CGWindowListCreateImage` est *obsoleted in macOS 15.0* (`CGWindow.h:271`,
« Please use ScreenCaptureKit instead ») — inutilisable pour sonder ; j'ai utilisé
`/usr/sbin/screencapture -R` à la place.

---

## Permissions TCC : rien n'est requis

✅ Testé proprement en construisant un bundle `.app` séparé (`local.bubulle.tccsonde.v1`, jamais
autorisé) et en le lançant via `open`, pour qu'il soit son propre *responsible process* et
n'hérite pas de l'autorisation du terminal.

| | avec Screen Recording | **sans** Screen Recording |
|---|---|---|
| `CGPreflightScreenCaptureAccess()` | `true` | `false` |
| `.optionAll` → nb fenêtres | 398 | **381** |
| dont `kCGWindowName` non-nil | 397 | **21** |
| `kCGWindowOwnerName` / `OwnerPID` | ✅ | ✅ |
| `kCGWindowBounds` | ✅ | ✅ |
| `kCGWindowNumber` / `Layer` | ✅ | ✅ |
| fenêtres `CursorUIViewService` visibles | 20 | **20** |
| `SLSGetWindowBounds(wid)` sur fenêtre tierce | `rc=0` | **`rc=0`** |

**Conclusion : seuls les titres (`kCGWindowName`) et la capture d'image sont protégés.** Le cadre
et le propriétaire passent sans aucune permission. Bubulle n'a donc besoin ni de Screen Recording
ni d'Accessibility pour ce ticket.

(Effet de bord noté ✅ mais sans conséquence : `kCGWindowSharingState` vaut 0 sans permission et 1
avec.)

---

## Latence et coût

### Chronologie mesurée (moyenne de plusieurs exécutions, horloges alignées sur la notif TIS)

```
t+0 ms     TISSelectInputSource() appelé
t+6…14 ms  notification distribuée kTISNotifySelectedKeyboardInputSourceChanged   <-- notre top départ
t+22…23 ms la fenêtre HUD passe 64x64 -> 84x77, ENCORE à sa position de parking
t+44 ms    elle se déplace à sa position finale sous le caret        <-- cadre final connu
t+39…62 ms notification CGS 912 (ordered in) : le HUD devient visible <-- deadline
t+~250 ms  notification CGS 827 (fin d'animation / redraw)
t+1,49…1,51 s   84x77 -> 64x64 : le HUD se replie
```

✅ **Marge nette entre « je connais le cadre final » et « le HUD est affiché » : 17-18 ms**, mesurée
deux fois (44,4 → 62,5 et 22,1 → 39,4). Une frame à 60 Hz.

✅ Durée d'affichage du HUD : **1,49 à 1,51 s** — très stable, et le compteur repart à zéro à chaque
nouveau changement.

✅ Cas où le caret n'a pas bougé depuis le dernier HUD : la fenêtre est déjà à la bonne position, il
n'y a **qu'un seul événement** (le redimensionnement), à t+22 ms. Cas où elle bouge : **deux
événements**, redimensionnement sur place puis déplacement. Il faut donc attendre la stabilisation
et non déclencher sur le premier changement — sinon on affiche notre bulle à la position de parking
(`0,1040` dans mon relevé, soit en bas à gauche de l'écran : bien visible).

### Coût des API (mesuré, moyennes sur 30 à 5000 appels)

| Appel | Coût | Verdict |
|---|---|---|
| `CGWindowListCopyWindowInfo(.optionAll)` | **2 187 µs** | à réserver aux rafraîchissements rares |
| `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` | **474 µs** | inutile ici de toute façon |
| `CGWindowListCreateDescriptionFromArray([wid])` | **82,5 µs** | acceptable, mais 8× plus cher que SLS |
| `SLSGetWindowBounds` — fenêtre **du process courant** | **0,1 µs** | lecture en mémoire partagée |
| `SLSGetWindowBounds` — fenêtre **tierce** | **~11 µs** | aller-retour, mais bon marché |
| `SLSGetWindowLevel` | 0,1 µs | |
| `SLSWindowIsOrderedIn` | 9,7 µs | et renvoie une valeur fausse ici |
| balayage des 21 fenêtres `CursorUIViewService` | **226 µs** | |

**Un polling permanent à 60 Hz sur `.optionAll` coûterait 13 % d'un cœur — inacceptable.** À
l'inverse, un balayage SLS des 21 fenêtres à 60 Hz coûte 1,4 % d'un cœur, et une rafale de 250 ms
déclenchée par la notif TIS coûte ~0 en régime permanent.

**Donc : pas de polling permanent. Notification TIS + rafale.** C'est la réponse à la question
« un polling suffit-il, et à quelle fréquence » : le polling est nécessaire (voir ci-dessous) mais
seulement par salves de ~250 ms, à ~3 kHz (300 µs entre balayages), ce qui reste sous 4 % d'un cœur
*pendant la salve seulement*.

---

## Notifications CGS privées : disponibles, mais inutilisables ici

✅ Tous les symboles se résolvent par `dlsym` sur `CoreGraphics` **et** sur
`/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`, sans SIP à contourner :

```
CoreGraphics : CGSRegisterNotifyProc CGSRegisterConnectionNotifyProc CGSMainConnectionID
               CGSGetWindowLevel CGSGetScreenRectForWindow CGSGetWindowBounds CGSCopyWindowProperty
               CGSGetWindowAlpha CGSWindowIsOrderedIn CGSGetWindowList CGSGetOnScreenWindowList
               CGSCopyWindowsWithOptionsAndTags
SkyLight     : les mêmes, plus SLSMainConnectionID SLSRegisterNotifyProc SLSGetWindowBounds
               SLSGetWindowLevel SLSWindowIsOrderedIn SLSGetWindowOwner SLSConnectionGetPID
               SLSRequestNotificationsForWindows SLSCopyWindowsWithOptionsAndTags
               SLSGetWindowTags SLSGetWindowSubLevel SLSCopyAssociatedWindows …
```

Signature retenue (déduite empiriquement, elle fonctionne) :

```swift
typealias FnRegister = @convention(c) (
    @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void,
    UInt32, UnsafeMutableRawPointer?) -> Int32
// SLSRegisterNotifyProc(handler, type, context) -> CGError
// le handler reçoit (type, data, dataLength, context) ; data pointe sur un UInt32 = window id
```

✅ **Types de notification identifiés empiriquement** (en balayant les types 700-1000 et 1200-1400
et en corrélant avec le cycle de vie du HUD) :

| Type | Signification déduite |
|---|---|
| **912** | fenêtre *ordered in* (devient visible) — payload = window id |
| **913** | fenêtre *ordered out* |
| **827** | émis ~240 ms après 912 et après 913 — probablement fin d'animation / redraw |
| 723, 904, 906, 1201, 1308, 1322, 1325, 1326 | trafic non corrélé au HUD |

✅ **Et pourtant : inutilisables.** Un process observateur séparé, tournant en parallèle et abonné
aux types 806/807/812/813/815/816/827/912/913, n'a reçu **aucun** événement pour la fenêtre HUD
pendant que le process qui avait le focus en recevait quatre. `SLSRequestNotificationsForWindows`
appelé avec les 20 window ids retourne `0` (succès) et ne change rien.

Explication cohérente avec ce que j'ai mesuré : ✅ `SLSGetWindowOwner` + `SLSConnectionGetPID` sur
la fenêtre HUD renvoient **le pid de l'app qui a le focus**, pas celui de `CursorUIViewService` —
alors que `CGWindowList` l'attribue à `CursorUIViewService`. Le HUD est un *remote view* hébergé
dans la connexion CGS de l'app cliente, dont le contenu est peint par le service XPC. Les
notify procs CGS ne livrent que les événements de sa propre connexion, donc ceux de l'app hôte.

> ❓ Non exploré : injecter dans chaque app cliente pour capter ses notifications CGS. C'est le mur
> SIP, et la carte l'a déjà écarté.

---

## La voie retenue, en détail

```
NSWorkspace.didActivateApplicationNotification
    └─ +250 ms ─> CGWindowListCopyWindowInfo(.optionAll), filtre owner == "CursorUIViewService"
                  (2,2 ms, quelques fois par minute)  -> liste des window ids candidats

DistributedNotificationCenter : kTISNotifySelectedKeyboardInputSourceChanged
    └─ démarre une rafale de 250 ms
         boucle à ~3 kHz : SLSGetWindowBounds(cid, wid) pour chaque candidat (~11 µs)
           - passage 64x64 -> 84x77                  = le HUD se prépare
           - origine stable pendant ~2 balayages     = cadre final  ==> on couvre
           - retour 84x77 -> 64x64 (~1,5 s plus tard) = on se retire
```

Placement : `bounds.insetBy(dx: 27.5, dy: 27.5)` donne la capsule à recouvrir. Le cadre CG est en
origine haut-gauche ; conversion vers `NSScreen` (origine bas-gauche) nécessaire — voir le point
« Positionnement multi-écrans et Retina » resté ouvert dans la carte. Notre fenêtre doit être à un
niveau > 3 (`kCGWindowLayer` du HUD).

**Pourquoi pas l'alternative « on ignore le HUD et on se place nous-mêmes sur le caret »** : le
caret n'est accessible partout que via le canal `NSTextInputClient`/TSM, que nous n'avons pas
depuis un process tiers — c'est précisément le constat de charting. Lire le cadre du HUD, c'est
lire la position du caret par procuration, y compris dans Chrome et Electron. C'est ce qui donne
sa valeur à cette voie.

---

## Code de sonde

Toutes les sondes sont dans
`/private/tmp/claude-501/-Users-frankbenady-dev-streamlink-scripts-bubulle/e1872384-d63d-434c-b846-cd225d4ab2aa/scratchpad/probes/`
(répertoire éphémère). Les deux qui comptent sont reproduites ici.

### `p16_final.swift` — la voie recommandée, bout en bout

Process observateur, jamais au premier plan, aucune permission. Dumpe le cadre observé et la
capsule déduite.

```swift
import AppKit
import Carbon
import CoreGraphics
import Foundation

typealias FnMainConn  = @convention(c) () -> Int32
typealias FnGetBounds = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> Int32
let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)!
let SLSMainConnectionID = unsafeBitCast(dlsym(sky, "SLSMainConnectionID")!, to: FnMainConn.self)
let SLSGetWindowBounds  = unsafeBitCast(dlsym(sky, "SLSGetWindowBounds")!,  to: FnGetBounds.self)
let cid = SLSMainConnectionID()

/// marge constante entre kCGWindowBounds et la capsule bleue réellement peinte
let CAPSULE_INSET: CGFloat = 27.5
/// taille du cadre quand le HUD est déployé (libellé à 2 glyphes)
let EXPANDED = CGSize(width: 84, height: 77)

final class Box: @unchecked Sendable {
    let lock = NSLock()
    var ids: [UInt32] = []
    var last: [UInt32: CGRect] = [:]
    var burstUntil: Double = 0
}
let B = Box()

func refreshWindowList() {
    let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    var ids: [UInt32] = []
    for w in all where (w[kCGWindowOwnerName as String] as? String) == "CursorUIViewService" {
        if let n = w[kCGWindowNumber as String] as? Int { ids.append(UInt32(n)) }
    }
    B.lock.lock(); B.ids = ids; B.lock.unlock()
}
refreshWindowList()

// le service crée la fenêtre du nouveau client peu après la prise de focus
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { refreshWindowList() } }

// le top départ : ~20 ms d'avance sur le cadre, ~40 ms sur l'affichage
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil, queue: nil
) { _ in
    B.lock.lock(); B.burstUntil = now() + 250; B.lock.unlock()
}

let poller = Thread {
    while true {
        B.lock.lock(); let ids = B.ids; let burst = now() < B.burstUntil; B.lock.unlock()
        for wid in ids {
            var r = CGRect.zero
            guard SLSGetWindowBounds(cid, wid, &r) == 0 else { continue }
            B.lock.lock(); let prev = B.last[wid]; B.last[wid] = r; B.lock.unlock()
            guard let prev, prev != r else { continue }
            if r.size == EXPANDED {
                // ATTENTION : peut être l'étape intermédiaire (déploiement à la position de
                // parking). Attendre 2 balayages sans changement d'origine avant de couvrir.
                print("cadre  = \(r)")
                print("capsule = \(r.insetBy(dx: CAPSULE_INSET, dy: CAPSULE_INSET))")
            } else if prev.size == EXPANDED {
                print("HUD replié (\(r))")
            }
        }
        usleep(burst ? 300 : 20_000)
    }
}
poller.stackSize = 1 << 20
poller.start()
RunLoop.main.run()
```

Sortie réelle d'une exécution (bascule French → US puis retour, déclenchée par un process tiers) :

```
t=   3142.4  liste rafraîchie : 22 fenêtres CursorUIViewService en 4.13 ms  (nouvelles: [81758])
t=   4151.6  ### TIS : changement d'input source détecté — début de la rafale
t=   4174.8  wid=81758  (0,1053 64x64) -> (0,1040 84x77)      [+23.1 ms après TIS]
t=   4196.0  wid=81758  (0,1040 84x77) -> (484,642 84x77)     [+44.4 ms après TIS]
t=   4196.1      cadre CG (haut-gauche) = (484,642 84x77)
t=   4196.1      capsule visible        = (512,670 29x22)
t=   5662.3  wid=81758  (484,642 84x77) -> (484,655 64x64)    [+1510.6 ms après TIS]
t=   6673.7  ### TIS : changement d'input source détecté — début de la rafale
t=   6695.9  wid=81758  (484,655 64x64) -> (484,642 84x77)    [+22.1 ms après TIS]
t=   8187.4  wid=81758  (484,642 84x77) -> (484,655 64x64)    [+1513.6 ms après TIS]
```

### `p8_capture.swift` — prouve que la fenêtre est peinte alors qu'elle est absente de `optionOnScreenOnly`

Fournit son propre champ texte (donc un caret), bascule l'input source, identifie la fenêtre dont
le cadre a changé, dumpe son dict complet, interroge `optionOnScreenOnly`, puis capture exactement
sa région.

```swift
// (extrait — le corps complet crée une NSWindow + NSTextField, l'active, et restaure
//  l'input source et l'app frontale d'origine à la fin)
let after = rects()                              // via CGWindowListCopyWindowInfo(.optionAll)
var hudID: Int? = nil; var hudRect = CGRect.zero
for (n, r) in after where baseline[n] != nil && baseline[n] != r { hudID = n; hudRect = r }
for (n, r) in after where baseline[n] == nil    { hudID = n; hudRect = r }

if let full = hudWindows().first(where: { ($0[kCGWindowNumber as String] as? Int) == hudID }) {
    print("DICT COMPLET: \(full)")
}
let onscreen = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
print("présente dans optionOnScreenOnly ? \(onscreen.contains { ($0[kCGWindowNumber as String] as? Int) == hudID })")

// CGWindowListCreateImage est obsoleted en macOS 15 -> on passe par screencapture
let pr = Process()
pr.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
pr.arguments = ["-x", "-R", "\(Int(hudRect.minX)),\(Int(hudRect.minY)),\(Int(hudRect.width)),\(Int(hudRect.height))",
                "\(outDir)/hud_exact.png"]
try? pr.run(); pr.waitUntilExit()
```

### Autres sondes utiles

- `p10_notify.swift` — balaye les types de notification CGS 700-1000 et 1200-1400 et les corrèle
  au cycle de vie du HUD. C'est ce qui a identifié 912/913/827.
- `p13_observer.swift` — l'observateur qui démontre que les notifications CGS ne franchissent pas
  la frontière de process, `SLSRequestNotificationsForWindows` compris.
- `tcc_main.swift` + bundle `TccSonde.app` — la mesure TCC honnête, dans un *responsible process*
  distinct.
- `p9_sls.swift` — les mesures de coût des API.
- `bbox.swift` / `prof.swift` — profil des pixels bleus qui donne l'inset de 27,5 pt.

### Manipulations d'input source

Toutes les sondes mémorisent la source courante avant et la restaurent après. ✅ Vérifié en fin de
session : `com.apple.keylayout.French`, la source d'origine. Aucun process de sonde résiduel.

📄 Piège rencontré : **`TISSelectKeyboardInputSource` n'existe pas.** Le symbole du SDK est
`TISSelectInputSource` (`HIToolbox.framework/Headers/TextInputSources.h`). Les sources
sélectionnables et actives au moment du test étaient `com.apple.keylayout.US`,
`com.apple.keylayout.French`, `com.apple.keylayout.Persian-ISIRI2901`.

---

## Incertitudes restantes

1. ❓ **Le chemin utilisateur réel n'a pas pu être déclenché sans humain.** Le raccourci système
   actif est **Option+Espace** (`AppleSymbolicHotKeys` id 61 ; l'id 60 / Ctrl+Espace est désactivé).
   ✅ J'ai vérifié qu'un `Option+Espace` **synthétique** posté via `CGEvent` — y compris avec une
   séquence `flagsChanged` complète, et avec Accessibility accordé — **ne déclenche pas** le hotkey
   sur macOS 26.5. Toutes mes mesures passent donc par `TISSelectInputSource`. La notification
   distribuée est la notification système standard et devrait être identique pour une bascule
   clavier, mais **je ne l'ai pas prouvé**. À revérifier d'un coup de clavier réel : c'est une
   mesure de 30 secondes qui sécurise tout le reste.
2. ❓ **La marge de 17-18 ms n'a été mesurée que sur ma propre app témoin**, en machine peu
   chargée. Sous charge, ou dans une app lente à répondre au canal TSM, elle peut fondre. Aucune
   mesure dans Chrome, Electron, ou une app non-Cocoa — or c'est le périmètre annoncé par la carte.
3. ❓ **Le libellé à plus de deux glyphes** (Wubihua chinois, ou une source dont l'abréviation est
   plus large) donne peut-être un cadre plus large que 84 pt. La marge de 27,5 pt est probablement
   constante — c'est de l'ombre — mais je n'ai pu tester que deux sources à deux glyphes.
4. ❓ **Multi-écrans** : j'ai vu une fenêtre garée à `93,-987`, donc sur le DELL (au-dessus de
   l'écran interne en coordonnées `NSScreen`, donc en Y négatif en coordonnées CG). Le mécanisme
   marche visiblement sur les deux écrans, mais je n'ai fait aucune mesure de HUD réel sur l'écran
   secondaire, ni à un facteur d'échelle 1x. L'inset de 27,5 pt en particulier est mesuré @2x
   uniquement (55 px / 2), avec l'incertitude d'anti-aliasing que ça implique : ±0,5 pt.
5. ❓ **La règle de stabilisation reste à régler.** Deux événements quand le caret a bougé, un seul
   sinon. Attendre la stabilité coûte sur les 17 ms de marge ; ne pas l'attendre risque un flash de
   notre bulle à la position de parking. À trancher au prototype, avec un compteur de balayages
   plutôt qu'un délai.
6. ❓ **Fragilité assumée.** `kCGWindowOwnerName == "CursorUIViewService"`, le niveau 3, la taille
   84×77 et l'inset 27,5 sont tous des constantes observées sur 26.5 (25F71), sans aucune garantie
   contractuelle. Le point de rupture le plus probable à une mise à jour est la taille du cadre.
   Un contrôle au démarrage (« existe-t-il des fenêtres `CursorUIViewService` de 64×64 ? ») est un
   canari bon marché.
7. ❓ **Types de notification CGS non identifiés** (723, 904, 906, 1201, 1308, 1322, 1325, 1326).
   Non corrélés au HUD, non creusés — sans objet puisque la voie CGS est écartée.
