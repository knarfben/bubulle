import AppKit

// Relève le rect réel de la fenêtre Dock (CGWindowList, aucune permission) et le compare
// à visibleFrame. Sert à trancher la référence du seuil de bascule bas du HUD.
for (i, s) in NSScreen.screens.enumerated() {
    print("SCREEN[\(i)] frame=\(s.frame) visible=\(s.visibleFrame) scale=\(s.backingScaleFactor)")
    let h = NSScreen.screens.first(where: { $0.frame.origin == .zero })!.frame.height
    let fCG = CGRect(x: s.frame.minX, y: h - s.frame.maxY, width: s.frame.width, height: s.frame.height)
    let vCG = CGRect(x: s.visibleFrame.minX, y: h - s.visibleFrame.maxY, width: s.visibleFrame.width, height: s.visibleFrame.height)
    print("  CG frame=\(fCG) visible=\(vCG)  -> bord bas CG frame=\(fCG.maxY) visible=\(vCG.maxY)")
}
let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
for w in all where (w[kCGWindowOwnerName as String] as? String) == "Dock" {
    let name = (w[kCGWindowName as String] as? String) ?? "—"
    let layer = (w[kCGWindowLayer as String] as? Int) ?? -1
    guard let d = w[kCGWindowBounds as String] as? [String: Any],
          let r = CGRect(dictionaryRepresentation: d as CFDictionary) else { continue }
    if r.width < 20 || r.height < 20 { continue }
    print("DOCKWIN name=\(name) layer=\(layer) boundsCG=\(r)")
}
