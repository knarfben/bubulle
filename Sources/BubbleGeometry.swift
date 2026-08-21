import AppKit

/// Formule mesurée aux tickets 11 (cas nominal) et 14 (hors cas nominal).
/// caret / visible en CG (origine haut-gauche).
///
/// `visible` est le `visibleFrame` de l'écran qui contient le caret — pas son `frame`, et pas
/// l'union des écrans (#14) : un Dock posé à gauche déplace le clamp de 2,5 pt derrière lui,
/// et un caret sur l'écran secondaire bascule au bord bas de *son* écran, pas de l'union.
/// Le bord haut, lui, ne contraint jamais : la capsule se pose par-dessus la barre de menus.
func cadreGarde(caret: CGRect, visible: CGRect) -> CGRect {
    let W: CGFloat = 29, H: CGFloat = 22
    let ECART: CGFloat = 4.5   // écart constant caret <-> capsule
    let MARGE: CGFloat = 2.5   // marge minimale capsule <-> bord de la zone visible

    var x = (caret.minX + 0.6).rounded(.down) - W / 2   // centrée sur minX, arrondi seuil 0,4
    x = min(max(x, visible.minX + MARGE), visible.maxX - MARGE - W)

    let butee = visible.maxY - MARGE                     // butée basse : la capsule ne descend jamais plus bas
    var y = caret.maxY + ECART                           // sous le caret…
    if y + H > butee {
        y = min(caret.minY - ECART - H, butee - H)       // …ou bascule au-dessus, elle-même bornée
    }

    return CGRect(x: x, y: y, width: W, height: H)
}

/// Bascule AppKit (origine bas-gauche de l'écran principal) <-> CG (origine haut-gauche).
/// Involutive : les deux repères partagent le même point de référence, donc l'appliquer deux
/// fois restitue le rect d'origine — une seule fonction sert dans les deux sens.
func flipAppKitCG(_ rect: NSRect) -> CGRect {
    let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
    let primaryHeight = primaryScreen?.frame.height ?? rect.maxY
    return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}

func screenContaining(_ point: NSPoint) -> NSScreen {
    NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? NSScreen.screens[0]
}
