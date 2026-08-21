import CoreGraphics
import Foundation
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
let p = CGPoint(x: x, y: y)
for (t, isDown) in [(CGEventType.leftMouseDown, true), (CGEventType.leftMouseUp, false)] {
    let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!
    e.post(tap: .cghidEventTap)
    if isDown { usleep(60_000) }
}
