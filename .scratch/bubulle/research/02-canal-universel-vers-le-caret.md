# Un canal universel vers le rect du caret — trouvailles

Ticket : [02-canal-universel-vers-le-caret](../tickets/02-canal-universel-vers-le-caret.md) · Carte : [MAP](../MAP.md)
Machine de mesure : macOS 26.5 (25F71), arm64, Swift 6.3.1, SDK `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`.
Date des mesures : 2026-08-18.

**Convention de lecture** : chaque affirmation est marquée
`[OBSERVÉ]` = mesuré sur cette machine par une sonde décrite ci-dessous ·
`[LU]` = tiré d'un header du SDK, d'un Info.plist système ou d'un binaire système, non vérifié à l'exécution ·
`[DÉDUIT]` = raisonnement à partir des deux, à confirmer.

---

## Verdict

**Le canal existe, il est universel, et un process tiers peut s'y abonner — sous une condition
unique, qui est satisfaite.** La condition : être un **input method de type `palette`**
(`InputMethodType = palette` dans l'Info.plist, catégorie TIS `TISCategoryPaletteInputSource`).

La question bloquante du ticket — « peut-on recevoir ça sans se substituer aux layouts de
l'utilisateur ? » — a une réponse nette : **oui, structurellement, et sans aucun compromis**.

- Un input source de catégorie *palette* est **sélectionné en parallèle** des layouts clavier,
  pas à leur place. Le header le dit (« Zero or more of these can be selected ») `[LU]` et la
  machine le montre : `com.apple.PressAndHold` est `selected=1` **en même temps** que
  `com.apple.keylayout.French` `[OBSERVÉ]`.
- Une palette **ne reçoit aucun événement clavier**. Sonde installée, sélectionnée, avec
  `handleEvent:client:` et `recognizedEvents:` implémentés : **0 appel** à `handleEvent:` alors
  que six caractères étaient tapés dans Chrome, qui les a tous reçus normalement `[OBSERVÉ]`.
  Le passthrough n'est donc pas un « input method qui renvoie `NO` » — c'est une catégorie
  d'input source que TSM ne met jamais sur le chemin des touches.
- Elle est **invisible** dans le menu de saisie : `ComponentInvisibleInSystemUI = true`, et
  l'activation n'ajoute rien à `AppleEnabledInputSources` (seulement à `AppleSelectedInputSources`)
  `[OBSERVÉ]`.

Et le rect obtenu est celui du ticket, à la demande, à tout moment :

```
[poll] bundle=com.google.Chrome rect={{-50, 2117}, {1, 22}} selRange=(0,0)
[poll] bundle=com.google.Chrome rect={{4,   2117}, {1, 22}} selRange=(6,0)   ← après avoir tapé "azerty"
```

`[OBSERVÉ]` — interrogation par timer 1 Hz, hors de tout `activateServer:`, sur le client retenu.

**Les trois autres pistes sont mortes**, et pour une seule et même raison, établie et non
supposée : le HUD système ne lit pas un bus global, il lit **le `NSTextInputClient` de
l'app focalisée, dans le process de cette app**. Il n'y a rien à écouter depuis l'extérieur.

---

## Piste 1 — Bundle Input Method type `palette` : **retenue**

Niveau de preuve : **bout en bout sur cette machine**. Sonde construite, signée ad-hoc,
installée dans `~/Library/Input Methods`, enregistrée, sélectionnée, interrogée, désinstallée.

### 1.1 L'API existe et est publique-ish

`attributesForCharacterIndex:lineHeightRectangle:` est déclarée dans le protocole `IMKTextInput`,
header **présent dans le SDK** `[LU]` :

```
/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/
  Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/IMKInputSession.h
```

```objc
@protocol IMKTextInput
- (NSDictionary*)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect*)lineRect;
- (NSRange)selectedRange;
- (NSString*)bundleIdentifier;
@end
```

> « Additionally, a rectangle that would frame a one-pixel wide rectangle with the height of
> the line is returned in the frame parameter. […] Input methods will call this method to place
> a candidate window on the screen. »
> — `IMKInputSession.h` `[LU]`

Noter : ce header n'est **pas** dans `InputMethodKit.framework/Headers` (qui ne contient que
`IMKCandidates.h`, `IMKInputController.h`, `IMKServer.h`, `InputMethodKit.h`) `[OBSERVÉ]`. Il est
dans HIToolbox. `#import <Carbon/Carbon.h>` ne suffit pas à le tirer ; en pratique on redéclare
un mini-protocole local et on caste le `sender` — c'est ce que fait la sonde.

