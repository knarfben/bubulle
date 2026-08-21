import Foundation

// Échelle de résolution posée au ticket 13 : ID exact -> null explicite (source muette) ->
// langue primaire contre une table déduite de flags.json -> rien (source muette, journalisée).

private enum FlagResolution {
    case asset(String)
    case mute
}

enum FlagDecision {
    case show(assetPath: String)
    case silentMute
    case silentUnmapped
}

final class FlagTable {
    private var byID: [String: FlagResolution] = [:]
    private var byLanguage: [String: String] = [:]

    init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "flags", withExtension: "json") else {
            Log.write("flags.json introuvable dans le bundle")
            return
        }
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Log.write("flags.json illisible")
            return
        }
        for (id, raw) in obj {
            if raw is NSNull {
                byID[id] = .mute
            } else if let path = raw as? String {
                byID[id] = .asset(path)
            }
        }
        buildLanguageTable()
    }

    // L'ordre des clés JSON n'est pas déterministe (mesuré au ticket 13) : la table doit être
    // construite sans dépendre de cet ordre. Une langue portée par deux drapeaux différents
    // sort de la table plutôt que de trancher arbitrairement.
    private func buildLanguageTable() {
        let languages = allKeyboardSourceLanguages()
        var pathsByLanguage: [String: Set<String>] = [:]
        for (id, resolution) in byID {
            guard case .asset(let path) = resolution else { continue }
            guard let lang = languages[id], !lang.isEmpty else { continue }
            pathsByLanguage[lang, default: []].insert(path)
        }
        for (lang, paths) in pathsByLanguage where paths.count == 1 {
            byLanguage[lang] = paths.first!
        }
    }

    func decision(forSourceID id: String, primaryLanguage lang: String?) -> FlagDecision {
        if let resolution = byID[id] {
            switch resolution {
            case .asset(let path): return .show(assetPath: path)
            case .mute: return .silentMute
            }
        }
        if let lang = lang, let path = byLanguage[lang] {
            return .show(assetPath: path)
        }
        return .silentUnmapped
    }
}
