// Ids des fenêtres Ghostty susceptibles d'être des fenêtres de terminal (calque 0, assez hautes),
// triés. CGWindowList voit toutes les fenêtres, y compris celles des autres Spaces — contrairement
// à l'énumération AX, qui en rate et renvoie parfois zéro.
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
var ids: [Int] = []
for w in list {
    guard ((w[kCGWindowOwnerName as String] as? String) ?? "").lowercased().contains("ghostty") else { continue }
    guard (w[kCGWindowLayer as String] as? Int) == 0 else { continue }
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    guard (b["Height"] ?? 0) > 200 else { continue }
    ids.append((w[kCGWindowNumber as String] as? Int) ?? -1)
}
for id in ids.sorted() { print(id) }
