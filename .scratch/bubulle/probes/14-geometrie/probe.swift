import AppKit
import Carbon
import Foundation

// Sonde #14 — géométrie du HUD hors du cas nominal.
// Fork de probes/11-offset/probe.swift, avec trois ajouts :
//   1. un index d'écran : toutes les cibles sont exprimées en coordonnées LOCALES à cet écran,
//      ce qui permet de rejouer les balayages sur le DELL @1x ;
//   2. un mode observateur (phase O) qui ne bascule rien lui-même — il écoute la notif TIS et
//      relève le cadre du HUD produit par une bascule clavier réelle (seul moyen d'atteindre
//      le Wubihua chinois, TISSelectInputSource renvoyant -50 sur un input method) ;
//   3. le relevé systématique de frame ET visibleFrame, pour trancher le bord bas Dock affiché.
//
// Aucune API privée : kCGWindowBounds suffit et ne demande aucune permission (recherche 01).

let kService = "CursorUIViewService"

/// Toutes les fenêtres CursorUIViewService « déployées » (au repos : 64x64 ou 54x54).
func hudFramesCG() -> [CGRect] {
    let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    var found: [CGRect] = []
    for w in all {
        guard (w[kCGWindowOwnerName as String] as? String) == kService else { continue }
        guard let d = w[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: d as CFDictionary) else { continue }
        if r.height > 70 { found.append(r) }
    }
    return found
}

func hudFrameCG() -> CGRect? { hudFramesCG().last }

func inputSources() -> [String: TISInputSource] {
    let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    var m = [String: TISInputSource]()
    for s in list {
        guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { continue }
        m[Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String] = s
    }
    return m
}

func str(_ s: TISInputSource, _ key: CFString) -> String {
    guard let p = TISGetInputSourceProperty(s, key) else { return "—" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

/// (id, nom localisé, Languages[0]) de la source courante. TISCopyCurrentKeyboardInputSource
/// échappe au cache par process (mesuré au #13), donc lisible depuis un process vivant.
func currentSource() -> (String, String, String) {
    guard let s = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return ("?", "?", "?") }
    var lang = "—"
    if let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceLanguages),
       let arr = Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as? [String], let f = arr.first {
        lang = f
    }
    return (str(s, kTISPropertyInputSourceID), str(s, kTISPropertyLocalizedName), lang)
}

func currentSourceID() -> String { currentSource().0 }

final class ProbeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class App: NSObject, NSApplicationDelegate {
    var win: ProbeWindow!
    var tv: NSTextView!
    var srcs: [String: TISInputSource] = [:]
    var order = ["com.apple.keylayout.US", "com.apple.keylayout.French"]
    var next = 0
    var original = ""
    var out: [String] = []
    var scr: NSScreen!
    var outPath = "/tmp/probe14.tsv"
    var observing = false
    var lastEvent = Date.distantPast

    /// Hauteur de l'écran primaire — pivot de la conversion AppKit -> CG.
    var primaryH: CGFloat { NSScreen.screens.first(where: { $0.frame.origin == .zero })!.frame.height }

