import Cocoa
import Carbon

let want = ["com.apple.keylayout.Czech", "com.apple.keylayout.German", "com.apple.keylayout.Arabic", "com.apple.keylayout.US"]
let list = TISCreateInputSourceList(nil, true)!.takeRetainedValue() as! [TISInputSource]
for s in list {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { continue }
    let id = Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    guard want.contains(id) else { continue }
    guard let ip = TISGetInputSourceProperty(s, kTISPropertyIconRef) else { print("\(id): pas d'IconRef"); continue }
    let ref = OpaquePointer(ip)
    let img = NSImage(iconRef: unsafeBitCast(ref, to: IconRef.self))
    let out = "/tmp/icon-\(id.replacingOccurrences(of: ".", with: "_")).png"
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: out))
        print("\(id): \(img.size) -> \(out)")
    } else { print("\(id): non rendu") }
}
