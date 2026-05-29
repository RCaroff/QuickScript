import Cocoa

/// NSView avec coordonnées top-down (pratique pour empiler des champs sans
/// inverser les y). Utilisée par `ParamInputDialog` et tout dialog qui
/// construit son layout manuellement.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
