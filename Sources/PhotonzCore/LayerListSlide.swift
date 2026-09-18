import Foundation

/// What the layers list's slide is keyed to.
///
/// Rows slide and fade when the LIST changes shape: a layer added, deleted,
/// duplicated, reordered, a group twisted open. Those are things somebody did
/// to the document, and seeing them move is how you keep your place.
///
/// A search is not one of those. Typing into the find field does not change
/// the list, it changes how much of it you are being shown, and a query is
/// retyped from scratch on every keystroke. Keyed to the rows on screen, one
/// letter over a separated screenshot asked a hundred and seventy rows to
/// slide out and forty to slide in, which cost about a third of a second of
/// main thread per letter and made the field stutter in exactly the place it
/// exists for (`typing-in-the-find-field-does-not-freeze-a-long`). Keyed to
/// the whole list instead, narrowing a search changes nothing the animation
/// watches, so results land the instant you type, the way search fields on the
/// Mac do.
public enum LayerListSlide {

    /// The value the list's add/remove animation watches.
    ///
    /// `shown` is what the list is drawing right now. `whole` is the list with
    /// nothing typed, and it is only asked for while a search IS showing:
    /// with an empty field the two are the same list, and working the second
    /// one out would be a walk of the tree per redraw for nothing.
    public static func key(shown: [LayerPanelRow],
                           whole: @autoclosure () -> [LayerPanelRow],
                           isSearching: Bool) -> [LayerPanelRow] {
        isSearching ? whole() : shown
    }
}
