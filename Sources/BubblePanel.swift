import AppKit

/// Clone visuel du HUD système — variante A retenue au ticket 05 : NSVisualEffectView
/// .hudWindow, rayon h*0.26, drapeau seul centré à h*0.58. Capsule 29x22 pt (ticket 01).
final class BubblePanel: NSPanel {
    private let flagView = NSImageView()

    /// Génération de la bulle courante. Sert à périmer la complétion d'un fondu de sortie
    /// supplanté : AppKit tire le completionHandler d'un groupe d'animation dès qu'une
    /// nouvelle animation remplace la propriété animée — donc `beginPose` pendant un fondu
    /// déclenche immédiatement le `orderOut` du fondu, sur la bulle qu'on vient de poser
    /// (ticket 16). La garde `animationEpoch` de la machine à états ne couvrait que la
    /// transition d'état, pas ce `orderOut`.
    private var generation = 0

    init() {
        let w: CGFloat = 29, h: CGFloat = 22
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .statusBar
        // .moveToActiveSpace (pas .canJoinAllSpaces, qui la fixerait partout en permanence) :
        // sans lui, un NSPanel reste épinglé au Space actif lors de son premier affichage et
        // devient invisible, sans erreur, dès qu'on le repose sur un autre Space.
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        alphaValue = 0

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = h * 0.26
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        // Drapeau pleine capsule, 3 pt de marge sur chaque bord. Le cadre est calé sur le
        // ratio réel des SVG (30x20 = 3:2), pas sur la boîte de padding brute, pour que la
        // bordure ci-dessous colle au drapeau au lieu de flotter dans une marge verticale.
        let padding: CGFloat = 3
        let flagAspect: CGFloat = 30.0 / 20.0
        let maxW = w - 2 * padding, maxH = h - 2 * padding
        let flagW = min(maxW, maxH * flagAspect)
        let flagH = flagW / flagAspect
        flagView.imageScaling = .scaleProportionallyUpOrDown
        flagView.frame = NSRect(x: (w - flagW) / 2, y: (h - flagH) / 2, width: flagW, height: flagH)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        content.addSubview(effect)
        content.addSubview(flagView)
        contentView = content
    }

    func setFlagImage(_ image: NSImage) {
        flagView.image = image
    }

    /// Pose et fait entrer la bulle. `fromAlpha` != 0 quand on annule un fondu de sortie en
    /// cours (ticket 08, transition Sortie -> repose depuis l'alpha courant).
    func beginPose(fromAlpha: CGFloat, duration: TimeInterval) {
        generation += 1   // périme un fondu de sortie en vol (voir `generation`)
        alphaValue = fromAlpha
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            animator().alphaValue = 1
        }
    }

    func beginFadeOut(duration: TimeInterval, completion: @escaping () -> Void) {
        generation += 1
        let gen = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            guard gen == self.generation else { return }   // fondu supplanté : la bulle à l'écran n'est plus la sienne
            self.orderOut(nil)
            completion()
        })
    }

    /// Disparition nette, sans fondu — amendement du ticket 13 : le drapeau posé est
    /// connu-faux (bascule vers une source muette), un fondu le laisserait recouvrir le HUD
    /// système juste.
    func vanishImmediately() {
        generation += 1
        alphaValue = 0
        orderOut(nil)
    }
}
