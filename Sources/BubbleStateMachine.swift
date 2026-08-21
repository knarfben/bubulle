import AppKit
import CoreGraphics
import Carbon.HIToolbox

// Machine à états arrêtée au ticket 08 (glossaire complet dans CONTEXT.md) :
//
//   Repos --notif TIS--> Placement(langue)
//   Repos --activateServer:--> Placement(focus)
//   Placement --rect non nul--> pose --> Recouvrement (langue) / Affichée (focus)
//   Placement --rect nul--> repoll unique 80ms --> Repos si toujours nul
//   Recouvrement --frappe/clic/scroll--> ignorés
//   Recouvrement --deactivateServer:--> Sortie
//   Recouvrement --notif TIS--> re-pose sur place, plancher réarmé
//   Recouvrement --activateServer: (autre champ)--> Sortie puis Placement(focus)
//   Recouvrement --t=1.5s--> Affichée
//   Affichée --acte--> Sortie
//   Affichée --deactivateServer:--> Sortie
//   Affichée --notif TIS--> re-pose, plancher 1.5s --> Recouvrement
//   Sortie --notif TIS / activateServer: pendant le fondu--> annule le fondu, repose depuis l'alpha courant
//   Sortie --fondu terminé--> Repos
//
// Ajout du ticket 17, le mode invite. Un guet tourne tant qu'un terminal a le focus et pose une
// bulle quand l'invite revient. Il ne passe pas par activateServer:, qui n'a pas lieu — le focus
// n'a pas changé :
//
//   Repos --invite revenue--> Placement(invite)
//   Recouvrement --invite revenue--> ignorée (le plancher est la portée de l'indiscernabilité :
//                                    reposer ailleurs découvrirait les deux lettres du HUD)
//   Affichée --invite revenue--> Sortie puis Placement(invite)
//   Sortie --invite revenue--> annule le fondu, repose depuis l'alpha courant
//
// Amendement du ticket 13 : une bulle vivante qui bascule vers une source muette disparaît
// net, sans fondu, plutôt que de re-poser ou de fondre.
//
// Limite connue (ticket 12, mesurée) : le document de démarrage restauré par Sublime Text
// rejoue plusieurs clics synthétiques (positions différentes, pas de motif humain plausible)
// dans la seconde qui suit l'ouverture, probablement pour restaurer sélection/scroll/focus de
// sidebar. Ces événements sont indiscernables d'un vrai clic pour CGEventSourceCounterForEvent-
// Type (ticket 04 : c'est précisément ce qui le rend fiable sans permission, y compris sous
// secure input), donc la bulle se ferme d'elle-même avant que l'utilisateur ne la voie. N'af-
// fecte que ce document restauré au lancement — un nouveau document (⌘N) ou un fichier ouvert
// normalement fonctionnent. Pas de contournement : une fenêtre de grâce casserait le
// « Affichée --acte--> Sortie » voulu partout ailleurs.

private let kEntreeDuree: TimeInterval = 0.25
private let kSortieDuree: TimeInterval = 0.40
private let kPlancherDuree: TimeInterval = 1.5
private let kRepollDelai: TimeInterval = 0.080
private let kRepollMaxAttempts = 5   // fenêtres neuves (Sublime au lancement) : layout parfois > 80ms
private let kCompteursIntervalle: TimeInterval = 1.0 / 60.0

// Guet du ticket 17. 60 Hz et pas 10 : sur une commande rapide (`ls`), la frappe d'Entrée, le
// passage en colonne 0 et l'écriture de l'invite tiennent dans 50 ms — à 10 Hz ils tombent dans
// le même échantillon et l'ancre du déplacement serait celle d'avant la frappe. Mesuré au 17.
private let kGuetIntervalle: TimeInterval = 1.0 / 60.0
private let kGuetImmobilisation: TimeInterval = 0.15

// Liste blanche du mode invite. Volontairement en dur et réduite à Ghostty : iTerm2 rendait
// `(0,0,0,0)` jusqu'à une vraie frappe (recherche 03) et n'a pas été remesuré, donc le guet n'y
// verrait peut-être jamais rien. Élargir demande une mesure, pas une ligne de plus.
private let kTerminaux: Set<String> = ["com.mitchellh.ghostty"]

enum BubbleMode {
    case langue, focus, invite
}

private enum Etat {
    case repos
    case placement(mode: BubbleMode)
    case recouvrement
    case affichee
    case sortie
}

private struct ActeCounters: Equatable {
    let key: UInt32
    let mouseDown: UInt32
    let scroll: UInt32

