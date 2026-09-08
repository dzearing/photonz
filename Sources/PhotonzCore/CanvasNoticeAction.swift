import Foundation

/// The one thing a canvas notice may offer you to press.
///
/// The canvas notice (`CopyConfirmation`) is normally inert: it appears
/// unprompted, says its piece, and fades. That rule exists so nothing can turn
/// up under your pointer and take a click you meant for the canvas.
///
/// One case earns a narrow exception. When a key press is REFUSED and the app
/// already knows the single command that would let it through
/// (`RegionSliceRefusal.canBecomeAPicture` → `RasterizePrompt`), sending the
/// person off to find that command in a menu is three steps for an answer the
/// app has already worked out. So the refusal may carry its own way out.
///
/// Deliberately one case and not a framework: a notice carries at most ONE
/// action, it is always the way out of the refusal it is printed on, and it
/// never replaces a permanent home for the same command. The button is a
/// shortcut to the Layer menu row, never the only door to it.
public enum CanvasNoticeAction: Hashable, Sendable {
    /// Turn the layer the refusal was about into a picture, question and all
    /// (`RasterizePrompt`). Carries the layer id captured at the moment of the
    /// refusal: what is selected can change between the refusal and the press,
    /// and a button that bakes whatever happens to be picked NOW would destroy
    /// the wrong layer.
    case turnIntoPicture(layer: UUID)

    /// The layer this action would act on.
    public var layerID: UUID {
        switch self {
        case .turnIntoPicture(let id): return id
        }
    }

    /// What the button says. The same words as the menu row, minus its
    /// ellipsis: on a button three dots read as "more options", and the
    /// question that follows is one press away from either door anyway.
    public var label: String {
        switch self {
        case .turnIntoPicture:
            return RasterizePrompt.menuItem.replacingOccurrences(of: "\u{2026}", with: "")
        }
    }

    /// The key that does the same thing, shown on the button. The pointer is
    /// not the only way in, and this is where a person learns a key that keeps
    /// working long after the pill has gone.
    public var shortcutHint: String {
        switch self {
        case .turnIntoPicture: return "\u{21E7}\u{2318}R"
        }
    }
}