### 1.2 Le type `palette` existe, Apple s'en sert, et il coexiste avec les layouts

Les catégories TIS, header `TextInputSources.h` `[LU]` :

| Catégorie | Sémantique (header) |
|---|---|
| `kTISCategoryKeyboardInputSource` | un seul sélectionné à la fois |
| `kTISCategoryPaletteInputSource` | **« Zero or more of these can be selected »** |
| `kTISCategoryInkInputSource` | zéro ou un |

Bundles Apple avec `InputMethodType = palette` dans leur Info.plist `[LU]` :
`CharacterPalette.app`, `Assistive Control.app`, `50onPaletteServer.app`, `DictationIM.app`.
`PressAndHold.app` est du même type côté TIS sans porter la clé (son appex utilise le point
d'extension `com.apple.textinputmethod-services`) `[LU]`.

Preuve qu'une palette est un client `IMKTextInput` qui demande le rect du caret `[LU]` :

```
$ strings -a "/System/Library/Input Methods/Assistive Control.app/Contents/MacOS/Assistive Control"
T@"<IMKTextInput><NSObject>",&,N,V__client
attributesForCharacterIndex:lineHeightRectangle:
```
Idem pour `CharacterPalette` (`T@"<IMKTextInput><IMKUnicodeTextInput>",R,V__currentSession`).

`IMKServer.h` expose `-(BOOL)paletteWillTerminate` depuis 10.7 `[LU]` — la notion de palette est
une notion de première classe d'InputMethodKit, pas un bricolage.

État réel des input sources de la machine, sonde `TISCreateInputSourceList(NULL, true)` `[OBSERVÉ]` :

```
ID                                          TYPE                       CATEGORY                         EN/SEL/SELCAP
com.apple.keylayout.US                      TISTypeKeyboardLayout      TISCategoryKeyboardInputSource   1/0/1
com.apple.CharacterPaletteIM                TISTypeCharacterPalette    TISCategoryPaletteInputSource    1/0/1
com.apple.PressAndHold                      TISTypeCharacterPalette    TISCategoryPaletteInputSource    1/1/1   ← sélectionnée
com.apple.keylayout.French                  TISTypeKeyboardLayout      TISCategoryKeyboardInputSource   1/1/1   ← sélectionné aussi
com.apple.keylayout.Persian-ISIRI2901       TISTypeKeyboardLayout      TISCategoryKeyboardInputSource   1/0/1
com.apple.inputmethod.SCIM.WBH              TISTypeKeyboardInputMode   TISCategoryKeyboardInputSource   1/0/1
```

`PressAndHold` **est** le précédent : une palette Apple, sélectionnée en permanence dans toutes
les apps, qui pose son popup d'accents exactement sur le caret — y compris dans Chrome. C'est
littéralement le mécanisme que la carte veut réutiliser.

### 1.3 Un bundle tiers y a droit — vérifié

Sonde `BubulleProbe.app` : Info.plist minimal, binaire ObjC de 70 Ko, `codesign -s -` (ad-hoc),
copié dans `~/Library/Input Methods/`.

```xml
<key>InputMethodType</key><string>palette</string>
<key>ComponentInvisibleInSystemUI</key><true/>
<key>InputMethodConnectionName</key><string>local_bubulle_probeim_connection</string>
<key>InputMethodServerControllerClass</key><string>BubulleController</string>
<key>TISInputSourceID</key><string>local.bubulle.probeim</string>
<key>LSUIElement</key><true/>
<key>LSBackgroundOnly</key><true/>
<key>tsInputMethodCharacterRepertoireKey</key><array><string>Latn</string></array>
```

Séquence et résultats `[OBSERVÉ]` :

1. `TISRegisterInputSource(bundleURL)` → `0` (noErr). La source apparaît immédiatement, typée
   `TISTypeCharacterPalette` / `TISCategoryPaletteInputSource`, `enabled=0 selected=0`.
2. `TISEnableInputSource` **avant** d'avoir lancé le process → renvoie `0` mais **ne prend pas**,
   et `TISSelectInputSource` renvoie `-50` (paramErr). **Piège à retenir.**
3. On lance l'app (elle crée son `IMKServer` : `initWithName:bundleIdentifier:`, instance
   `_IMKServerLegacy`). La source passe **toute seule** à `enabled=1`.
