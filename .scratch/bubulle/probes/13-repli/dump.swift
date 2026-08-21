import Foundation
import Carbon

func str(_ src: TISInputSource, _ key: CFString) -> String? {
    guard let p = TISGetInputSourceProperty(src, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}
func bool(_ src: TISInputSource, _ key: CFString) -> Bool {
    guard let p = TISGetInputSourceProperty(src, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
}
func langs(_ src: TISInputSource) -> [String] {
    guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) else { return [] }
    return (Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as! [String])
}
func iconURL(_ src: TISInputSource) -> String? {
    guard let p = TISGetInputSourceProperty(src, kTISPropertyIconImageURL) else { return nil }
    return (Unmanaged<CFURL>.fromOpaque(p).takeUnretainedValue() as URL).path
}
func hasIconRef(_ src: TISInputSource) -> Bool {
    TISGetInputSourceProperty(src, kTISPropertyIconRef) != nil
}

let list = TISCreateInputSourceList(nil, true)!.takeRetainedValue() as! [TISInputSource]
print("id\tname\tcat\tselectable\tenabled\tlangs\ticonRef\ticonURL")
for s in list {
    guard let cat = str(s, kTISPropertyInputSourceCategory) else { continue }
    guard cat == (kTISCategoryKeyboardInputSource as String) else { continue }
    let id = str(s, kTISPropertyInputSourceID) ?? "?"
    let name = str(s, kTISPropertyLocalizedName) ?? "?"
    let sel = bool(s, kTISPropertyInputSourceIsSelectCapable)
    let en = bool(s, kTISPropertyInputSourceIsEnabled)
    print("\(id)\t\(name)\t\(cat.replacingOccurrences(of: "TISCategory", with: ""))\t\(sel)\t\(en)\t\(langs(s).joined(separator: ","))\t\(hasIconRef(s))\t\(iconURL(s) ?? "-")")
}
