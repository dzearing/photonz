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
/// The second case widens the exception by one step and keeps every part of
/// its shape. Separate into Layers raises a pill saying what came out of a
/// screenshot, and the thing a person wants next — the words in those labels —
/// was a menu row under a menu row that nothing pointed at
/// (`docs/design/separate-reads-the-words.md`). So the pill offers it, once,
/// on the result they are already looking at.
///
/// Deliberately two cases and not a framework: a notice carries at most ONE
/// action, it is always the obvious next move on the thing the notice is
/// about, and it never replaces a permanent home for the same command. The
/// button is a shortcut to the Layer menu row, never the only door to it.
public enum CanvasNoticeAction: Hashable, Sendable {
    /// Turn the layer the refusal was about into a picture, question and all
    /// (`RasterizePrompt`). Carries the layer id captured at the moment of the
    /// refusal: what is selected can change between the refusal and the press,
    /// and a button that bakes whatever happens to be picked NOW would destroy
    /// the wrong layer.
    case turnIntoPicture(layer: UUID)

    /// Read the words in every run a separation just made
    /// (`next-read-every-label`). Carries the runs captured at the moment the
    /// separation landed, for the same reason the case above carries its
    /// layer: selection changes the instant somebody clicks the canvas, and a
    /// button that read whatever happens to be picked NOW would rewrite the
    /// wrong labels.
    case readTheWords(runs: [UUID])

    /// The layers this action would act on.
    public var layerIDs: [UUID] {
        switch self {
        case .turnIntoPicture(let id): return [id]
        case .readTheWords(let runs): return runs
        }
    }

    /// What the button says. The same words as the menu row, minus its
    /// ellipsis: on a button three dots read as "more options", and the
    /// question that follows is one press away from either door anyway.
    public var label: String {
        switch self {
        case .turnIntoPicture:
            return RasterizePrompt.menuItem.replacingOccurrences(of: "\u{2026}", with: "")
        // NOT the menu row's own name. "Turn into Text" on a row means that
        // row; on a pill that has just counted forty pieces it would be a
        // promise about which forty is anybody's guess. This says what the
        // press gets you, in the words the study used for it.
        case .readTheWords: return "Read the Words"
        }
    }

    /// The key that does the same thing, shown on the button. The pointer is
    /// not the only way in, and this is where a person learns a key that keeps
    /// working long after the pill has gone.
    ///
    /// Nil where the command has no key. Showing one that does not exist
    /// teaches something false, and Turn into Text is deliberately unbound:
    /// nothing in Photoshop's set is free for it and it is not a command
    /// anybody runs in a stream.
    public var shortcutHint: String? {
        switch self {
        case .turnIntoPicture: return "\u{21E7}\u{2318}R"
        case .readTheWords: return nil
        }
    }
}