    static func now() -> ActeCounters {
        func c(_ t: CGEventType) -> UInt32 {
            CGEventSource.counterForEventType(.combinedSessionState, eventType: t)
        }
        let mouse = c(.leftMouseDown) + c(.rightMouseDown) + c(.otherMouseDown)
        return ActeCounters(key: c(.keyDown), mouseDown: mouse, scroll: c(.scrollWheel))
    }
}

final class BubbleStateMachine {
    static let shared = BubbleStateMachine()

    private let panel = BubblePanel()
    private let flags = FlagTable()

    private var etat: Etat = .repos
    private var currentClient: BubulleTextInput?

    private var compteursTimer: Timer?
    private var plancherTimer: Timer?
    private var actesDepart: ActeCounters?

    // Gardes anti-course : un événement plus récent invalide la complétion d'un événement
    // périmé (repoll de rect en vol, fondu de sortie en vol).
    private var placementToken = 0
    private var animationEpoch = 0

    private var loggedUnmappedIDs = Set<String>()

    // Guet du mode invite (ticket 17). Tourne tant qu'un terminal de kTerminaux a le focus.
    private var guetTimer: Timer?
    private var guetArme = false                    // un acte arme, la pose désarme : une bulle par commande
    private var guetRect: NSRect?                   // dernier rect observé
    private var guetImmobileDepuis = Date.distantPast
    private var guetAncre: NSRect?                  // où était le caret au dernier acte
    private var guetActes: ActeCounters?
    private var guetMargeGauche = CGFloat.greatestFiniteMagnitude   // plus petit x vu depuis la prise de focus

