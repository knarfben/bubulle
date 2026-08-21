// PROTOTYPE JETABLE — ticket « Clone visuel du HUD, à l'écran ».
// Question : à quoi ressemble notre bulle, et notre niveau de fenêtre passe-t-il
// AU-DESSUS du HUD de CursorUIViewService ?
//
// 4 variantes affichées sous le curseur, commutables depuis la fenêtre de contrôle.
// Aucune détection : la position suit la souris, exprès, pour que tu puisses garer
// la bulle pile sur la vraie et juger la superposition à l'œil.
//
// Ne pas promouvoir ce code : pas de tests, pas de gestion d'erreur, tout en dur.

import AppKit
import Carbon.HIToolbox

// ---------------------------------------------------------------- variantes

enum Variant: Int, CaseIterable {
    case cloneStrict, capsuleOpaque, drapeauNu, drapeauEtCode

    var key: String { ["A", "B", "C", "D"][rawValue] }
    var title: String {
        switch self {
        case .cloneStrict:   return "A — clone strict (hudWindow, drapeau seul)"
        case .capsuleOpaque: return "B — capsule opaque pilule + liseré"
        case .drapeauNu:     return "C — drapeau nu, sans capsule"
        case .drapeauEtCode: return "D — drapeau + code langue"
        }
    }
}

enum FlagChoice: Int, CaseIterable {
    case fr, us, cn, ir, frVector

    var label: String { ["🇫🇷 France (emoji)", "🇺🇸 US (emoji)", "🇨🇳 Chine (emoji)",
                         "🇮🇷 Iran (emoji)", "🇫🇷 France (vectoriel dessiné)"][rawValue] }
    var emoji: String { ["🇫🇷", "🇺🇸", "🇨🇳", "🇮🇷", "🇫🇷"][rawValue] }
    var code: String { ["FR", "US", "CN", "FA", "FR"][rawValue] }
    var isVector: Bool { self == .frVector }
}

// ---------------------------------------------------------------- drapeau

final class FlagView: NSView {
    var choice: FlagChoice = .fr { didSet { needsDisplay = true } }
    var outlined = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        if choice.isVector {
            let radius = r.height * 0.14
            let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
            NSGraphicsContext.saveGraphicsState()
            path.setClip()
            let band = r.width / 3
            NSColor(srgbRed: 0.00, green: 0.14, blue: 0.58, alpha: 1).setFill()
            NSRect(x: r.minX, y: r.minY, width: band, height: r.height).fill()
            NSColor.white.setFill()
            NSRect(x: r.minX + band, y: r.minY, width: band, height: r.height).fill()
            NSColor(srgbRed: 0.93, green: 0.13, blue: 0.22, alpha: 1).setFill()
            NSRect(x: r.minX + 2 * band, y: r.minY, width: band, height: r.height).fill()
            NSGraphicsContext.restoreGraphicsState()
            if outlined {
                NSColor.white.withAlphaComponent(0.85).setStroke()
                path.lineWidth = max(1, r.height * 0.06)
                path.stroke()
            }
        } else {
            let font = NSFont(name: "Apple Color Emoji", size: r.height * 0.95)
                ?? NSFont.systemFont(ofSize: r.height * 0.9)
            let s = NSAttributedString(string: choice.emoji, attributes: [.font: font])
            let sz = s.size()
            s.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
        }
    }
}

// ---------------------------------------------------------------- bulle

