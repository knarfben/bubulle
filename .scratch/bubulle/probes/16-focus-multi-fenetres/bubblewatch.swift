// Sonde : la bulle de Bubulle est-elle à l'écran ? Lit CGWindowListCopyWindowInfo (owner, bounds,
// alpha et isOnscreen ne réclament aucune permission — seuls les titres exigeraient Screen
// Recording) et filtre sur le pid du process Bubulle.
//
// Rend aussi les compteurs d'actes du ticket 04. Une bulle peut disparaître pour une raison
// parfaitement légitime — une frappe, un clic, un scroll ailleurs dans la session pendant que la
// boucle tourne. Sans les compteurs, ce bruit-là est indiscernable de la régression du ticket 16,
// et le test est flaky pour rien.
//
// Sortie : "<VISIBLE|HORS-ECRAN|ABSENTE> x=… y=… w=… h=… alpha=… actes=<n>"
import CoreGraphics
import Foundation

let pid = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1])! : 0

func actes() -> UInt32 {
    func c(_ t: CGEventType) -> UInt32 {
        CGEventSource.counterForEventType(.combinedSessionState, eventType: t)
    }
    return c(.keyDown) &+ c(.leftMouseDown) &+ c(.rightMouseDown) &+ c(.otherMouseDown) &+ c(.scrollWheel)
}

guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
    print("ERREUR liste"); exit(2)
}
var found = false
for w in list {
    guard let owner = w[kCGWindowOwnerPID as String] as? Int, owner == pid else { continue }
    let alpha = (w[kCGWindowAlpha as String] as? Double) ?? -1
    let onscreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    print("\(onscreen ? "VISIBLE" : "HORS-ECRAN") x=\(b["X"] ?? -1) y=\(b["Y"] ?? -1) w=\(b["Width"] ?? -1) h=\(b["Height"] ?? -1) alpha=\(alpha) actes=\(actes())")
    found = true
}
if !found { print("ABSENTE actes=\(actes())") }
