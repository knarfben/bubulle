// Tape une chaîne puis (optionnellement) Entrée, en vrais CGEvent.
//   frappe "texte" [entree]
//   frappe --cmd n        -> ⌘N
import CoreGraphics
import Foundation
let src = CGEventSource(stateID: .hidSystemState)
let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--cmd", args.count > 1 {
    let touches: [String: CGKeyCode] = ["n": 45, "w": 13]
    guard let code = touches[args[1]] else { exit(2) }
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
        e.flags = .maskCommand
        e.post(tap: .cghidEventTap)
    }
    exit(0)
}

for ch in args[0].unicodeScalars {
    var u = [UniChar(ch.value)]
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)!
        e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
        e.post(tap: .cghidEventTap)
    }
    usleep(25_000)
}
if args.count > 1 && args[1] == "entree" {
    for down in [true, false] {
        CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: down)!.post(tap: .cghidEventTap)
    }
}