/// Construit le contenu d'une variante et rend sa taille.
func makeBubbleContent(_ variant: Variant, height h: CGFloat, flag: FlagChoice) -> NSView {
    let container = NSView()
    container.wantsLayer = true

    let flagView = FlagView()
    flagView.choice = flag
    flagView.translatesAutoresizingMaskIntoConstraints = false

    func addBackground(_ bg: NSView, radius: CGFloat) {
        bg.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bg, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bg.topAnchor.constraint(equalTo: container.topAnchor),
            bg.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        bg.wantsLayer = true
        bg.layer?.cornerRadius = radius
        bg.layer?.cornerCurve = .continuous
        bg.layer?.masksToBounds = true
    }

    var size: NSSize
    var flagHeight: CGFloat

    switch variant {
    case .cloneStrict:
        size = NSSize(width: h * 1.32, height: h)
        flagHeight = h * 0.58
        let vev = NSVisualEffectView()
        vev.material = .hudWindow
        vev.blendingMode = .behindWindow
        vev.state = .active
        addBackground(vev, radius: h * 0.26)

    case .capsuleOpaque:
        size = NSSize(width: h * 1.32, height: h)
        flagHeight = h * 0.58
        flagView.outlined = true
        let solid = NSView()
        addBackground(solid, radius: h * 0.5)
        solid.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        solid.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
        solid.layer?.borderWidth = 1

    case .drapeauNu:
        size = NSSize(width: h * 1.32, height: h)
        flagHeight = h * 0.92
        flagView.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.55)
            s.shadowBlurRadius = h * 0.18
            s.shadowOffset = NSSize(width: 0, height: -h * 0.06)
            return s
        }()
        flagView.wantsLayer = true

    case .drapeauEtCode:
        size = NSSize(width: h * 2.35, height: h)
        flagHeight = h * 0.55
        let vev = NSVisualEffectView()
        vev.material = .hudWindow
        vev.blendingMode = .behindWindow
        vev.state = .active
        addBackground(vev, radius: h * 0.26)
    }

    container.frame = NSRect(origin: .zero, size: size)
    container.addSubview(flagView)

    if variant == .drapeauEtCode {
        let label = NSTextField(labelWithString: flag.code)
        label.font = .systemFont(ofSize: h * 0.42, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            flagView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: h * 0.28),
            flagView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            flagView.heightAnchor.constraint(equalToConstant: flagHeight),
            flagView.widthAnchor.constraint(equalToConstant: flagHeight * 1.5),
            label.leadingAnchor.constraint(equalTo: flagView.trailingAnchor, constant: h * 0.22),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    } else {
        NSLayoutConstraint.activate([
            flagView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            flagView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            flagView.heightAnchor.constraint(equalToConstant: flagHeight),
            flagView.widthAnchor.constraint(equalToConstant: flagHeight * 1.5),
        ])
    }

    return container
}

final class BubblePanel: NSPanel {
    let variant: Variant

    init(variant: Variant) {
        self.variant = variant
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        level = .screenSaver
    }

    func rebuild(height: CGFloat, flag: FlagChoice) {
        let content = makeBubbleContent(variant, height: height, flag: flag)
        setContentSize(content.frame.size)
        contentView = content
    }
}

// ---------------------------------------------------------------- niveaux

struct LevelChoice {
    let label: String
    let level: NSWindow.Level
}

let levelChoices: [LevelChoice] = [
    .init(label: "floating (3)", level: .floating),
    .init(label: "statusBar (25)", level: .statusBar),
    .init(label: "popUpMenu (101)", level: .popUpMenu),
    .init(label: "screenSaver (1000)", level: .screenSaver),
    .init(label: "assistiveTechHigh (\(Int(CGWindowLevelForKey(.assistiveTechHighWindow))))",
          level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))),
    .init(label: "shielding (\(Int(CGShieldingWindowLevel())))",
          level: NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))),
]

// ---------------------------------------------------------------- input sources

func sourceProperty(_ src: TISInputSource, _ key: CFString) -> String? {
    guard let p = TISGetInputSourceProperty(src, key) else { return nil }
    return (Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String)
}

func selectableKeyboardSources() -> [TISInputSource] {
    guard let cf = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return [] }
    let all = cf as! [TISInputSource]
    return all.filter { src in
        guard let cat = sourceProperty(src, kTISPropertyInputSourceCategory),
              cat == (kTISCategoryKeyboardInputSource as String) else { return false }
        guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsSelectCapable) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
    }
}

// ---------------------------------------------------------------- raccourci global

// RegisterEventHotKey ne demande aucune permission TCC et marche même quand
// l'app n'est pas au premier plan — donc on peut geler la bulle sans toucher
// à la souris qu'on vient de garer sur le caret.
var globalHotKeyAction: (() -> Void)?
var hotKeyRefKeeper: EventHotKeyRef?

func installGlobalHotKey() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
        DispatchQueue.main.async { globalHotKeyAction?() }
        return noErr
    }, 1, &spec, nil, nil)
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: 0x42554255, id: 1)   // 'BUBU'
    let status = RegisterEventHotKey(UInt32(kVK_ANSI_B),
                                     UInt32(controlKey | optionKey | cmdKey),
                                     id, GetApplicationEventTarget(), 0, &ref)
    hotKeyRefKeeper = ref
    print(status == noErr ? ">> raccourci ⌃⌥⌘B armé (geler / dégeler la bulle)"
                          : "!! raccourci non armé (status \(status))")
}

// ---------------------------------------------------------------- contrôleur