4. `TISSelectInputSource` → `0`. `selected=1`.
5. **Les layouts de l'utilisateur ne bougent pas** : `French` reste `selected=1`, `SCIM.WBH`,
   `US`, `Persian` restent enabled. `AppleSelectedInputSources` contient alors exactement
   `{PressAndHold, local.bubulle.probeim, French}`.
6. `AppleEnabledInputSources` **n'est pas modifié** (6 entrées avant et après) → la palette
   n'entre pas dans la liste que l'utilisateur voit dans Réglages.

Donc l'ordre est : **lancer le process d'abord, enregistrer/activer ensuite**.

### 1.4 Ce qu'on reçoit, et quand

Le controller reçoit `activateServer:`/`deactivateServer:` à chaque prise/perte de focus texte,
dans **toutes** les apps, et le `sender` est un `_IPMDServerClientWrapperLegacy` conforme à
`IMKTextInput` `[OBSERVÉ]`.

Rects obtenus (`attributesForCharacterIndex:0 lineHeightRectangle:&r`) `[OBSERVÉ]` :

| App | Nature | Rect |
|---|---|---|
| `com.mitchellh.ghostty` | terminal natif | `{{25.75, 179}, {1, 21}}` |
| `com.apple.TextEdit` | AppKit | `{{195, 989}, {1, 13}}` |
| binaire AppKit non bundlé | `NSTextField` | `{{226, 250}, {1, 16}}` |
| **`com.google.Chrome`** | **Blink, hors Accessibility** | **`{{-50, 2117}, {1, 22}}`** |
| `com.apple.systempreferences` | fenêtre sans focus texte | `{{0,0},{0,0}}` |
| `com.microsoft.VSCode` (écran d'accueil) | Electron sans champ focalisé | `{{0,0},{0,0}}` |
| `com.hnc.Discord` (pas de champ focalisé) | Electron | `{{0,0},{0,0}}` |

Le dictionnaire d'attributs retourné contient `IMKLineHeight`, `IMKBaseline`, `IMKLineAscent`,
`NSFont`, `IMKTextOrientation` — et il est **vide** quand le rect est nul `[OBSERVÉ]`.

**Espace de coordonnées** : points, **origine en bas à gauche de l'écran principal**, convention
Cocoa/`NSScreen` `[OBSERVÉ]` — vérifié en croisant avec une fenêtre de géométrie connue :
fenêtre `{{200,200},{400,120}}`, champ à `(20,40,360,30)` dans sa vue → rect rendu
`{{226,250},{1,16}}`. Largeur toujours 1, hauteur = hauteur de ligne. Les valeurs négatives /
très grandes de Chrome viennent d'un second écran, donc **c'est bien un espace multi-écrans
global**, pas un espace fenêtre.

### 1.5 À la demande, pas seulement au moment du HUD

C'est le point central du ticket. Il faut **retenir le `sender`** (ou `self.client` d'`IMKInputController`)
et l'interroger quand on veut. Sonde : timer 1 Hz interrogeant le dernier client vu, hors de
tout callback `[OBSERVÉ]` :

