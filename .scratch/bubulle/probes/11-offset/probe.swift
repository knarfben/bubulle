import AppKit
import Carbon
import Foundation

// Sonde #11 : corrèle le rect du caret (firstRect(forCharacterRange:), soit exactement
// la valeur qu'AppKit sert au canal NSTextInputClient/TSM que lit CursorUIViewService)
// au cadre du HUD système, sur un balayage de positions et de tailles de police.
//
// Aucune API privée : kCGWindowBounds suffit et ne demande aucune permission (recherche 01).

let kService = "CursorUIViewService"

func hudFrameCG() -> CGRect? {
    let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    var best: CGRect? = nil
    for w in all {
        guard (w[kCGWindowOwnerName as String] as? String) == kService else { continue }
        guard let d = w[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: d as CFDictionary) else { continue }
        if r.height > 70 { best = r }   // déployé (au repos : 64x64 ou 54x54)
    }
    return best
}

func inputSources() -> [String: TISInputSource] {
    let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    var m = [String: TISInputSource]()
    for s in list {
        guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { continue }
        m[Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String] = s
    }
    return m
}

func currentSourceID() -> String {
    guard let s = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

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

    func applicationDidFinishLaunching(_ n: Notification) {
        srcs = inputSources()
        original = currentSourceID()

        let scr = NSScreen.main!
        win = ProbeWindow(contentRect: NSRect(x: 400, y: 400, width: 420, height: 90),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        win.level = .normal
        win.backgroundColor = .white
        win.hasShadow = false
        tv = NSTextView(frame: NSRect(x: 8, y: 8, width: 404, height: 74))
        tv.isRichText = false
        tv.string = "abc"
        win.contentView?.addSubview(tv)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(tv)

        FileHandle.standardError.write("SCREEN frame=\(scr.frame) visible=\(scr.visibleFrame) backing=\(scr.backingScaleFactor)\n".data(using: .utf8)!)
        FileHandle.standardError.write("SCREENS \(NSScreen.screens.map { "\($0.frame)@\($0.backingScaleFactor)" })\n".data(using: .utf8)!)

        Thread.detachNewThread { self.run(screen: scr) }
    }

    func log(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
        out.append(s)
    }

    /// Rect du caret en coordonnées écran AppKit (origine bas-gauche de l'écran principal).
    func caretRectAppKit() -> NSRect {
        var actual = NSRange()
        let loc = tv.selectedRange().location
        return tv.firstRect(forCharacterRange: NSRange(location: loc, length: 0), actualRange: &actual)
    }

    /// Place la fenêtre pour que le coin bas-gauche du caret tombe sur `target` (coords AppKit).
    func placeCaret(at target: CGPoint) {
        for _ in 0..<6 {
            let r = caretRectAppKit()
            let d = CGPoint(x: target.x - r.minX, y: target.y - r.minY)
            if abs(d.x) < 0.05 && abs(d.y) < 0.05 { break }
            let o = win.frame.origin
            win.setFrameOrigin(NSPoint(x: o.x + d.x, y: o.y + d.y))
            win.displayIfNeeded()
        }
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

    /// Bascule l'input source et relève le cadre du HUD à t+250 ms.
    func triggerAndMeasure() -> CGRect? {
        let id = order[next % order.count]; next += 1
        guard let s = srcs[id] else { return nil }
        // macOS 26 : HIToolbox fait un dispatch_assert_queue(main) dans TSMSelectInputSource.
        var rc: OSStatus = 0
        DispatchQueue.main.sync { rc = TISSelectInputSource(s) }
        if rc != noErr { log("# TISSelectInputSource(\(id)) -> \(rc)"); return nil }
        usleep(260_000)
        var f = hudFrameCG()
        if f == nil { usleep(150_000); f = hudFrameCG() }
        return f
    }

    func sample(_ tag: String, fontSize: CGFloat, target: CGPoint) {
        DispatchQueue.main.sync {
            self.setFont(fontSize)
            self.placeCaret(at: target)
            NSApp.activate(ignoringOtherApps: true)
            self.win.makeFirstResponder(self.tv)
        }
        usleep(120_000)
        var caret = NSRect.zero
        DispatchQueue.main.sync { caret = self.caretRectAppKit() }
        guard let hud = triggerAndMeasure() else { log("\(tag)\tFONT=\(fontSize)\tNO_HUD\tcaret=\(fmt(caret))"); waitHudGone(); return }

        // conversion AppKit -> CG (origine haut-gauche de l'écran principal)
        let H = NSScreen.screens.first(where: { $0.frame.origin == .zero })!.frame.height
        let caretCG = CGRect(x: caret.minX, y: H - caret.maxY, width: caret.width, height: caret.height)
        let caps = hud.insetBy(dx: 27.5, dy: 27.5)
        log([tag, "font=\(fontSize)",
             "caretCG=\(fmt(caretCG))",
             "hud=\(fmt(hud))",
             "caps=\(fmt(caps))",
             "dxCenter=\(f2(caps.midX - caretCG.midX))",
             "dxLeft=\(f2(caps.minX - caretCG.minX))",
             "dyTop_caretBottom=\(f2(caps.minY - caretCG.maxY))",
             "dyTop_caretTop=\(f2(caps.minY - caretCG.minY))",
             "dyBottom_caretBottom=\(f2(caps.maxY - caretCG.maxY))",
            ].joined(separator: "\t"))
        waitHudGone()
    }

    func sampleNoPlace(_ tag: String) {
        DispatchQueue.main.sync {
            NSApp.activate(ignoringOtherApps: true)
            self.win.makeFirstResponder(self.tv)
            self.win.displayIfNeeded()
        }
        usleep(120_000)
        var caret = NSRect.zero
        DispatchQueue.main.sync { caret = self.caretRectAppKit() }
        guard let hud = triggerAndMeasure() else { log("\(tag)\tNO_HUD"); waitHudGone(); return }
        let Hs = NSScreen.screens.first(where: { $0.frame.origin == .zero })!.frame.height
        let caretCG = CGRect(x: caret.minX, y: Hs - caret.maxY, width: caret.width, height: caret.height)
        let caps = hud.insetBy(dx: 27.5, dy: 27.5)
        log([tag, "font=13.0",
             "caretCG=\(fmt(caretCG))", "hud=\(fmt(hud))", "caps=\(fmt(caps))",
             "dxCenter=\(f2(caps.midX - caretCG.midX))",
             "dxLeft=\(f2(caps.minX - caretCG.minX))",
             "dyTop_caretBottom=\(f2(caps.minY - caretCG.maxY))",
             "dyTop_caretTop=\(f2(caps.minY - caretCG.minY))",
             "dyBottom_caretBottom=\(f2(caps.maxY - caretCG.maxY))"].joined(separator: "\t"))
        waitHudGone()
    }

    /// Comme sampleNoPlace mais lit le rect de la sélection entière (largeur non nulle).
    func sampleNoPlaceRange(_ tag: String) {
        DispatchQueue.main.sync { NSApp.activate(ignoringOtherApps: true); self.win.makeFirstResponder(self.tv) }
        usleep(120_000)
        var caret = NSRect.zero
        DispatchQueue.main.sync {
            var actual = NSRange()
            caret = self.tv.firstRect(forCharacterRange: self.tv.selectedRange(), actualRange: &actual)
        }
        guard let hud = triggerAndMeasure() else { log("\(tag)\tNO_HUD"); waitHudGone(); return }
        let Hs = NSScreen.screens.first(where: { $0.frame.origin == .zero })!.frame.height
        let caretCG = CGRect(x: caret.minX, y: Hs - caret.maxY, width: caret.width, height: caret.height)
        let caps = hud.insetBy(dx: 27.5, dy: 27.5)
        log([tag, "font=13.0", "caretCG=\(fmt(caretCG))", "hud=\(fmt(hud))", "caps=\(fmt(caps))",
             "capsMid-rectMin=\(f2(caps.midX - caretCG.minX))",
             "capsMid-rectMid=\(f2(caps.midX - caretCG.midX))"].joined(separator: "\t"))
        waitHudGone()
    }

    func fmt(_ r: CGRect) -> String { "(\(f2(r.minX)),\(f2(r.minY)) \(f2(r.width))x\(f2(r.height)))" }
    func f2(_ v: CGFloat) -> String { String(format: "%.2f", Double(v)) }

    func run(screen scr: NSScreen) {
        let f = scr.frame
        let W = f.width, H = f.height
        log("# écran AppKit \(fmt(f))  visible \(fmt(scr.visibleFrame))  scale \(scr.backingScaleFactor)")
        log("# source d'origine : \(original)")

        let phase = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "ABC"

        if phase.contains("A") {
        // Phase A — offset vs taille de police, position centrale fixe
        for s in [11.0, 13.0, 18.0, 24.0, 36.0, 48.0] as [CGFloat] {
            sample("A-font", fontSize: s, target: CGPoint(x: 700, y: 600))
        }
        }

        if phase.contains("B") {
        // Phase B — balayage de positions, police 13
        let grid: [(String, CGPoint)] = [
            ("centre",      CGPoint(x: W/2,      y: H/2)),
            ("gauche",      CGPoint(x: 2,        y: H/2)),
            ("droite-100",  CGPoint(x: W - 100,  y: H/2)),
            ("droite-40",   CGPoint(x: W - 40,   y: H/2)),
            ("droite-4",    CGPoint(x: W - 4,    y: H/2)),
            ("bas-60",      CGPoint(x: W/2,      y: 60)),
            ("bas-20",      CGPoint(x: W/2,      y: 20)),
            ("bas-2",       CGPoint(x: W/2,      y: 2)),
            ("haut-40",     CGPoint(x: W/2,      y: H - 40)),
            ("haut-10",     CGPoint(x: W/2,      y: H - 10)),
            ("coin-BD",     CGPoint(x: W - 4,    y: 4)),
            ("coin-HD",     CGPoint(x: W - 4,    y: H - 10)),
            ("coin-BG",     CGPoint(x: 2,        y: 4)),
        ]
        for (n, p) in grid { sample("B-" + n, fontSize: 13, target: p) }
        }

        if phase.contains("C") {
        // Phase C — balayage fin du bord droit et du bord bas
        for dx in [140.0, 120.0, 100.0, 80.0, 60.0, 40.0, 20.0, 10.0, 2.0] as [CGFloat] {
            sample("C-droite-\(Int(dx))", fontSize: 13, target: CGPoint(x: W - dx, y: H/2))
        }
        for dy in [80.0, 60.0, 50.0, 40.0, 30.0, 20.0, 10.0, 2.0] as [CGFloat] {
            sample("C-bas-\(Int(dy))", fontSize: 13, target: CGPoint(x: W/2, y: dy))
        }
        }

        if phase.contains("F") {
        // Phase F — recoupement du rect AppKit (firstRect) avec le rect IMK que logge Bubulle.
        // Pas de bascule d'input source : on pose le caret et on tient 2,6 s pour que le poll
        // 1 Hz de la palette le voie au moins deux fois.
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = TimeZone(identifier: "UTC")
        for (i, cfg) in [(13.0, CGPoint(x: 300, y: 700)), (13.0, CGPoint(x: 900, y: 300)),
                         (18.0, CGPoint(x: 500, y: 500)), (28.0, CGPoint(x: 1200, y: 800)),
                         (11.0, CGPoint(x: 200, y: 200)), (48.0, CGPoint(x: 700, y: 600))].enumerated() {
            DispatchQueue.main.sync {
                self.setFont(CGFloat(cfg.0))
                self.placeCaret(at: cfg.1)
                NSApp.activate(ignoringOtherApps: true)
                self.win.makeFirstResponder(self.tv)
            }
            usleep(300_000)
            var caret = NSRect.zero
            DispatchQueue.main.sync { caret = self.caretRectAppKit() }
            log("F-\(i)\tt=\(df.string(from: Date()))\tfont=\(cfg.0)\tfirstRectAppKit=\(fmt(caret))")
            usleep(2_600_000)
        }
        }

        if phase.contains("E") {
        // Phase E — arrondi vertical (et re-confirmation horizontale) via un inset fractionnaire
        for k in 0..<9 {
            let frac = CGFloat(k) * 0.13
            DispatchQueue.main.sync {
                self.tv.textContainerInset = NSSize(width: frac, height: frac)
                self.tv.string = "abc"; self.tv.font = NSFont.systemFont(ofSize: 13)
                self.tv.selectedRange = NSRange(location: 3, length: 0)
                self.win.displayIfNeeded()
            }
            sampleNoPlace("E-inset-\(f2(frac))")
        }
        DispatchQueue.main.sync { self.tv.textContainerInset = .zero }
        // rect de caret non ponctuel : centré sur minX ou sur midX ?
        DispatchQueue.main.sync {
            self.tv.string = "MMMMMM"
            self.tv.selectedRange = NSRange(location: 0, length: 4)
        }
        sampleNoPlaceRange("E-selection-4")
        DispatchQueue.main.sync { self.tv.string = "abc"; self.tv.selectedRange = NSRange(location: 3, length: 0) }
        }

        if phase.contains("D") {
        // Phase D-x — arrondi horizontal : caret déplacé par pas fractionnaires
        // (index de caret dans une suite de « i », dont l'avance est fractionnaire)
        DispatchQueue.main.sync {
            self.tv.string = String(repeating: "i", count: 30)
            self.tv.font = NSFont.systemFont(ofSize: 13)
        }
        for i in 0..<14 {
            DispatchQueue.main.sync { self.tv.selectedRange = NSRange(location: i, length: 0) }
            sampleNoPlace("D-arrx-\(i)")
        }
        DispatchQueue.main.sync { self.tv.string = "abc" }

        // Phase D-y — arrondi vertical : hauteur de ligne fractionnaire
        for s in stride(from: 13.0, through: 15.0, by: 0.25) {
            sample("D-arry-\(s)", fontSize: CGFloat(s), target: CGPoint(x: 700, y: 600))
        }

        // Phase D-gauche — seuil du clamp gauche
        for x in [40.0, 30.0, 24.0, 20.0, 18.0, 16.0, 14.0, 12.0, 8.0, 4.0, 0.0] as [CGFloat] {
            sample("D-gauche-\(Int(x))", fontSize: 13, target: CGPoint(x: x, y: H/2))
        }

        // Phase D-bas — seuil de la bascule bas
        for dy in [40.0, 36.0, 34.0, 32.0, 30.0, 29.0, 28.0, 27.0, 26.0, 24.0] as [CGFloat] {
            sample("D-bas-\(Int(dy))", fontSize: 13, target: CGPoint(x: W/2, y: dy))
        }
        }

        // restauration
        if let s = srcs[original] { DispatchQueue.main.sync { _ = TISSelectInputSource(s) } }
        var restored = ""
        DispatchQueue.main.sync { restored = currentSourceID() }
        log("# source restaurée : \(restored)")
        try? out.joined(separator: "\n").write(toFile: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/probe11.tsv", atomically: true, encoding: .utf8)
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let d = App()
app.delegate = d
app.setActivationPolicy(.regular)
app.run()