final class Controller: NSObject {
    var panels: [Variant: BubblePanel] = [:]
    var mode: Variant? = nil          // nil = toutes les variantes en rang
    var flag: FlagChoice = .fr
    // 22 pt = hauteur mesurée de la capsule système (29x22, cf. recherche sur le cadre du HUD)
    var height: CGFloat = 22
    var levelIndex = 3
    var followMouse = true
    var frozen: NSPoint? = nil      // position retenue quand la bulle ne suit plus la souris
    var timer: Timer?

    let statusLabel = NSTextField(labelWithString: "")
    var followCheckbox: NSButton?

    func start() {
        for v in Variant.allCases {
            let p = BubblePanel(variant: v)
            panels[v] = p
        }
        rebuildAll()
        buildControlWindow()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.reposition()
        }
        RunLoop.main.add(timer!, forMode: .common)
        applyMode()
        installGlobalHotKey()
        globalHotKeyAction = { [weak self] in self?.toggleFreezeAtMouse() }
        logState()
    }

    func rebuildAll() {
        for (_, p) in panels {
            p.rebuild(height: height, flag: flag)
            p.level = levelChoices[levelIndex].level
        }
    }

    /// Les bulles se placent sous le curseur, comme le HUD se place sous le caret.
    func reposition() {
        let mouse = followMouse
            ? NSEvent.mouseLocation
            : (frozen ?? NSPoint(x: (NSScreen.main?.frame.midX ?? 600),
                                 y: (NSScreen.main?.frame.midY ?? 400)))
        let gap: CGFloat = 22

        if let solo = mode {
            guard let p = panels[solo] else { return }
            let s = p.frame.size
            p.setFrameOrigin(NSPoint(x: mouse.x - s.width / 2, y: mouse.y - gap - s.height))
        } else {
            let ordered = Variant.allCases.compactMap { panels[$0] }
            let spacing: CGFloat = 14
            let total = ordered.reduce(0) { $0 + $1.frame.width } + spacing * CGFloat(ordered.count - 1)
            var x = mouse.x - total / 2
            for p in ordered {
                p.setFrameOrigin(NSPoint(x: x, y: mouse.y - gap - p.frame.height))
                x += p.frame.width + spacing
            }
        }
    }

    func applyMode() {
        for (v, p) in panels {
            let visible = (mode == nil) || (mode == v)
            if visible { p.orderFrontRegardless() } else { p.orderOut(nil) }
        }
        reposition()
    }

    func logState() {
        let modeStr = mode.map { $0.title } ?? "toutes les variantes"
        let s = """
        ── état ──────────────────────────────
        mode      : \(modeStr)
        drapeau   : \(flag.label)
        hauteur   : \(Int(height)) pt
        niveau    : \(levelChoices[levelIndex].label)
        souris    : \(followMouse ? "suit le curseur" : "figé au centre")
        """
        print(s)
        statusLabel.stringValue = "niveau \(levelChoices[levelIndex].label) · \(Int(height)) pt · "
            + (mode?.key ?? "A+B+C+D")
    }

    // --- actions

    @objc func modeChanged(_ sender: NSPopUpButton) {
        mode = sender.indexOfSelectedItem == 0 ? nil : Variant(rawValue: sender.indexOfSelectedItem - 1)
        applyMode(); logState()
    }

    @objc func flagChanged(_ sender: NSPopUpButton) {
        flag = FlagChoice(rawValue: sender.indexOfSelectedItem) ?? .fr
        rebuildAll(); reposition(); logState()
    }

    @objc func levelChanged(_ sender: NSPopUpButton) {
        levelIndex = sender.indexOfSelectedItem
        for (_, p) in panels { p.level = levelChoices[levelIndex].level }
        // un ré-ordonnancement force la prise en compte immédiate
        applyMode(); logState()
    }

    @objc func bigger() { height = min(80, height + 2); rebuildAll(); reposition(); logState() }
    @objc func smaller() { height = max(16, height - 2); rebuildAll(); reposition(); logState() }

    /// Gèle la bulle là où elle est, ou la relâche. Déclenché par ⌃⌥⌘B,
    /// donc sans jamais déplacer la souris.
    @objc func toggleFreezeAtMouse() {
        followMouse.toggle()
        frozen = followMouse ? nil : NSEvent.mouseLocation
        followCheckbox?.state = followMouse ? .on : .off
        reposition(); logState()
        print(followMouse ? ">> dégelée, elle resuit la souris" : ">> gelée sur place")
    }

    @objc func toggleFollow(_ sender: NSButton) {
        followMouse = (sender.state == .on)
        frozen = followMouse ? nil : NSEvent.mouseLocation   // fige SUR PLACE, pas au centre
        reposition(); logState()
    }

    @objc func replayAnimation() {
        let targets = mode.map { [panels[$0]!] } ?? Variant.allCases.compactMap { panels[$0] }
        for p in targets { p.alphaValue = 0 }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            for p in targets { p.animator().alphaValue = 1 }
        } completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    for p in targets { p.animator().alphaValue = 0 }
                } completionHandler: {
                    for p in targets { p.alphaValue = 1 }
                }
            }
        }
    }

    /// Compte à rebours puis bascule : le temps de revenir dans ton champ texte
    /// et d'y garer ta souris, sans que le clic sur ce bouton fausse le test.
    @objc func triggerSystemHUD() {
        countdown(from: 6)
    }

    func countdown(from n: Int) {
        if n <= 0 { statusLabel.stringValue = "→ bascule !"; doSwitch(); return }
        statusLabel.stringValue = "bascule dans \(n) s — reclique dans ton champ, gare la souris sur le caret"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.countdown(from: n - 1) }
    }

    /// Déclenche le vrai HUD système, puis restaure la source d'origine.
    func doSwitch() {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            print("!! impossible de lire la source courante"); return
        }
        let currentID = sourceProperty(current, kTISPropertyInputSourceID) ?? "?"
        let others = selectableKeyboardSources().filter {
            sourceProperty($0, kTISPropertyInputSourceID) != currentID
        }
        guard let other = others.first else { print("!! aucune autre source sélectionnable"); return }
        let otherID = sourceProperty(other, kTISPropertyInputSourceID) ?? "?"
        print(">> bascule \(currentID) → \(otherID) (retour dans 2,5 s)")
        TISSelectInputSource(other)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            TISSelectInputSource(current)
            print(">> restauré : \(currentID)")
        }
    }

    @objc func quit() { NSApp.terminate(nil) }

    // --- fenêtre de contrôle

    func buildControlWindow() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "Bubulle — prototype visuel"
        win.level = .modalPanel

        func popup(_ items: [String], _ action: Selector, selected: Int) -> NSPopUpButton {
            let p = NSPopUpButton()
            p.addItems(withTitles: items)
            p.selectItem(at: selected)
            p.target = self
            p.action = action
            return p
        }
        func button(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            return b
        }
        func row(_ label: String, _ control: NSView) -> NSStackView {
            let l = NSTextField(labelWithString: label)
            l.alignment = .right
            l.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            l.widthAnchor.constraint(equalToConstant: 78).isActive = true
            let s = NSStackView(views: [l, control])
            s.orientation = .horizontal
            s.spacing = 8
            return s
        }

        let modeItems = ["Toutes (comparaison)"] + Variant.allCases.map { $0.title }
        let sizeStack = NSStackView(views: [button("−", #selector(smaller)),
                                            button("+", #selector(bigger))])
        sizeStack.orientation = .horizontal

        let follow = NSButton(checkboxWithTitle: "La bulle suit le curseur  (⌃⌥⌘B pour geler)",
                              target: self, action: #selector(toggleFollow(_:)))
        follow.state = .on
        followCheckbox = follow

        statusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            row("Variante", popup(modeItems, #selector(modeChanged(_:)), selected: 0)),
            row("Drapeau", popup(FlagChoice.allCases.map { $0.label }, #selector(flagChanged(_:)), selected: 0)),
            row("Niveau", popup(levelChoices.map { $0.label }, #selector(levelChanged(_:)), selected: levelIndex)),
            row("Hauteur", sizeStack),
            follow,
            button("Rejouer l'animation d'apparition", #selector(replayAnimation)),
            button("Bascule d'input source dans 6 s (va garer ta souris)", #selector(triggerSystemHUD)),
            statusLabel,
            button("Quitter", #selector(quit)),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        win.contentView = content
        win.setContentSize(stack.fittingSize)
        win.center()
        win.makeKeyAndOrderFront(nil)
    }
}

// ---------------------------------------------------------------- lancement

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        controller.start()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
app.delegate = delegate
print("""
PROTOTYPE bubulle — clone visuel du HUD
Gare la bulle sur la vraie (elle suit ton curseur), déclenche le HUD système,
et regarde qui passe au-dessus. Change le niveau si la nôtre passe dessous.
""")
app.run()