    func applicationDidFinishLaunching(_ n: Notification) {
        srcs = inputSources()
        original = currentSourceID()

        outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/probe14.tsv"
        let phase = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "S"
        let idx = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3]) ?? 0 : 0

        let screens = NSScreen.screens
        scr = idx < screens.count ? screens[idx] : screens[0]

        for (i, s) in screens.enumerated() {
            FileHandle.standardError.write("SCREEN[\(i)] frame=\(s.frame) visible=\(s.visibleFrame) scale=\(s.backingScaleFactor)\n".data(using: .utf8)!)
        }

        let o = scr.frame.origin
        win = ProbeWindow(contentRect: NSRect(x: o.x + 200, y: o.y + 200, width: 420, height: 90),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        win.level = .normal
        win.backgroundColor = .white
        win.hasShadow = false
        tv = NSTextView(frame: NSRect(x: 8, y: 8, width: 404, height: 74))
        tv.isRichText = false
        tv.string = "abc"
        tv.font = NSFont.systemFont(ofSize: 13)
        win.contentView?.addSubview(tv)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(tv)

        if phase == "O" {
            startObserver()
        } else {
            Thread.detachNewThread { self.run(phase: phase) }
        }
    }

    func log(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
        out.append(s)
        try? out.joined(separator: "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
    }

    func fmt(_ r: CGRect) -> String { "(\(f2(r.minX)),\(f2(r.minY)) \(f2(r.width))x\(f2(r.height)))" }
    func f2(_ v: CGFloat) -> String { String(format: "%.2f", Double(v)) }

    // MARK: — géométrie

    /// Rect du caret en coordonnées écran AppKit (origine bas-gauche de l'écran primaire).
    func caretRectAppKit() -> NSRect {
        var actual = NSRange()
        let loc = tv.selectedRange().location
        return tv.firstRect(forCharacterRange: NSRange(location: loc, length: 0), actualRange: &actual)
    }

    func caretCG() -> CGRect {
        let r = caretRectAppKit()
        return CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height)
    }

    /// Cible en coordonnées LOCALES à l'écran choisi -> coordonnées AppKit globales.
    func T(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: scr.frame.minX + x, y: scr.frame.minY + y)
    }

    @discardableResult
    func placeCaret(at target: CGPoint) -> CGPoint {
        var d = CGPoint.zero
        for _ in 0..<8 {
            let r = caretRectAppKit()
            d = CGPoint(x: target.x - r.minX, y: target.y - r.minY)
            if abs(d.x) < 0.05 && abs(d.y) < 0.05 { break }
            let o = win.frame.origin
            win.setFrameOrigin(NSPoint(x: o.x + d.x, y: o.y + d.y))
            win.displayIfNeeded()
        }
        return d
    }

    /// Réduit la fenêtre pour que le caret ne soit plus qu'à quelques points de son bord bas.
    /// Sans ça, approcher le bord bas de l'écran demande une origine de fenêtre hors écran,
    /// et le placement décroche silencieusement.
    func resizeWindow(_ h: CGFloat) {
        let o = win.frame.origin
        win.setFrame(NSRect(x: o.x, y: o.y, width: 420, height: h), display: true)
        tv.frame = NSRect(x: 4, y: 2, width: 412, height: h - 4)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        win.displayIfNeeded()
    }

    func setFont(_ size: CGFloat) {
        tv.font = NSFont.systemFont(ofSize: size)
        tv.selectedRange = NSRange(location: 3, length: 0)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        win.displayIfNeeded()
    }

    func waitHudGone(_ deadline: Double = 2.5) {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < deadline {
            if hudFrameCG() == nil { return }
            usleep(30_000)
        }
    }

    /// Dernier cadre relevé, pour détecter une lecture périmée.
    var lastHud: CGRect? = nil

    /// Bascule l'input source et relève le cadre du HUD.
    ///
    /// `kCGWindowBounds` peut servir la position **précédente** du HUD pendant quelques
    /// centaines de ms — six relevés d'affilée avaient rendu un cadre identique alors que le
    /// caret bougeait. On relit donc jusqu'à ce que le cadre change, ce qui ne peut pas boucler
    /// à tort : le caret a bougé entre deux appels, donc le cadre doit bouger aussi.
    func triggerAndMeasure() -> CGRect? {
        let id = order[next % order.count]; next += 1
        guard let s = srcs[id] else { return nil }
        var rc: OSStatus = 0
        DispatchQueue.main.sync { rc = TISSelectInputSource(s) }   // main thread obligatoire (macOS 26)
        if rc != noErr { log("# TISSelectInputSource(\(id)) -> \(rc)"); return nil }
        let t0 = Date()
        var f: CGRect? = nil
        while Date().timeIntervalSince(t0) < 1.2 {
            usleep(60_000)
            guard let cur = hudFrameCG() else { continue }
            f = cur
            if lastHud == nil || !cur.equalTo(lastHud!) { break }
        }
        lastHud = f
        return f
    }

    /// Colonnes communes à tous les relevés : caret, cadre, capsule, et les écarts dérivés.
    func columns(_ tag: String, font: CGFloat, caret: CGRect, hud: CGRect) -> String {
        let caps = hud.insetBy(dx: 27.5, dy: 27.5)
        return [tag, "font=\(font)",
                "caretCG=\(fmt(caret))",
                "hud=\(fmt(hud))",
                "caps=\(fmt(caps))",
                "capsW=\(f2(caps.width))",
                "dxCenter=\(f2(caps.midX - caret.midX))",
                "dxLeft=\(f2(caps.midX - caret.minX))",
                "dyTop_caretBottom=\(f2(caps.minY - caret.maxY))",
                "dyBottom_caretTop=\(f2(caps.maxY - caret.minY))",
               ].joined(separator: "\t")
    }

    func sample(_ tag: String, fontSize: CGFloat, target: CGPoint) {
        var miss = CGPoint.zero
        DispatchQueue.main.sync {
            self.setFont(fontSize)
            miss = self.placeCaret(at: target)
            NSApp.activate(ignoringOtherApps: true)
            self.win.makeFirstResponder(self.tv)
        }
        usleep(120_000)
        var caret = CGRect.zero
        DispatchQueue.main.sync { caret = self.caretCG() }
        guard let hud = triggerAndMeasure() else {
            log("\(tag)\tfont=\(fontSize)\tNO_HUD\tcaretCG=\(fmt(caret))"); waitHudGone(); return
        }
        let flag = (abs(miss.x) > 0.05 || abs(miss.y) > 0.05) ? "\tPLACEMENT_RATE=\(f2(miss.x)),\(f2(miss.y))" : ""
        log(columns(tag, font: fontSize, caret: caret, hud: hud) + flag)
        waitHudGone()
    }

    func sampleNoPlace(_ tag: String) {
        DispatchQueue.main.sync {
            NSApp.activate(ignoringOtherApps: true)
            self.win.makeFirstResponder(self.tv)
            self.win.displayIfNeeded()
        }
        usleep(120_000)
        var caret = CGRect.zero
        DispatchQueue.main.sync { caret = self.caretCG() }
        guard let hud = triggerAndMeasure() else { log("\(tag)\tNO_HUD"); waitHudGone(); return }
        log(columns(tag, font: 13.0, caret: caret, hud: hud))
        waitHudGone()
    }

    // MARK: — mode observateur

    /// N'appelle jamais TISSelectInputSource : c'est Frank qui bascule au clavier. Sert à la
    /// fois à atteindre le Wubihua (interdit à un process tiers) et à vérifier qu'une bascule
    /// clavier réelle produit bien la même notif que l'appel programmatique.
    func startObserver() {
        observing = true
        let scrCG = CGRect(x: scr.frame.minX, y: primaryH - scr.frame.maxY,
                           width: scr.frame.width, height: scr.frame.height)
        log("# OBSERVATEUR — écran[\(NSScreen.screens.firstIndex(of: scr) ?? 0)] AppKit \(fmt(scr.frame)) / CG \(fmt(scrCG))")
        log("# visibleFrame AppKit \(fmt(scr.visibleFrame))  scale \(scr.backingScaleFactor)")
        log("# Dock : frame.minY=\(f2(scr.frame.minY)) visibleFrame.minY=\(f2(scr.visibleFrame.minY)) -> réserve basse \(f2(scr.visibleFrame.minY - scr.frame.minY)) pt")
        log("# source de départ : \(currentSource())")
        log("# Bascule la langue au clavier. Ctrl-C pour finir.")

        DispatchQueue.main.async {
            self.setFont(13)
            self.placeCaret(at: self.T(self.scr.frame.width / 2, self.scr.frame.height / 2))
            NSApp.activate(ignoringOtherApps: true)
            self.win.makeFirstResponder(self.tv)
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { [weak self] _ in self?.onSwitch() }

        // Filet : certaines bascules (input methods) peuvent ne pas notifier. On échantillonne
        // aussi le HUD en continu et on logge tout cadre déployé qu'aucune notif n'a couvert.
        Thread.detachNewThread { self.pollLoop() }
    }

    func onSwitch() {
        lastEvent = Date()
        let src = currentSource()
        // Rafale : on collecte TOUS les cadres distincts de la rafale. Maintenir le raccourci
        // fait apparaître le sélecteur d'input source (264x83), qui n'est pas la capsule à deux
        // lettres (84x77) ; garder « le plus large » ne relevait que le sélecteur.
        Thread.detachNewThread {
            var seen: [CGRect] = []
            let t0 = Date()
            while Date().timeIntervalSince(t0) < 1.6 {
                for f in hudFramesCG() where !seen.contains(where: { $0.equalTo(f) }) { seen.append(f) }
                usleep(25_000)
            }
            var caret = CGRect.zero
            DispatchQueue.main.sync { caret = self.caretCG() }
            guard !seen.isEmpty else {
                self.log("NOTIF\tid=\(src.0)\tname=\(src.1)\tlang=\(src.2)\tNO_HUD"); return
            }
            for hud in seen.sorted(by: { $0.width < $1.width }) {
                let kind = hud.width > 150 ? "SELECTEUR" : "CAPSULE"
                self.log("NOTIF\tid=\(src.0)\tname=\(src.1)\tlang=\(src.2)\t\(kind)\t"
                         + self.columns("obs", font: 13.0, caret: caret, hud: hud))
            }
        }
    }

    func pollLoop() {
        var seen: CGRect? = nil
        while observing {
            let frames = hudFramesCG()
            if let f = frames.last {
                let fresh = seen == nil || !f.equalTo(seen!)
                if fresh && Date().timeIntervalSince(lastEvent) > 1.6 {
                    var caret = CGRect.zero
                    var src = ("?", "?", "?")
                    // TIS hors du main thread = SIGTRAP sur macOS 26, pas un code d'erreur (#11).
                    DispatchQueue.main.sync { caret = self.caretCG(); src = currentSource() }
                    log("SANS-NOTIF\tsrc=\(src)\t" + columns("orphan", font: 13.0, caret: caret, hud: f))
                }
                seen = f
            } else if frames.isEmpty {
                seen = nil
            }
            usleep(40_000)
        }
    }

    // MARK: — phases automatiques

    func run(phase: String) {
        let f = scr.frame
        let W = f.width, H = f.height
        let scrCG = CGRect(x: f.minX, y: primaryH - f.maxY, width: W, height: H)
        log("# écran AppKit \(fmt(f))  CG \(fmt(scrCG))  visible \(fmt(scr.visibleFrame))  scale \(scr.backingScaleFactor)")
        log("# réserve basse (Dock) = visibleFrame.minY - frame.minY = \(f2(scr.visibleFrame.minY - f.minY)) pt")
        log("# source d'origine : \(original)")

        if phase.contains("A") {
            // Offset vs taille de police — l'écart de 4,5 pt tient-il à 1x ?
            for s in [11.0, 13.0, 18.0, 24.0, 36.0, 48.0] as [CGFloat] {
                sample("A-font-\(Int(s))", fontSize: s, target: T(W/2, H/2))
            }
        }

        if phase.contains("S") {
            // Bords latéraux : marge de 2,5 pt ?
            for dx in [140.0, 100.0, 60.0, 40.0, 20.0, 10.0, 2.0] as [CGFloat] {
                sample("S-droite-\(Int(dx))", fontSize: 13, target: T(W - dx, H/2))
            }
            for x in [40.0, 30.0, 24.0, 20.0, 18.0, 16.0, 14.0, 12.0, 8.0, 4.0, 0.0] as [CGFloat] {
                sample("S-gauche-\(Int(x))", fontSize: 13, target: T(x, H/2))
            }
        }

        if phase.contains("K") {
            // Bord bas : seuil de bascule. Rejoué Dock affiché, il tranche frame vs visibleFrame.
            DispatchQueue.main.sync { self.resizeWindow(26) }
            for dy in [60.0, 50.0, 44.0, 42.0, 40.0, 38.0, 36.0, 35.0, 34.0, 33.0, 32.0, 31.0, 30.0, 29.0, 28.0, 27.0, 26.0, 24.0, 20.0, 12.0, 4.0, 0.0] as [CGFloat] {
                sample("K-bas-\(Int(dy))", fontSize: 13, target: T(W/2, dy))
            }
            DispatchQueue.main.sync { self.resizeWindow(90) }
        }

        if phase.contains("L") {
            // Balayage bas long : assez haut pour attraper le seuil qu'il se réfère à `frame`
            // (bord physique) ou à `visibleFrame` (bord au-dessus du Dock).
            DispatchQueue.main.sync { self.resizeWindow(26) }
            for dy in [130.0, 120.0, 110.0, 100.0, 95.0, 90.0, 86.0, 84.0, 82.0, 80.0, 78.0, 76.0,
                       70.0, 60.0, 50.0, 40.0, 34.0, 32.0, 31.0, 30.0, 29.0, 28.0, 27.0, 24.0, 20.0] as [CGFloat] {
                sample("L-bas-\(Int(dy))", fontSize: 13, target: T(W/2, dy))
            }
            DispatchQueue.main.sync { self.resizeWindow(90) }
        }

        if phase.contains("M") {
            // Balayage au point près : seuil de bascule, puis apparition du clamp de la capsule
            // basculée quand le caret lui-même est passé sous le bord haut du Dock.
            DispatchQueue.main.sync { self.resizeWindow(26) }
            for dy in [106.0, 105.0, 104.0, 103.0, 102.0, 101.0, 100.0, 99.0, 98.0, 97.0, 96.0,
                       58.0, 56.0, 55.0, 54.0, 53.0, 52.0, 51.0, 50.0, 48.0, 46.0] as [CGFloat] {
                sample("M-bas-\(Int(dy))", fontSize: 13, target: T(W/2, dy))
            }
            DispatchQueue.main.sync { self.resizeWindow(90) }
        }

        if phase.contains("N") {
            // Seuil de bascule, recentré automatiquement sur le bord bas de `visibleFrame`.
            // Permet de rejouer la mesure quelle que soit la taille du Dock.
            DispatchQueue.main.sync { self.resizeWindow(26) }
            let v = scr.visibleFrame.minY - scr.frame.minY   // réserve basse, en points
            log("# N : réserve basse = \(f2(v)) pt ; seuil prédit (référence visibleFrame) dy = \(f2(v + 29))")
            for k in stride(from: 38.0, through: 20.0, by: -1.0) {
                sample("N-bas-\(Int(k))", fontSize: 13, target: T(W/2, v + CGFloat(k)))
            }
            DispatchQueue.main.sync { self.resizeWindow(90) }
        }

        if phase.contains("G") {
            // Clamp latéral gauche, recentré sur le bord gauche de `visibleFrame` : un Dock
            // posé à gauche sépare visibleFrame.minX de frame.minX et tranche la référence.
            let g = scr.visibleFrame.minX - scr.frame.minX   // réserve gauche, en points
            log("# G : réserve gauche = \(f2(g)) pt")
            for k in stride(from: 40.0, through: -12.0, by: -4.0) {
                sample("G-gauche-\(Int(k))", fontSize: 13, target: T(g + CGFloat(k), H/2))
            }
        }

        if phase.contains("X") {
            // Arrondi horizontal : le seuil de 0,4 tient-il sur une grille de pixels 1x ?
            DispatchQueue.main.sync {
                self.tv.string = String(repeating: "i", count: 30)
                self.tv.font = NSFont.systemFont(ofSize: 13)
                self.placeCaret(at: self.T(W/2, H/2))
            }
            for i in 0..<14 {
                DispatchQueue.main.sync { self.tv.selectedRange = NSRange(location: i, length: 0) }
                sampleNoPlace("X-arrx-\(i)")
            }
            DispatchQueue.main.sync { self.tv.string = "abc"; self.tv.selectedRange = NSRange(location: 3, length: 0) }
        }

        if let s = srcs[original] { DispatchQueue.main.sync { _ = TISSelectInputSource(s) } }
        var restored = ""
        DispatchQueue.main.sync { restored = currentSourceID() }
        log("# source restaurée : \(restored)")
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let d = App()
app.delegate = d
app.setActivationPolicy(.regular)
app.run()
