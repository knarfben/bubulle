# Détecter la première frappe, y compris en secure input — trouvailles

Ticket : [04-detecter-la-premiere-frappe](../tickets/04-detecter-la-premiere-frappe.md) · Carte : [MAP](../MAP.md)
Machine de mesure : macOS 26.5 (25F71), arm64, Swift 6.3.1, SDK MacOSX26.4.
Date des mesures : 2026-08-18.

**Convention de lecture** : chaque affirmation est marquée
`[OBSERVÉ]` = mesuré sur cette machine par une sonde ci-dessous ·
`[LU]` = tiré d'un header du SDK ou d'une doc Apple, non vérifié à l'exécution ·
`[DÉDUIT]` = raisonnement à partir des deux, à confirmer.

---

## Réponse courte

Deux détecteurs, pas un seul.

1. **Détecteur principal — `CGEventTap` en `listenOnly` sur `kCGSessionEventTap`**, masque
   `keyDown` (+ `flagsChanged` seulement pour l'ignorer). Il est **strictement passif** :
   un callback qui dort 400 ms n'a retardé la livraison de la frappe à l'app cible que de
   4,7 ms `[OBSERVÉ]`. Aucune latence de saisie mesurable. Permission requise :
   **Input Monitoring** (`CGPreflightListenEventAccess()`), pas Accessibility.
2. **Détecteur de secours — `CGEventSourceCounterForEventType(.combinedSessionState, .keyDown)`**,
   polling. Il **ne demande AUCUNE permission** `[OBSERVÉ]` et il **continue de compter
   pendant le secure input** `[OBSERVÉ sur événements synthétiques]`. C'est lui qui fait
   disparaître la bulle dans un champ mot de passe, là où le tap est aveugle.

En secure input, le tap voit **zéro** événement — aux trois emplacements, HID compris — mais
il **reste `enabled` et redevient fonctionnel tout seul** à la sortie, sans réarmement `[OBSERVÉ]`.
`IsSecureEventInputEnabled()` répond correctement sans aucune permission `[OBSERVÉ]`, et
`CGSessionCopyCurrentDictionary()["kCGSSessionSecureInputPID"]` donne même **le pid du détenteur**
`[OBSERVÉ]`.

Donc : **on ne bascule pas sur le timeout en secure input**. On bascule sur le compteur,
qui reste précis. Le timeout ne sert plus que de filet ultime.

---

## Détail par question du ticket

### 1. `CGEventTap` en `listenOnly` : permission, latence, emplacement

#### Permission — ce n'est pas Accessibility, c'est Input Monitoring

Le header du SDK dit encore l'ancienne règle :

> « Taps placed at `kCGHIDEventTap`, `kCGSessionEventTap`, `kCGAnnotatedSessionEventTap`,
> or on a specific process may only receive key up and down events if access for assistive
> devices is enabled […] If the tap is not permitted to monitor these events when the tap
> is created, then the appropriate bits in the mask are cleared. If that results in an empty
> mask, then NULL is returned. »
> — `CoreGraphics.framework/Headers/CGEvent.h`, bloc de commentaire de `CGEventTapCreate` `[LU]`

Mais depuis 10.15 le même header expose le vrai contrôle d'accès moderne `[LU]` :

```c
/* Checks whether the current process already has event listening access */
CG_EXTERN bool CGPreflightListenEventAccess(void) API_AVAILABLE(macos(10.15));
/* Requests event listening access if absent, potentially prompting */
CG_EXTERN bool CGRequestListenEventAccess(void)  API_AVAILABLE(macos(10.15));
```
(`CGEvent.h`, lignes 398-402 du SDK MacOSX26.4)

`CGPreflightListenEventAccess()` **ne déclenche aucun dialogue** (« Checks whether »), à la
différence de `CGRequestListenEventAccess()` (« potentially prompting »). C'est la sonde à
appeler au démarrage de bubulle. `[LU]` + `[OBSERVÉ]` : la sonde 1 l'appelle, aucun dialogue
n'est apparu.

Attention au piège de test : **la permission suit le processus responsable**. Les sondes
lancées depuis le terminal héritent des droits de Ghostty (`AXIsProcessTrusted=true`,
`preflightListen=true`). Le **même binaire** relancé sous `launchctl submit` (responsable =
launchd) rapporte `AXIsProcessTrusted=false preflightListen=false` `[OBSERVÉ]`. Le binaire
bubulle final aura donc besoin de **sa propre** entrée dans Réglages → Confidentialité →
Surveillance de la saisie.

Deux conséquences pratiques :
- au démarrage, si `CGPreflightListenEventAccess() == false`, ne pas appeler
  `CGRequestListenEventAccess()` en boucle : une seule fois, puis message clair et repli
  sur le détecteur n°2 ;
- ne jamais laisser `CGEventTapCreate` échouer en silence : `NULL` ⇒ pas de permission.

#### Latence — nulle, `listenOnly` est réellement passif

Sonde 5, phase B : tap `listenOnly` sur un **thread dédié**, callback qui dort 400 ms sur la
frappe, mesure du moment où l'app destinataire reçoit réellement le `NSEvent` :

```
PHASE B — callback lent 400 ms sur le tap Session (thread dédié)
   livraison F19 à notre app : t+4.7ms
```
`[OBSERVÉ]` — le WindowServer n'attend pas le retour du callback d'un tap `listenOnly`.
Conclusion : **impact zéro sur la saisie**, à condition de ne jamais utiliser `.defaultTap`.

Piège méthodologique à noter pour l'implémentation : une première version de la sonde plaçait
le tap sur le **main thread** de l'app ; le sleep bloquait alors le main thread, et donc le
champ texte de la sonde elle-même — mesure faussée. `[OBSERVÉ]` Le tap de bubulle doit vivre
sur son propre thread avec son propre `CFRunLoop`, pour que le callback ne puisse jamais être
retardé par le rendu de la bulle.

#### Emplacement — `kCGSessionEventTap`

Les trois emplacements ont été créés avec succès en `listenOnly`, **sans être root**
`[OBSERVÉ]` — y compris `kCGHIDEventTap`, alors que le header affirme :

> « Taps may only be placed at `kCGHIDEventTap` by a process running as the root user.
> NULL is returned for other users. » — `CGEvent.h` `[LU]`

Le header est donc **périmé sur ce point** en macOS 26 : le droit Input Monitoring suffit.
Ce n'est pas une raison de s'y placer.

| Emplacement | créé sans root | voit les frappes | aveuglé en secure input |
|---|---|---|---|
| `kCGHIDEventTap` | oui `[OBSERVÉ]` | oui | **oui** `[OBSERVÉ]` |
| `kCGSessionEventTap` | oui `[OBSERVÉ]` | oui | **oui** `[OBSERVÉ]` |
| `kCGAnnotatedSessionEventTap` | oui `[OBSERVÉ]` | oui | **oui** `[OBSERVÉ]` |

Descendre au niveau HID **ne contourne pas** le secure input. Aucun bénéfice, et un tap HID
est plus intrusif (il voit la frappe avant toute réécriture système).

Choix : **`kCGSessionEventTap`, `.headInsertEventTap`, `.listenOnly`**. C'est le niveau où la
frappe est déjà celle de la session de l'utilisateur, avant l'annotation vers une app précise —
donc on la voit même si l'app destinataire ne la consomme pas.

`CGEvent.tapCreateForPid(pid: getpid(), …)` retourne **NULL** `[OBSERVÉ]` (auto-tap refusé) ;
la piste « tap par pid sur l'app focalisée » n'a pas été explorée plus loin, elle imposerait
de recréer le tap à chaque changement de focus pour aucun gain.

---

### 2. Secure input : que voit-on, et que sait-on ?

Méthode : la sonde n'appelle **jamais** `EnableSecureEventInput()` elle-même (risque d'état
bloqué pour l'utilisateur). Elle ouvre une fenêtre avec un `NSSecureTextField` et lui donne le
focus : c'est AppKit qui active et relâche le secure input, exactement comme un vrai champ mot
de passe. Vérifié à chaque fin de sonde : `IsSecureEventInputEnabled() == false`.

Résultats (sonde 5, phase D) `[OBSERVÉ]` :

```
PHASE D — champ SÉCURISÉ
   IsSecureEventInputEnabled = true
   tap HID:       +0 événement(s) — enabled=true notices=[]
   tap Session:   +0 événement(s) — enabled=true notices=[]
   tap Annotated: +0 événement(s) — enabled=true notices=[]
   livraison à notre app (moniteur local) : oui
   counter combinedSessionState keyDown delta = 3
   counter hidSystemState       keyDown delta = 3
   secondsSinceLastKeyDown avant=0.997 après=0.668
```

Quatre faits, dans l'ordre d'importance :

1. **Le tap est aveugle** : 0 événement, aux trois emplacements. `[OBSERVÉ]`
2. **Le tap n'est pas désactivé** : `enabled=true`, aucune notification
   `kCGEventTapDisabledBy*`. Le secure input **filtre**, il ne coupe pas le tap. `[OBSERVÉ]`
3. **`CGEventSourceCounterForEventType` continue de compter** — `+3` sur
   `.combinedSessionState` **et** sur `.hidSystemState` pendant que le tap ne voyait rien.
   `secondsSinceLastEventType` est également remis à zéro (0,997 → 0,668). `[OBSERVÉ]`
4. **À la sortie du secure input, le tap reprend seul**, sans réarmement (phase E : `+4`
   événements, `enabled=true`). `[OBSERVÉ]`

#### Peut-on savoir qu'on y est ? Oui, et mieux que ça

`IsSecureEventInputEnabled()` **n'est déclaré dans aucun header public** des SDK 13.x → 26.x
`[OBSERVÉ]` : le symbole n'existe que dans `HIToolbox.tbd` / `Carbon.tbd`. Il faut le déclarer
soi-même et lier Carbon :

```swift
@_silgen_name("IsSecureEventInputEnabled")
func IsSecureEventInputEnabled() -> Bool
// swiftc … -framework Carbon    (sinon : Undefined symbols _IsSecureEventInputEnabled)
```
`[OBSERVÉ]` — l'édition de liens échoue sans `-framework Carbon`.

Il fonctionne **sans aucune permission** : dans le processus lancé par launchd
(`AXIsProcessTrusted=false`, `preflightListen=false`), il répond correctement `[OBSERVÉ]`.
Coût : **0,003 µs par appel** `[OBSERVÉ]` — négligeable, on peut le lire à chaque tick.

Bonus non demandé par le ticket : **on peut identifier le détenteur**.
`CGSessionCopyCurrentDictionary()` (API publique, `CGSession.h`) ne contient aucune clé
`secure` quand le secure input est éteint, et expose `kCGSSessionSecureInputPID` quand il est
allumé `[OBSERVÉ]` :

```
=== A : secure input OFF ===  clés secure/input = [:]
=== A : secure input ON  ===  clés secure/input = ["kCGSSessionSecureInputPID": 42777]
                              notre pid = 42777
```

Utile pour le diagnostic (« quelle app m'aveugle ? ») et pour distinguer un vrai champ mot de
passe d'un secure input parasite laissé par une app plantée. Coût : **61 µs par appel**
`[OBSERVÉ]` — 20 000× plus cher que `IsSecureEventInputEnabled()`, donc à n'appeler qu'à la
transition, jamais en boucle.

#### La stratégie envisagée dans le ticket est à revoir

Le ticket propose : « basculer sur le timeout dès l'entrée dans un champ mot de passe plutôt
que d'attendre l'expiration bêtement ». **Mieux que ça** : on n'a pas besoin de dégrader vers
le timeout, parce que le compteur `CGEventSource` reste exact sous secure input. Comportement
retenu :

- transition `secure input : off → on` ⇒ on **ne détruit pas le tap**, on démarre simplement
  le polling du compteur et c'est lui qui fait autorité ;
- première variation du compteur ⇒ bulle masquée, exactement comme une frappe normale ;
- transition `on → off` ⇒ retour au tap, sans réarmement.

Le timeout de sécurité reste, mais comme filet, pas comme mécanisme principal en champ mot
de passe.

---

### 3. Qu'est-ce qui compte comme « frappe » ?

Source primaire, `CGEventSource.h` (commentaire de `CGEventSourceCounterForEventType`) `[LU]` :

> « Modifier keys produce `kCGEventFlagsChanged` events, not `kCGEventKeyDown` events, and do
> so both on press and release. The volume, brightness, and CD eject keys on some keyboards
> (both desktop and laptop) do not generate key up or key down events. […] **Key autorepeat
> events are not counted.** »

Ce paragraphe règle trois points d'un coup :

- **modificateurs seuls (⇧ ⌘ ⌥ ⌃ Verr. maj) : ce sont des `flagsChanged`, jamais des
  `keyDown`.** Donc un masque limité à `keyDown` les exclut *gratuitement* — pas de filtrage à
  écrire. C'est la réponse à la question du ticket : **non**, les modificateurs seuls ne
  comptent pas, et on n'a rien à coder pour ça ;
- **volume / luminosité / éjection** ne produisent pas de `keyDown` — donc ne masqueront pas
  la bulle. Comportement souhaitable ;
- **l'autorepeat n'est pas compté** par `CGEventSourceCounterForEventType` — le compteur de
  secours ne dérivera donc pas si l'utilisateur laisse une touche enfoncée.

Pour le tap, l'autorepeat est en revanche bien livré ; il se lit sur le champ
`kCGKeyboardEventAutorepeat` `[OBSERVÉ]` (les frappes synthétiques de la sonde 6 ressortent
avec `autorepeat=0`). Sans importance ici : la *première* frappe n'est jamais un autorepeat.

**Flèches, retour arrière, Tab, Entrée, Échap** : ce sont tous des `keyDown` ordinaires, avec
des keycodes dédiés (flèches 123-126, retour arrière 51, Tab 48, Entrée 36, Échap 53).
Ils **doivent** masquer la bulle : ce sont des frappes qui modifient le texte ou le caret,
donc la bulle n'est plus au bon endroit et n'est plus pertinente. `[DÉDUIT]` — cohérent avec
la décision de carte « disparition sur première frappe ».

**Ne pas classer par contenu Unicode.** La sonde 6 montre que
`CGEvent.keyboardGetUnicodeString` est trompeur : F19 (keycode 80) rend **0** caractère, mais
F16 (keycode 106) en rend **1** (un caractère de zone privée) `[OBSERVÉ]` :

```
type=10 keycode=80  autorepeat=0 unicode=0ch ''
type=10 keycode=106 autorepeat=0 unicode=1ch ''
```

Règle retenue, simple et robuste : **tout `kCGEventKeyDown` est une frappe.** Aucune
exception, aucune liste à maintenir. Les seules choses qu'on voulait exclure (modificateurs,
touches média) sont déjà exclues par le type d'événement lui-même.

---

### 4. Timeout du tap et réarmement

C'est le point sur lequel l'observation **contredit** l'attente.

Le header annonce `[LU]` :

> « If a tap becomes unresponsive or a user requests taps be disabled, an appropriate
> `kCGEventTapDisabled...` event is passed to the registered `CGEventTapCallBack` function.
> An event tap may be re-enabled by calling this function. » — `CGEvent.h`, `CGEventTapEnable`

Trois tentatives distinctes de provoquer le timeout (sonde 5 phase C : callback 3 000 ms ;
sonde 6 : callback 3 000 ms ; sonde 7 phase B : 60 événements × 100 ms de stall) :

```
sonde 5 · à t+4.5s : tap HID/Session/Annotated enabled=false notices=[]
sonde 6 ·            enabled après stall = true, notices=[]
sonde 7 · à t+3s  : enabled=false reçus=31  notices=[]
           à t+6s  : enabled=false reçus=120 notices=[]
           réarmé -> enabled=true ; après réarmement : +4 ; notices=[]
```

`[OBSERVÉ]` :
- le tap **est bel et bien désactivé** par un callback trop lent (`CGEventTapIsEnabled()`
  passe à `false`) ;
- **le callback `kCGEventTapDisabledByTimeout` n'a JAMAIS été reçu**, dans aucune des trois
  tentatives, ni pendant ni après le stall ;
- `CGEventTapEnable(tap, true)` **restaure intégralement** le tap : les frappes suivantes sont
  de nouveau vues (`+4`) ;
- désactiver puis réactiver manuellement fonctionne aussi (sonde 2) ;
- l'état `enabled=false` peut être lu **pendant que le backlog se vide encore** (sonde 7 :
  `enabled=false` alors que le compteur d'événements reçus continue de monter de 31 à 120) —
  donc `enabled=false` n'est pas synonyme de « plus rien n'arrive ».

**Stratégie de réarmement retenue** — ne pas faire confiance à la notification :

1. gérer quand même `kCGEventTapDisabledByTimeout` et `kCGEventTapDisabledByUserInput` dans
   le callback (réarmement immédiat) — coût nul, ça marchera peut-être sur une autre version ;
2. **plus un chien de garde** : un timer (2 s suffit) qui vérifie `CGEventTapIsEnabled()` et
   réarme si `false`. C'est ce chien de garde qui est le vrai mécanisme, l'observation le
   montre ;
3. **et surtout, ne jamais faire attendre le callback** : tap sur son propre thread, callback
   qui ne fait que lire le type de l'événement et poster sur la queue principale. Un callback
   qui ne dépasse pas quelques microsecondes ne déclenche jamais le problème.

À noter : dans la sonde 5 les **trois** taps ont été désactivés alors qu'un seul dormait —
parce qu'ils partageaient un runloop. Un thread par tap, ou un seul tap : pas d'entre-deux.

---

### 5. Le détecteur sans permission (`CGEventSource`)

C'est la trouvaille la plus utile du ticket, parce qu'elle couvre **à la fois** le cas
« permission non accordée » et le cas « secure input ».

```
=== binaire lancé depuis le terminal (responsable = Ghostty) ===
AXIsProcessTrusted=true  preflightListen=true  preflightPost=true
counterForEventType : 0.0046 µs/appel

=== MÊME binaire lancé via launchctl submit (responsable = launchd) ===
AXIsProcessTrusted=false preflightListen=false preflightPost=false
counterForEventType : 0.0077 µs/appel      <-- fonctionne quand même
IsSecureEventInputEnabled : 0.0043 µs/appel <-- fonctionne quand même
```
`[OBSERVÉ]` (sonde 8)

Coûts mesurés, par appel `[OBSERVÉ]` :

| appel | coût | verdict |
|---|---|---|
| `CGEventSourceCounterForEventType` | **0,005 µs** | polling à 60 Hz = 0,0003 % d'un cœur |
| `CGEventSourceSecondsSinceLastEventType` | 0,023 µs | idem |
| `IsSecureEventInputEnabled` | 0,003 µs | idem |
| `CGSessionCopyCurrentDictionary` | **61 µs** | seulement aux transitions |

Un polling à 60 Hz du compteur est donc gratuit. La latence de détection vaut au pire une
période de polling ; à 60 Hz c'est 16 ms, invisible à l'œil pour une bulle qui disparaît.

Limite du compteur : il est **global à la session**, pas par application. Il ne dit pas *où* la
frappe a eu lieu. Pour bubulle, c'est sans importance : la bulle disparaît à la première
frappe, d'où qu'elle vienne.

---

## Mécanique retenue

```
                    ┌──────────────────────────────────────────┐
   au démarrage     │ CGPreflightListenEventAccess() ?         │
                    └───────────────┬──────────────────────────┘
                       true         │        false
                        │           │          │
                        ▼           │          ▼
        tap listenOnly, Session,    │   CGRequestListenEventAccess() UNE fois,
        thread dédié, masque        │   message clair, puis mode compteur seul
        keyDown | flagsChanged      │
                        │                      │
                        └──────────┬───────────┘
                                   ▼
        bulle visible  ──► à chaque tick (60 Hz) :
                             1. secure = IsSecureEventInputEnabled()
                             2. si !secure et tap actif : la frappe vient du tap
                                si  secure ou pas de tap : c'est le compteur qui décide
                             3. chien de garde 2 s : CGEventTapIsEnabled() ? sinon réarmer
```

Détail de la règle 2 : on mémorise `counter0 = CGEventSourceCounterForEventType(
.combinedSessionState, .keyDown)` **au moment où la bulle s'affiche**, et la bulle disparaît
dès que le compteur en diffère — que le tap ait vu quelque chose ou non. Le tap sert alors
uniquement à raccourcir la latence (immédiat au lieu de ≤ 16 ms) et à disposer du keycode si
on en veut un jour. Autrement dit : **le compteur est la source de vérité, le tap est
l'accélérateur.** Ça simplifie beaucoup la machine à états du ticket 08 — il n'y a pas deux
modes, il y a un mode avec un raccourci optionnel.

Comportement exact en champ sécurisé, tel qu'observé :

| moment | `IsSecureEventInputEnabled` | tap | compteur | bulle |
|---|---|---|---|---|
| champ normal | `false` | voit tout | incrémente | disparaît sur la frappe (via tap) |
| entrée champ mot de passe | passe à `true` immédiatement | 0 événement, reste `enabled` | incrémente toujours | **reste affichée**, en attente |
| frappe dans le champ mot de passe | `true` | rien | +1 | **disparaît** (via compteur, ≤ 16 ms) |
| sortie du champ | repasse à `false` | reprend seul | — | — |

La bulle ne « meurt pas bêtement au timeout » en champ mot de passe : elle disparaît à la
vraie première frappe, comme partout ailleurs. Le timeout de sécurité (valeur à trancher avec
Frank, hors périmètre de ce ticket) ne sert plus que si *aucune* frappe n'arrive.

---

## Code des sondes

Toutes dans le scratchpad de session
`/private/tmp/claude-501/-Users-frankbenady-dev-streamlink-scripts-bubulle/e1872384-d63d-434c-b846-cd225d4ab2aa/scratchpad/`,
compilées avec `xcrun swiftc -O <fichier>.swift -o <bin> -framework Carbon`.

| sonde | fichier | ce qu'elle établit |
|---|---|---|
| 1 | `probe1_perms.swift` | état TCC sans prompt, `IsSecureEventInputEnabled`, compteurs, inventaire des taps actifs de la machine |
| 2 | `probe2_taps.swift` | matrice de création HID/Session/Annotated/ForPid, masques réellement accordés, `tapEnable` manuel |
| 3 | `probe3_secure.swift` | premier aveuglement observé sous `NSSecureTextField` |
| 4 | `probe4_full.swift` | (partiellement invalidée : tap sur le main thread ⇒ mesure de latence faussée) |
| 5 | `probe5_block_secure.swift` | tap sur thread dédié : non-blocage, timeout, secure input sur les 3 emplacements |
| 6 | `probe6_details.swift` | classification des touches, champs `keycode`/`autorepeat`/unicode |
| 7 | `probe7_holder_timeout.swift` | `kCGSSessionSecureInputPID`, timeout sous charge soutenue |
| 8 | `probe8_bench.swift` | coût des appels, et comportement du **même binaire** sans permission (via `launchctl submit`) |

### Squelette minimal, tel que validé

```swift
import Cocoa
import CoreGraphics

// N'existe dans AUCUN header public : à déclarer soi-même, et lier -framework Carbon.
@_silgen_name("IsSecureEventInputEnabled")
func IsSecureEventInputEnabled() -> Bool

final class FirstKeystrokeWatcher {
    private var tapPort: CFMachPort?
    private var baseline: UInt32 = 0
    private var onFirstKeystroke: (() -> Void)?

    /// Compteur global de keyDown de la session. Aucune permission requise,
    /// et il continue de compter sous secure input.
    private var keyDownCounter: UInt32 {
        CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
    }

    func armTap() {
        guard CGPreflightListenEventAccess() else { return }   // ne prompte pas
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let sem = DispatchSemaphore(value: 0)
        Thread {                                               // runloop dédié, jamais le main
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,                          // JAMAIS .defaultTap
                eventsOfInterest: mask,
                callback: { _, type, event, _ in
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        // observé : cette notification n'arrive jamais sur macOS 26.5.
                        // On la gère quand même, mais le chien de garde est le vrai filet.
                        return nil
                    }
                    DispatchQueue.main.async { /* hideBubble() */ }
                    return Unmanaged.passUnretained(event)     // ignoré en listenOnly
                },
                userInfo: nil
            ) else { sem.signal(); return }
            self.tapPort = port
            CFRunLoopAddSource(CFRunLoopGetCurrent(),
                               CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)!,
                               .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            sem.signal()
            CFRunLoopRun()
        }.start()
        sem.wait()
    }

    /// Appelé quand la bulle s'affiche.
    func begin(_ handler: @escaping () -> Void) {
        baseline = keyDownCounter
        onFirstKeystroke = handler
    }

    /// Tick à 60 Hz. Coût mesuré : ~0.008 µs.
    func tick() {
        if keyDownCounter != baseline { onFirstKeystroke?(); onFirstKeystroke = nil }
    }

    /// Chien de garde, toutes les 2 s. La notification de timeout n'arrive pas.
    func watchdog() {
        if let p = tapPort, !CGEvent.tapIsEnabled(tap: p) {
            CGEvent.tapEnable(tap: p, enable: true)
        }
    }

    /// Diagnostic seulement — 61 µs par appel, jamais dans une boucle.
    func secureInputHolderPID() -> pid_t? {
        guard IsSecureEventInputEnabled(),
              let d = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = d["kCGSSessionSecureInputPID"] as? pid_t else { return nil }
        return pid
    }
}
```

Précautions respectées par toutes les sondes, à reprendre dans bubulle :
- `options: .listenOnly` **partout**, jamais `.defaultTap` : impossible d'avaler ou de modifier
  une frappe de l'utilisateur ;
- `EnableSecureEventInput()` **jamais appelé** : le secure input a été provoqué par un
  `NSSecureTextField`, c'est AppKit qui le relâche ; vérifié `false` en fin de chaque sonde ;
- frappes de test = **F19 (keycode 80)**, inerte partout, jamais un caractère.

---

## Incertitudes

1. **Le compteur `CGEventSource` sous secure input n'a été vérifié qu'avec des frappes
   synthétiques**, postées par le processus qui détenait lui-même le secure input. `[OBSERVÉ]`
   ne couvre donc pas le cas « clavier physique + champ mot de passe d'une autre app ».
   Argument en faveur `[DÉDUIT]` : le compteur `.hidSystemState` a bougé aussi, il est
   maintenu en amont du filtrage secure input, et c'est le même compteur qui alimente la
   détection d'inactivité du système — l'écran ne se met pas en veille pendant qu'on tape un
   mot de passe. **À vérifier en 30 secondes une fois bubulle lancé** : afficher le compteur
   en continu, ouvrir le trousseau ou un champ mot de passe réel, taper, regarder s'il monte.
2. **Le comportement sans permission n'a pas été testé jusqu'à la création du tap.**
   `CGPreflightListenEventAccess()` retourne `false` sous launchd `[OBSERVÉ]`, mais je n'ai pas
   appelé `CGEventTapCreate` dans ce contexte pour ne pas risquer un dialogue système ni une
   entrée parasite dans la liste Surveillance de la saisie. Le header dit `NULL` si le masque
   devient vide `[LU]` ; **à confirmer** au premier lancement du vrai binaire, avant que la
   permission ne soit accordée.
3. **Le seuil exact du timeout du tap n'a pas été mesuré.** Un stall de 400 ms ne le déclenche
   pas ; 3 000 ms sur trois taps partageant un runloop le déclenche ; 3 000 ms sur un tap seul
   ne l'a pas déclenché. `[OBSERVÉ]` La valeur dépend visiblement de la charge et du backlog,
   pas d'un simple seuil par événement. Sans importance si le callback reste microscopique.
4. **`kCGEventTapDisabledByTimeout` jamais reçu** : je ne peux pas exclure un problème de ma
   sonde (le `return nil` sur ce type d'événement, ou une coalescence pendant le stall). Mais
   l'état `enabled=false` était bien lisible, donc la stratégie « chien de garde » est correcte
   quelle que soit l'explication.
5. **Verr. maj (`caps lock`)** n'a pas été testé spécifiquement. Le header le range avec les
   modificateurs (`flagsChanged`) `[LU]`, donc il ne devrait pas masquer la bulle — ce qui est
   probablement le bon comportement, mais mérite une vérification si Frank le trouve étrange.
6. **Les émulateurs de terminal en mode « secure keyboard entry »** (option de Terminal.app,
   activée en permanence chez certains) maintiennent le secure input **tout le temps**, pas
   seulement sur un champ mot de passe. Dans ces apps, bubulle tournera **toujours** en mode
   compteur. Sans conséquence fonctionnelle vu les résultats ci-dessus, mais bon à savoir pour
   le débogage : `secureInputHolderPID()` dira lequel.

---

## Sources primaires

- `CGEvent.h`, `CGEventTypes.h`, `CGEventSource.h`, `CGSession.h` —
  `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/CoreGraphics.framework/Headers/`
- `HIToolbox.tbd` / `Carbon.tbd` (symboles `IsSecureEventInputEnabled`,
  `EnableSecureEventInput`, `DisableSecureEventInput` — **aucun header public** dans les SDK
  13.0 à 26.5)
- Mesures directes sur macOS 26.5 (25F71), sondes 1 à 8 listées ci-dessus.