```
[poll] bundle=com.google.Chrome rect={{-50, 2117}, {1, 22}} selRange=(0,0)
... (frappe de "azerty" via System Events)
[poll] bundle=com.google.Chrome rect={{4, 2117}, {1, 22}} selRange=(6,0)
```

Le rect **suit le caret en direct**, et `selectedRange` suit aussi. On a donc, gratuitement,
un second signal exploitable pour le ticket « première frappe » (`selRange` qui bouge) — à
croiser avec [04](04-detecter-la-premiere-frappe.md), qui a déjà tranché pour le compteur
`CGEventSourceCounterForEventType`.

Après `deactivateServer:`, le même objet client reste vivant mais renvoie
`rect = {{0,0},{0,0}}` et `selRange = (NSNotFound, NSNotFound)` `[OBSERVÉ]`. **Utile** : c'est un
test de validité intégré, on n'a pas besoin de savoir si l'objet est périmé.

### 1.6 Passthrough : preuve

`handleEvent:client:` implémenté, `recognizedEvents:` renvoyant `NSEventMaskKeyDown`.
`grep -c handleEvent` dans le log après avoir tapé « azerty » dans Chrome : **0** `[OBSERVÉ]`.
Le texte est arrivé dans Chrome (`selRange` 0 → 6). **Une palette n'est jamais sur le chemin des
touches** — même en le demandant explicitement. Aucun risque de casser la saisie, aucun risque
d'ajouter de la latence, aucune interaction avec le SCIM chinois sur le plan des événements.

---

## Piste 2 — TSM / Carbon hors contexte input method : **morte**

Niveau de preuve : header + table des symboles exportés.

Les fonctions **existent bien** et sont exportées par HIToolbox sur cette machine
(`dyld_info -arch arm64e -exports`) `[OBSERVÉ]` :
`_TSMGetActiveDocument`, `_TSMGetDocumentProperty`, `_TSMSetDocumentProperty`,
`_TSMRemoveDocumentProperty`, `_TSMInvalidateClientGeometry`, `_TSMSelectInputSource`,
`_TSMCopyTextInputGlobalProperty`, etc. Elles sont donc appelables.

Mais **deux verrous** :

1. **Aucun tag de propriété ne porte une géométrie de caret.** Liste exhaustive des
   `kTSMDocument*PropertyTag` du header `TextServices.h` `[LU]` : `TextService`, `Unicode`,
   `TSMTE`, `SupportGlyphInfo` (`'dpgi'`), `UseFloatingWindow` (`'uswm'`), `UnicodeInputWindow`
   (`'dpub'`), `SupportDocumentAccess` (`'dapy'`), `Refcon` (`'refc'`), `InputMode` (`'imim'`),
   `WindowLevel` (`'twlp'`), `InputSourceOverride` (`'inis'`), `EnabledInputSources` (`'enis'`).
   Rien de géométrique. Le seul voisin, `TSMSetInlineInputRegion`, est un *setter* pour l'app,
   déprécié depuis 10.5 et 32-bit only.
2. **`TSMDocumentID` est un handle intra-process.** Les documents sont créés par l'app elle-même
   (`NewTSMDocument`) dans son propre espace d'adressage ; `TSMGetActiveDocument()` renvoie le
   document actif *du process appelant*. Notre process n'a pas de document texte, donc il ne
   verra jamais celui de Chrome. `[DÉDUIT]` du header, mais corroboré par la découverte de la
   piste 3 : c'est le même modèle in-process partout.

Détail à garder en tête : `TUICursorUIViewService` expose une propriété
`targetTSMDocument` (`NSNumber`) et une clé `tsmTargetTSMDocumentKeyKey` `[LU]` — le HUD
identifie bien son document par un id TSM, mais c'est **l'app** qui le lui passe.

---

## Piste 3 — `TextInputUIMacHelper.framework` : **morte, mais c'est elle qui explique tout**

Niveau de preuve : dump du runtime ObjC après `dlopen`, plus sonde AppKit d'auto-observation.

### 3.1 Ce que contient le framework

