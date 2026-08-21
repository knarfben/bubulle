import Cocoa
import InputMethodKit

// Doit matcher InputMethodConnectionName dans Resources/Info.plist.
let kConnectionName = "local_bubulle_connection"

let server = IMKServer(name: kConnectionName, bundleIdentifier: Bundle.main.bundleIdentifier)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Force l'initialisation maintenant : l'observateur kTISNotifySelectedKeyboardInputSourceChanged
// doit être en place avant la première prise de focus, pas seulement au premier activateServer:.
_ = BubbleStateMachine.shared

Log.write("Bubulle démarré, pid=\(ProcessInfo.processInfo.processIdentifier), server=\(String(describing: server))")
app.run()
