// Sonde #18 — lire QUEL modificateur est enfoncé, sans permission.
//
// Question du ticket 18 : CGEventSourceCounterForEventType compte les flagsChanged mais ne dit
// pas lequel. Il faut le doubler d'une lecture d'état. Ni CGEventSource.flagsState ni
// NSEvent.modifierFlags n'ont jamais été mesurés dans ce projet.
//
// Protocole du #01 : bundle .app séparé, jamais autorisé, lancé par `open` pour être son propre
// responsible process et ne pas hériter des permissions du terminal.

import AppKit
import CoreGraphics
import ApplicationServices
import Carbon.HIToolbox

let logPath = "/tmp/bubulle-probe18.log"
FileManager.default.createFile(atPath: logPath, contents: nil)
let fh = FileHandle(forWritingAtPath: logPath)!

func log(_ s: String) {
    let line = s + "\n"
    fh.write(line.data(using: .utf8)!)
    FileHandle.standardError.write(line.data(using: .utf8)!)
}

func ms(_ t: CFAbsoluteTime) -> String { String(format: "%.1f", t * 1000) }

// MARK: - 1. Permissions : on prouve qu'on n'en a aucune

log("=== sonde 18 — \(Date()) ===")
log("pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(Bundle.main.bundleIdentifier ?? "?")")
log("AXIsProcessTrusted()            = \(AXIsProcessTrusted())")
log("CGPreflightListenEventAccess()  = \(CGPreflightListenEventAccess())")
log("CGPreflightScreenCaptureAccess()= \(CGPreflightScreenCaptureAccess())")
log("IsSecureEventInputEnabled()     = \(IsSecureEventInputEnabled())")

// MARK: - 2. Coût des trois lectures

func chrono(_ nom: String, _ n: Int, _ f: () -> Void) {
    f()   // réchauffe
    let t0 = CFAbsoluteTimeGetCurrent()
    for _ in 0..<n { f() }
    let dt = (CFAbsoluteTimeGetCurrent() - t0) / Double(n)
    log(String(format: "coût %-34s = %8.3f µs", (nom as NSString).utf8String!, dt * 1_000_000))
}

chrono("CGEventSource.flagsState", 20_000) {
    _ = CGEventSource.flagsState(.combinedSessionState)
}
chrono("NSEvent.modifierFlags", 20_000) {
    _ = NSEvent.modifierFlags
}
chrono("counterForEventType(.flagsChanged)", 20_000) {
    _ = CGEventSource.counterForEventType(.combinedSessionState, eventType: .flagsChanged)
}
chrono("counterForEventType(.keyDown)", 20_000) {
    _ = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
}

// MARK: - 3. Guet 60 Hz : les trois canaux côte à côte

// Les quatre modificateurs candidats, dans les deux vocabulaires.
let cibles: [(String, CGEventFlags, NSEvent.ModifierFlags)] = [
    ("⌃ control", .maskControl,   .control),
    ("⌥ option",  .maskAlternate, .option),
    ("⇧ shift",   .maskShift,     .shift),
    ("⌘ command", .maskCommand,   .command),
]

func etatCG() -> String {
    let f = CGEventSource.flagsState(.combinedSessionState)
    return cibles.map { f.contains($0.1) ? String($0.0.first!) : "·" }.joined()
}
func etatNS() -> String {
    let f = NSEvent.modifierFlags
    return cibles.map { f.contains($0.2) ? String($0.0.first!) : "·" }.joined()
}
func compteur(_ t: CGEventType) -> UInt32 {
    CGEventSource.counterForEventType(.combinedSessionState, eventType: t)
}

var dernierCG = etatCG()
var dernierNS = etatNS()
var dernierFlags = compteur(.flagsChanged)
var dernierKey = compteur(.keyDown)
var dernierMouse = compteur(.leftMouseDown) + compteur(.rightMouseDown) + compteur(.otherMouseDown)

log("")
log("état initial : CG=\(dernierCG) NS=\(dernierNS) flagsChanged=\(dernierFlags) keyDown=\(dernierKey)")
log("Tape ⌃⌃ (double control). Puis essaie sous `sudo -v` pour le secure input.")
log("Colonnes : ⌃⌥⇧⌘ — CG = CGEventSource.flagsState, NS = NSEvent.modifierFlags")
log("")

// Machine à double-tap : appui -> relâche -> appui -> relâche, aucun keyDown ni mouseDown entre.
enum Phase { case repos, premierAppui, entreDeux }
var phase = Phase.repos
var t0 = CFAbsoluteTimeGetCurrent()
let fenetre: CFTimeInterval = 0.50

let debut = CFAbsoluteTimeGetCurrent()

Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
    let cg = etatCG()
    let ns = etatNS()
    let fc = compteur(.flagsChanged)
    let kd = compteur(.keyDown)
    let md = compteur(.leftMouseDown) + compteur(.rightMouseDown) + compteur(.otherMouseDown)
    let now = CFAbsoluteTimeGetCurrent()

    if cg != dernierCG || ns != dernierNS || fc != dernierFlags {
        let divergence = (cg == ns) ? "" : "   ⚠️ CG≠NS"
        let secure = IsSecureEventInputEnabled() ? " SECURE" : ""
        log(String(format: "%8s  CG=%@ NS=%@  flagsChanged=%+d keyDown=%+d%@%@",
                   (ms(now - debut) as NSString).utf8String!,
                   cg, ns, Int(fc) - Int(dernierFlags), Int(kd) - Int(dernierKey), secure, divergence))
    }

    // Détection du double-⌃, sur l'état CG (on rejouera sur NS si CG est aveugle).
    let ctrlDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskControl)
    let seulement = etatCG().dropFirst().allSatisfy { $0 == "·" }
    let acte = (kd != dernierKey) || (md != dernierMouse)

    if acte, phase != .repos {
        log("   × séquence annulée : un keyDown/mouseDown est passé")
        phase = .repos
    }
    switch phase {
    case .repos:
        if ctrlDown && seulement { phase = .premierAppui; t0 = now }
    case .premierAppui:
        if !ctrlDown { phase = .entreDeux }
        else if now - t0 > fenetre { phase = .repos }
    case .entreDeux:
        if now - t0 > fenetre { phase = .repos }
        else if ctrlDown && seulement {
            log("   ✅ DOUBLE-⌃ détecté — Δ = \(ms(now - t0)) ms")
            phase = .repos
        }
    }

    dernierCG = cg; dernierNS = ns
    dernierFlags = fc; dernierKey = kd; dernierMouse = md
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