`dlopen` du framework privé puis `objc_copyClassList` `[OBSERVÉ]` (le binaire est dans le
dyld shared cache, donc `class-dump`/`nm` sur le chemin disque échouent — il faut passer par le
runtime, ou par `dyld_info -exports` qui ne donne que les classes exportées).

Classe centrale, **`TUINSCursorUIController`** :

```objc
+ (instancetype)sharedInstance;   + (BOOL)enabled;
@property NSView<NSTextInputClient> *client;      // ← ivar _client
- (CGPoint)cursorLocation;   - (CGRect)selectedRect;   - (CGRect)visibleRect;
- (void)updateCursorLocation;   - (void)getCursorLocation:(void(^)())block;
- (void)invalidateCharacterCoordinates;
- (void)showTextInputMenuHUD:(id)a;  - (void)moveTextInputMenuHUD:(id)a;
- (void)hideTextInputMenuHUD:(id)a;  - (void)commitTextInputMenuHUD:(id)a;
- (BOOL)supportsTextCursorAccessory;
@property TUINSWindow *hostWindow;   // TUINSWindow : NSWindow, avec un NSRemoteViewController
```
plus `TUICursorAccessory` et ses sous-classes `TUIInputModeSwitcherAccessory`,
`TUIInputModeAccessory`, `TUICapslockAccessory`, `TUIDictationAccessory`, et un
`TUINSCursorLocationCache` (`NSMapTable` client → `NSValue` + `NSDate`, avec un
`expirationThreshold`).

### 3.2 Le fait qui tranche

Sonde : un binaire AppKit ordinaire, non privilégié, qui ouvre une fenêtre avec un `NSTextField`,
l'active, puis regarde ses propres images chargées `[OBSERVÉ]` :

```
avant : TUINSCursorUIController=0x0  TextInputUIMacHelper chargé=0
après (fenêtre active, champ first responder) :
        TextInputUIMacHelper chargé=1, +enabled=1,
        sharedInstance.client = <NSTextView: 0x9dd7f9000>   ← MON PROPRE text view
        supportsTextCursorAccessory=1
```

**Le framework se charge dans le process de l'app focalisée, et son `client` est le
`NSTextInputClient` de cette app.** Le HUD ne connaît pas la position du caret « partout » via
un service central : il la connaît parce qu'**une copie du contrôleur tourne dans chaque app**
et interroge le `NSTextInputClient` local. C'est exactement le même canal que la piste 1, vu de
l'autre bout.

Corollaire : **il n'y a aucun abonnement possible depuis l'extérieur**, et la seule façon
d'atteindre ce contrôleur pour une *autre* app serait l'injection de code dans son process —
explicitement hors périmètre de la carte (mur SIP).

### 3.3 Nuance mesurée

`cursorLocation`, `selectedRect` et `visibleRect` sont restés à zéro dans la sonde, même après
un appel explicite à `updateCursorLocation` `[OBSERVÉ]`. Ils ne sont probablement peuplés que
lorsqu'une *assertion* d'accessoire est active (cf. `TUICursorAccessoryAssertionController`,
`beginTrackingAssertion:`). Sans importance pour la décision, puisque le chemin est de toute
façon in-process.

---

## Piste 4 — Notification distribuée / XPC de `CursorUIViewService` : **morte**

Niveau de preuve : Info.plist, `otool -L`, table des symboles importés, `ps`.

- Le service vit **à l'intérieur** du framework :
  `TextInputUIMacHelper.framework/Versions/A/XPCServices/CursorUIViewService.xpc` `[OBSERVÉ]`.
- Son Info.plist `[LU]` :
  ```
  NSPrincipalClass = NSViewServiceApplication
  CFBundlePackageType = XPC!
  XPCService = { RunLoopType = _NSApplicationMain; JoinExistingSession = true; ServiceType = User }
  CFBundleIdentifier = com.apple.TextInputUI.xpc.CursorUIViewService
  ```
  C'est un **view service ViewBridge** (`otool -L` confirme le lien sur `ViewBridge.framework`)
  `[OBSERVÉ]`. On l'atteint par un `NSRemoteViewController` dont l'endpoint est remis par le
  process hôte — **il n'y a pas de nom mach de bootstrap à qui se connecter**, et pas
  d'`NSXPCListener` nommé. Un tiers n'a pas d'endpoint et ne peut pas en fabriquer un.
