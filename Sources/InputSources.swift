import Carbon.HIToolbox

// Lecture TIS. TISCopyCurrentKeyboardInputSource() n'est PAS caché par process — contrairement
// à TISCreateInputSourceList (cf. ticket 09) — et sert déjà la source à jour quand la notif
// arrive (mesuré au ticket 13). C'est le seul appel sur le chemin chaud.

private func sourceStringProperty(_ src: TISInputSource, _ key: CFString) -> String? {
    guard let p = TISGetInputSourceProperty(src, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

private func sourceLanguages(_ src: TISInputSource) -> [String] {
    guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) else { return [] }
    return (Unmanaged<CFArray>.fromOpaque(p).takeUnretainedValue() as! [String])
}

struct CurrentSource {
    let id: String
    let localizedName: String?
    let primaryLanguage: String?
}

func currentInputSource() -> CurrentSource? {
    guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    guard let id = sourceStringProperty(src, kTISPropertyInputSourceID) else { return nil }
    return CurrentSource(
        id: id,
        localizedName: sourceStringProperty(src, kTISPropertyLocalizedName),
        primaryLanguage: sourceLanguages(src).first
    )
}

/// Appelé une seule fois au démarrage pour déduire la table langue→drapeau — pas sur le
/// chemin chaud, donc le cache par process de TISCreateInputSourceList (ticket 09) n'a pas
/// d'incidence : on ne lui demande jamais de voir un changement, seulement la liste au repos.
func allKeyboardSourceLanguages() -> [String: String] {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
        return [:]
    }
    var result: [String: String] = [:]
    for s in list {
        guard let id = sourceStringProperty(s, kTISPropertyInputSourceID) else { continue }
        result[id] = sourceLanguages(s).first ?? ""
    }
    return result
}
