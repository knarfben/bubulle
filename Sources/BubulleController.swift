import Cocoa
import InputMethodKit

// IMKTextInput.attributesForCharacterIndex:lineHeightRectangle: n'est déclaré nulle part dans
// InputMethodKit.framework (seulement dans HIToolbox/IMKInputSession.h, hors SDK public
// InputMethodKit). Cf. research/02-canal-universel-vers-le-caret.md §1.1 : on redéclare le
// protocole minimal ici et on caste le client reçu par activateServer:.
@objc protocol BubulleTextInput: NSObjectProtocol {
    @objc(attributesForCharacterIndex:lineHeightRectangle:)
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>?) -> [AnyHashable: Any]?

    @objc(selectedRange)
    func selectedRange() -> NSRange

    @objc(bundleIdentifier)
    func bundleIdentifier() -> String?
}

// @objc(BubulleController) fixe le nom ObjC-runtime de la classe : IMKServer résout
// InputMethodServerControllerClass via NSClassFromString sur ce nom exact, indépendamment
// du nom de module Swift que swiftc choisit à la compilation.
@objc(BubulleController)
final class BubulleController: IMKInputController {
    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        guard let client = Self.castToTextInput(sender) else {
            Log.write("activateServer: sender ne répond pas au protocole BubulleTextInput (\(String(describing: sender)))")
            return
        }
        BubbleStateMachine.shared.priseDeFocus(client: client)
    }

    // `sender as? BubulleTextInput` compile en `conformsToProtocol:`. Le client réel
    // (_IPMDServerClientWrapperLegacy) répond aux sélecteurs mais ne déclare pas la conformance
    // à un protocole qui n'existe que dans notre binaire — donc le cast Swift échoue toujours.
    // On vérifie chaque sélecteur avec responds(to:) puis on force le typage.
    // Cf. ticket 10 : la sonde ObjC ne voyait pas le problème, un cast id<IMKTextInput> n'y est
    // pas vérifié à l'exécution.
    private static func castToTextInput(_ sender: Any!) -> BubulleTextInput? {
        guard let obj = sender as AnyObject? else { return nil }
        let selectors: [Selector] = [
            #selector(BubulleTextInput.attributes(forCharacterIndex:lineHeightRectangle:)),
            #selector(BubulleTextInput.selectedRange),
            #selector(BubulleTextInput.bundleIdentifier)
        ]
        for sel in selectors where !obj.responds(to: sel) {
            Log.write("activateServer: sender ne répond pas à \(sel) (\(String(describing: sender)))")
            return nil
        }
        return unsafeBitCast(obj, to: BubulleTextInput.self)
    }

    override func deactivateServer(_ sender: Any!) {
        Log.write("deactivateServer")
        BubbleStateMachine.shared.perteDeFocus()
        super.deactivateServer(sender)
    }
}

enum Log {
    static let path = "/tmp/bubulle.log"

    static func write(_ s: String) {
        let line = "[\(Date())] \(s)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
        FileHandle.standardError.write(data)
    }
}