- Instance unique observée : un seul process `CursorUIViewService` tournait, `ServiceType = User`
  `[OBSERVÉ]` — partagé, mais toujours piloté par l'app hôte.
- Protocoles trouvés dans le binaire : `TUINSCursorUIViewServiceProtocol`,
  `TUINSCursorUIRemoteProtocol`, `TSMMessageProtocol`, avec les clés `tsmMessagePSNKey` et
  `tsmTargetTSMDocumentKeyKey` `[LU]`. Ce sont des protocoles NSXPC privés du couple
  app ↔ service, pas un bus de diffusion.
- **Aucun symbole de notification** : `nm -u` sur le binaire ne référence ni
  `CFNotificationCenter*`, ni `NSDistributedNotificationCenter`. La seule chaîne
  « notification » du binaire est le sélecteur `setNotificationOverride:` `[OBSERVÉ]`.

Aucune diffusion. Rien à écouter.

*Note de côté utile au ticket [01](../tickets/01-cadre-du-hud-au-vol.md) : la fenêtre du HUD est
une `TUINSWindow : NSWindow` créée **dans le process de l'app focalisée**, portant un
`NSRemoteViewController` et des `insets` — ce n'est pas une fenêtre système à part.*

---

## Précédents open-source

Honnêteté : **je n'ai pas trouvé d'input method « palette » tiers open-source** qui fasse
exactement ça. Ce qui existe :

- **Les palettes d'Apple elles-mêmes**, sur cette machine, sont le précédent le plus fort et il
  est de première main : `PressAndHold`, `CharacterPalette`, `Assistive Control`, `DictationIM`,
  `50onPaletteServer` `[LU]`.
