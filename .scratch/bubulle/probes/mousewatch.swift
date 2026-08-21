import Cocoa
import CoreGraphics

// Probe ponctuel : logue chaque mouseDown réel (CGEventTap listenOnly) avec l'app frontmost
// au moment de l'event, pour tracer l'origine d'un mouseDown périodique observé pendant les
// tests du ticket 12 (~toutes les 15-20s, sans clic humain).

func frontmostApp() -> String {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
}

let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.otherMouseDown.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: CGEventMask(mask),
    callback: { _, type, event, _ in
        let loc = event.location
        print("[\(Date())] mouseDown type=\(type.rawValue) loc=(\(loc.x),\(loc.y)) frontmost=\(frontmostApp())")
        fflush(stdout)
        return Unmanaged.passRetained(event)
    },
    userInfo: nil
) else {
    print("tapCreate a échoué — permission Input Monitoring manquante ?")
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("mousewatch démarré, pid=\(ProcessInfo.processInfo.processIdentifier)")
fflush(stdout)
RunLoop.main.run()
