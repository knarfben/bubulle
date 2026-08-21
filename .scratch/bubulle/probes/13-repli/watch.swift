import Foundation
import Carbon

func s(_ src: TISInputSource, _ k: CFString) -> String? {
    guard let p = TISGetInputSourceProperty(src, k) else { return nil }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}
func langs(_ src: TISInputSource) -> [String] {
    guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) else { return [] }
    return Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as! [String]
}
func report(_ tag: String) {
    guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { print("\(tag): nil"); return }
    let l = langs(src)
    print("\(tag) id=\(s(src, kTISPropertyInputSourceID) ?? "?") cat=\((s(src, kTISPropertyInputSourceCategory) ?? "?").replacingOccurrences(of: "TISCategory", with: "")) lang0=\(l.first ?? "(vide)") name=\(s(src, kTISPropertyLocalizedName) ?? "?")")
    fflush(stdout)
}
report("start")
CFNotificationCenterAddObserver(
    CFNotificationCenterGetDistributedCenter(), nil,
    { _, _, _, _, _ in report("notif") },
    kTISNotifySelectedKeyboardInputSourceChanged, nil, .deliverImmediately)
Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { _ in report("fin"); exit(0) }
RunLoop.main.run()