- Les input methods clavier open-source classiques (Squirrel/Rime, fcitx5-macos,
  [`ensan-hcl/macOS_IMKitSample_2021`](https://github.com/ensan-hcl/macOS_IMKitSample_2021))
  utilisent `attributesForCharacterIndex:lineHeightRectangle:` pour poser leur fenêtre de
  candidats — ils valident l'API, mais **pas** le montage passthrough : ce sont des input sources
  clavier, qui se substituent bien au layout `[LU]`.
- Déclaration du protocole hors SDK, utile en secours :
  [`w0lfschild/macOS_headers` — IMKTextInput-Protocol.h](https://github.com/w0lfschild/macOS_headers/blob/master/macOS/Frameworks/InputMethodKit/365.16.13/IMKTextInput-Protocol.h) `[LU]`.
- Côté « position du caret pour un tiers », l'état de l'art public reste l'Accessibility :
  [`Aeastr/CursorBounds`](https://github.com/Aeastr/CursorBounds) `[LU]` — c'est précisément la
  solution que la piste 1 rend inutile pour les apps où AX ne donne rien.

Autrement dit : le montage est inédit publiquement mais il n'invente rien, il recopie
`PressAndHold`.

---

## Ce que ça implique pour le déclencheur « prise de focus d'un champ »

1. **Le déclencheur est `activateServer:`**, pas un observateur Accessibility. Il arrive dans
   toutes les apps, y compris Chrome, sans permission Accessibility et sans TCC `[OBSERVÉ]`.
2. **Le rect nul est le signal « pas de champ texte »**. `rect == NSZeroRect` +
   `selectedRange.location == NSNotFound` + dictionnaire d'attributs vide : c'est le cas de
   `systempreferences`, de l'écran d'accueil de VS Code, de Discord sans champ focalisé
   `[OBSERVÉ]`. Il faut donc **ne pas afficher la bulle sur un `activateServer:` à rect nul**, et
   re-interroger un instant plus tard : dans Chrome, le premier `activateServer:` donnait
   `{{0,0},{0,0}}` puis le second le vrai rect `[OBSERVÉ]`.
3. **Pas de notification « le caret a bougé »** — le canal est *pull*, pas *push*. Il faut poller
   le client retenu (1 Hz suffit pour un repositionnement, plus vite pendant que la bulle est
   affichée). Coût par appel non mesuré.
4. **L'agent doit être un bundle `.app` dans `~/Library/Input Methods`**, pas un binaire nu :
   c'est ce qui change la forme du ticket [07](../tickets/07-squelette-du-projet-swift.md). Il
   reste lancé à la main (la carte l'exige) — mais il doit être *lancé avant* d'être activé
   côté TIS, sinon `TISSelectInputSource` renvoie `-50` `[OBSERVÉ]`.
5. **Accessibility devient un repli, pas le socle.** Il reste utile pour ce que le canal IMK ne
   donne pas (identité/rôle du champ, distinction mot de passe), mais plus pour la position.

---

## Incertitudes restantes

- **Java / Swing / AWT : non testé.** Aucun JRE sur cette machine
  (`/usr/libexec/java_home` → « Unable to locate a Java Runtime ») `[OBSERVÉ]`. AWT implémente
  `NSTextInputClient` côté `CInputMethod`, donc ça *devrait* marcher, mais c'est `[DÉDUIT]`.
- **Electron : validé par transitivité seulement.** Chrome (même moteur de saisie) donne un vrai
  rect ; VS Code et Discord ont donné un rect nul, très probablement parce qu'aucun champ n'était
  focalisé au moment du test (fenêtre d'accueil, pas de clic possible depuis un agent). **À
  reconfirmer à la main**, c'est le seul trou sérieux de la démonstration.
- **Cohabitation avec le SCIM chinois non testée** : la palette reste-t-elle sélectionnée quand
  l'utilisateur bascule vers `com.apple.inputmethod.SCIM.WBH` ? Le cas de `PressAndHold`, toujours
  sélectionné, suggère que oui `[DÉDUIT]`. Et surtout : **la palette est-elle notifiée** du
  changement d'input source, ou faut-il un observateur `kTISNotifySelectedKeyboardInputSourceChanged`
  séparé ? Probablement le second — c'est le sujet du ticket sur le déclencheur « changement de
  langue ».
- **Modes internes du SCIM** (bascule chinois/anglais sans changer d'input source, cf. *Not yet
  specified* de la carte) : le canal IMK n'expose rien là-dessus dans ce qu'on a vu. Non résolu.
- **Persistance au login** : l'enregistrement TIS a tenu tant que le bundle était en place, mais
  le comportement après déconnexion/reconnexion n'a pas été testé. Une source désinstallée reste
  listée (`local.bubulle.probeim`, `enabled=0 selected=0`) jusqu'à purge du cache TIS `[OBSERVÉ]`.
- **Signature** : la sonde était signée ad-hoc (`codesign -s -`) et non sandboxée, et macOS 26.5
  l'a acceptée **sans aucun prompt utilisateur** `[OBSERVÉ]`. Rien ne garantit que ça survive à
  une mise à jour — c'est la contrepartie assumée par la carte.
- **Latence et coût** de `attributesForCharacterIndex:` (aller-retour IPC vers l'app) : non
  mesurés. À faire avant de choisir une fréquence de polling.

---

## Reproduire

Sondes écrites pour ces mesures (scratchpad de session, non versionnées) :
`dump.m` (dump du runtime ObjC après `dlopen` d'un framework privé),
`appkitprobe.m` / `gui.m` / `gui2.m` (auto-observation de `TUINSCursorUIController`),
`tis.m` (énumération TIS avec type/catégorie/état),
`reg.m` (`TISRegisterInputSource` / enable / select / disable),
`im.m` + `BubulleProbe.app` (palette IMK complète, log dans `/tmp/bubulle_probe.log`).

L'environnement a été **entièrement restauré** : palette désélectionnée et désactivée, bundle
supprimé de `~/Library/Input Methods`, process arrêté, `AppleSelectedInputSources` revenu à
`{PressAndHold, French}` `[OBSERVÉ]`.