    private init() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                Unmanaged<BubbleStateMachine>.fromOpaque(observer).takeUnretainedValue().changementDeLangue()
            },
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Entrées (appelées depuis BubulleController)

    func priseDeFocus(client: BubulleTextInput) {
        currentClient = client
        if kTerminaux.contains(client.bundleIdentifier() ?? "") { demarrerGuet() } else { arreterGuet() }
        switch etat {
        case .repos:
            beginPlacement(mode: .focus)
        case .placement:
            placementToken += 1
            beginPlacement(mode: .focus)
        case .recouvrement, .affichee:
            exitThenPlacement(mode: .focus)
        case .sortie:
            cancelFadeAndRepose(mode: .focus)
        }
    }

    func perteDeFocus() {
        arreterGuet()
        currentClient = nil
        switch etat {
        case .recouvrement, .affichee:
            beginSortie()
        case .placement:
            placementToken += 1
            etat = .repos
        default:
            break
        }
    }

    private func changementDeLangue() {
        switch etat {
        case .repos:
            beginPlacement(mode: .langue)
        case .placement:
            placementToken += 1
            beginPlacement(mode: .langue)
        case .recouvrement, .affichee:
            represerSurPlace()
        case .sortie:
            cancelFadeAndRepose(mode: .langue)
        }
    }

    // MARK: - Placement

    private func beginPlacement(mode: BubbleMode, fadeFromCurrentAlpha: Bool = false) {
        placementToken += 1
        let token = placementToken
        etat = .placement(mode: mode)

        guard let source = currentInputSource() else {
            Log.write("placement: aucune source d'entrée courante")
            etat = .repos
            return
        }

        switch flags.decision(forSourceID: source.id, primaryLanguage: source.primaryLanguage) {
        case .silentMute:
            etat = .repos
        case .silentUnmapped:
            logUnmappedOnce(source)
            etat = .repos
        case .show(let assetPath):
            guard let image = loadFlagImage(assetPath) else {
                Log.write("asset introuvable/illisible: \(assetPath) (id=\(source.id))")
                etat = .repos
                return
            }
            resolveRectAndPose(mode: mode, image: image, token: token, fadeFromCurrentAlpha: fadeFromCurrentAlpha, attempt: 0)
        }
    }

    private func resolveRectAndPose(mode: BubbleMode, image: NSImage, token: Int, fadeFromCurrentAlpha: Bool, attempt: Int) {
        guard token == placementToken else { return }   // événement périmé, supplanté depuis
        guard let rect = queryCaretRect() else {
            guard attempt + 1 < kRepollMaxAttempts else {
                etat = .repos
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + kRepollDelai) { [weak self] in
                self?.resolveRectAndPose(mode: mode, image: image, token: token, fadeFromCurrentAlpha: fadeFromCurrentAlpha, attempt: attempt + 1)
            }
            return
        }
        pose(mode: mode, caretRect: rect, image: image, fadeFromCurrentAlpha: fadeFromCurrentAlpha)
    }

    private func pose(mode: BubbleMode, caretRect: NSRect, image: NSImage, fadeFromCurrentAlpha: Bool) {
        let screen = screenContaining(caretRect.origin)
        let caretCG = flipAppKitCG(caretRect)
        let visibleCG = flipAppKitCG(screen.visibleFrame)
        let cadreCG = cadreGarde(caret: caretCG, visible: visibleCG)
        let cadreAppKit = flipAppKitCG(cadreCG)

        panel.setFlagImage(image)
        panel.setFrame(cadreAppKit, display: false)

        actesDepart = ActeCounters.now()
        startCompteursTimer()

        animationEpoch += 1
        let startAlpha = fadeFromCurrentAlpha ? panel.alphaValue : 0
        panel.beginPose(fromAlpha: startAlpha, duration: kEntreeDuree)

        switch mode {
        case .langue:
            etat = .recouvrement
            armerPlancher()
        case .focus, .invite:
            etat = .affichee
        }
    }

    private func queryCaretRect() -> NSRect? {
        guard let client = currentClient else { return nil }
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return rect == .zero ? nil : rect   // rect nul = pas de champ texte (ticket 02)
    }

    // MARK: - Re-pose sur place (bulle déjà vivante, changement de langue)

    private func represerSurPlace() {
        guard let source = currentInputSource() else { return }
        switch flags.decision(forSourceID: source.id, primaryLanguage: source.primaryLanguage) {
        case .silentMute:
            vanirNet()
        case .silentUnmapped:
            logUnmappedOnce(source)
            vanirNet()
        case .show(let assetPath):
            guard let image = loadFlagImage(assetPath) else {
                Log.write("asset introuvable/illisible: \(assetPath) (id=\(source.id))")
                vanirNet()
                return
            }
            panel.setFlagImage(image)
            actesDepart = ActeCounters.now()
            armerPlancher()
            etat = .recouvrement
        }
    }

    private func vanirNet() {
        stopTimers()
        animationEpoch += 1
        panel.vanishImmediately()
        etat = .repos
    }

    // MARK: - Sortie

    private func exitThenPlacement(mode: BubbleMode) {
        beginSortie { [weak self] in
            self?.beginPlacement(mode: mode)
        }
    }

    private func beginSortie(completion: (() -> Void)? = nil) {
        stopTimers()
        etat = .sortie
        animationEpoch += 1
        let epoch = animationEpoch
        panel.beginFadeOut(duration: kSortieDuree) { [weak self] in
            guard let self = self, epoch == self.animationEpoch else { return }
            self.etat = .repos
            completion?()
        }
    }

    private func cancelFadeAndRepose(mode: BubbleMode) {
        animationEpoch += 1   // périme la complétion du fondu en cours
        beginPlacement(mode: mode, fadeFromCurrentAlpha: true)
    }

    // MARK: - Compteurs d'actes / plancher

    private func armerPlancher() {
        plancherTimer?.invalidate()
        let timer = Timer(timeInterval: kPlancherDuree, repeats: false) { [weak self] _ in
            self?.plancherEcoule()
        }
        plancherTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func plancherEcoule() {
        guard case .recouvrement = etat else { return }
        etat = .affichee
    }

    private func startCompteursTimer() {
        compteursTimer?.invalidate()
        let timer = Timer(timeInterval: kCompteursIntervalle, repeats: true) { [weak self] _ in
            self?.tickCompteurs()
        }
        compteursTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tickCompteurs() {
        guard case .affichee = etat else { return }   // en Recouvrement les actes sont ignorés
        guard let depart = actesDepart, ActeCounters.now() != depart else { return }
        beginSortie()
    }

    private func stopTimers() {
        plancherTimer?.invalidate(); plancherTimer = nil
        compteursTimer?.invalidate(); compteursTimer = nil
    }

    // MARK: - Guet du mode invite (ticket 17)

    /// Le guet cherche l'**invite** au sens de CONTEXT.md : un terminal prêt à recevoir la
    /// commande suivante. Ce n'est ni la frappe d'Entrée (la commande peut durer : `sleep 10`
    /// rend la main 10 s plus tard) ni une position connue d'avance — mesuré au ticket 17, un
    /// shell pose son caret *après* son invite, un TUI le ramène au *début* de sa boîte vidée.
    /// Les deux se déplacent en sens opposés ; leur seul invariant est que le caret s'y immobilise.
    ///
    /// D'où la règle : on pose quand le caret est immobile depuis kGuetImmobilisation **à une
    /// position que la frappe n'explique pas** — un autre ligne, ou un écart horizontal de plus
    /// d'un caractère par rapport à là où il était au dernier acte. Taper une lettre avance le
    /// caret d'une colonne et ne déclenche donc rien, même si on marque une pause juste après.
    private func demarrerGuet() {
        guard guetTimer == nil else { return }
        guetArme = false
        guetRect = nil
        guetAncre = nil
        guetActes = nil
        guetMargeGauche = .greatestFiniteMagnitude
        guetImmobileDepuis = .distantPast
        let t = Timer(timeInterval: kGuetIntervalle, repeats: true) { [weak self] _ in
            self?.tickGuet()
        }
        guetTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func arreterGuet() {
        guetTimer?.invalidate()
        guetTimer = nil
    }

    private func tickGuet() {
        let actes = ActeCounters.now()
        let rect = queryCaretRect()
        let maintenant = Date()

        // La marge gauche s'apprend : un shell y parque son curseur à chaque commande, donc elle
        // est connue dès la première. Voir estUneInvite(ancre:immobile:).
        if let r = rect { guetMargeGauche = min(guetMargeGauche, r.origin.x) }

        // Un acte arme le guet et redéfinit l'ancre. `guetRect` n'a pas encore été mis à jour :
        // c'est donc la position d'AVANT la frappe, ce qu'on veut — l'app redessine parfois dans
        // le même tick que l'acte, parfois au suivant (mesuré au 17), et l'ancre doit précéder
        // les deux.
        if let precedent = guetActes, actes != precedent {
            guetArme = true
            guetAncre = guetRect ?? rect
        }
        guetActes = actes

        if rect != guetRect {
            guetRect = rect
            guetImmobileDepuis = maintenant
            return
        }

        guard guetArme,
              let rect = rect,
              let ancre = guetAncre,
              maintenant.timeIntervalSince(guetImmobileDepuis) >= kGuetImmobilisation,
              estUneInvite(ancre: ancre, immobile: rect)
        else { return }

        guetArme = false   // une pose par armement : rien pendant un `tail -f` qui défile
        inviteRevenue()
    }

    /// Le caret immobile est-il à une **invite** au sens de CONTEXT.md, ou seulement là où l'app
    /// l'a parqué en attendant ? Mesuré au ticket 17 : après Entrée, un shell a DEUX positions
    /// immobiles successives — la colonne 0 pendant que la commande tourne (jusqu'à plusieurs
    /// secondes), puis la position d'après l'invite. Un TUI n'en a qu'une. Prendre la première
    /// poserait la bulle sur la zone de sortie.
    ///
    /// Les deux cas se séparent par la ligne :
    ///
    /// - **Même ligne que l'ancre** — la boîte de saisie d'un TUI s'est vidée sur place et a
    ///   ramené le caret à son début. C'est déjà l'état prêt (mesuré : 132,5 -> 24,5, y inchangé).
    /// - **Ligne différente** — un shell est passé à la ligne suivante. Tant que le caret est sur
    ///   la marge gauche, rien n'a encore été écrit sur cette ligne : c'est le parcage, on attend
    ///   (mesuré : 6,5 pendant 2 s, puis 222,5).
    ///
    /// Le seuil est la hauteur du caret : en chasse fixe un caractère fait à peu près la moitié
    /// de la hauteur de ligne, donc « plus d'une hauteur » vaut « plus de deux caractères », et ça
    /// se met à l'échelle avec la taille de police sans la connaître. C'est aussi ce qui fait
    /// qu'une frappe ordinaire — un caractère — ne déclenche jamais rien.
    ///
    /// Deux angles morts assumés, tous deux du côté « pas de bulle » et jamais « bulle au mauvais
    /// endroit » : la toute première commande d'une fenêtre si elle est assez rapide pour que la
    /// colonne 0 ne soit jamais échantillonnée (la marge n'est pas encore connue), et un prompt
    /// multi-ligne validé dans un TUI (la boîte se replie, donc ligne différente, et son bord
    /// gauche EST la marge).
    private func estUneInvite(ancre: NSRect, immobile: NSRect) -> Bool {
        let seuil = immobile.height
        if immobile.origin.y == ancre.origin.y {
            return abs(immobile.origin.x - ancre.origin.x) > seuil
        }
        return immobile.origin.x > guetMargeGauche + seuil
    }

    private func inviteRevenue() {
        switch etat {
        case .repos:
            beginPlacement(mode: .invite)
        case .placement:
            placementToken += 1
            beginPlacement(mode: .invite)
        case .recouvrement:
            break   // plancher : reposer ailleurs découvrirait les deux lettres du HUD système
        case .affichee:
            exitThenPlacement(mode: .invite)
        case .sortie:
            cancelFadeAndRepose(mode: .invite)
        }
    }

    // MARK: - Assets / log

    private func loadFlagImage(_ relativePath: String) -> NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(relativePath) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func logUnmappedOnce(_ source: CurrentSource) {
        guard !loggedUnmappedIDs.contains(source.id) else { return }
        loggedUnmappedIDs.insert(source.id)
        Log.write("source muette (non mappée) id=\(source.id) nom=\(source.localizedName ?? "?") langue=\(source.primaryLanguage ?? "(vide)")")
    }
}
