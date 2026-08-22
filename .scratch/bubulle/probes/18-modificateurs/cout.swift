// Re-mesure des coûts en défaisant l'élision : on accumule le résultat et on l'imprime.
import AppKit
import CoreGraphics

var sink: UInt64 = 0
func chrono(_ nom: String, _ n: Int, _ f: () -> UInt64) {
    _ = f()
    let t0 = CFAbsoluteTimeGetCurrent()
    for _ in 0..<n { sink &+= f() }
    let dt = (CFAbsoluteTimeGetCurrent() - t0) / Double(n)
    print(String(format: "%-36s = %8.3f µs", (nom as NSString).utf8String!, dt * 1_000_000))
}
chrono("CGEventSource.flagsState", 200_000) { UInt64(CGEventSource.flagsState(.combinedSessionState).rawValue) }
chrono("NSEvent.modifierFlags", 200_000) { UInt64(NSEvent.modifierFlags.rawValue) }
chrono("counterForEventType(.flagsChanged)", 200_000) { UInt64(CGEventSource.counterForEventType(.combinedSessionState, eventType: .flagsChanged)) }
print("sink=\(sink)")
