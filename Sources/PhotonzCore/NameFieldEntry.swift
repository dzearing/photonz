import Foundation

/// The rules of a typed WORD field: a name, a label, a caption, a search. What
/// each key does, and in particular when the field is finished with the
/// keyboard.
///
/// The idea in one line, and it is the same one `NumberFieldEntry` states for
/// digits: **typing a name is a moment, not a mode.** A field that holds the
/// keyboard after you are done with it turns the next tool letter into a letter
/// of the name, and leaves clicking the picture as the only way out. So Return
/// lands the name and Escape puts it back, and both hand the keyboard to the
/// picture, where the tool keys and the nudge arrows live.
///
/// The one difference from a number: up and down do NOT step anything. There is
/// no next name, so the arrows stay caret movement the way they are in every
/// other text field on the Mac, and every key that is not Return or Escape
/// simply types.
///
/// What "puts it back" means is the field's own business and it is not always a
/// name: renaming puts the old name back, naming something new abandons the
/// making of it, and a search box empties itself. All three go back to how
/// things were before the typing started, and all three then let go, which is
/// the part this file is here to keep the same everywhere.
public enum NameFieldEntry {

    public enum Key: Equatable, Sendable {
        case `return`
        case escape
        /// Everything else, including the tool shortcut letters and the arrows.
        case other
    }

    public enum Action: Equatable, Sendable {
        /// Land the draft and let the keyboard go.
        case commitAndRelease
        /// Go back to how things were before the typing started, land nothing,
        /// and let the keyboard go.
        case revertAndRelease
        /// An ordinary keystroke the field editor should handle itself.
        case type
    }

    public static func action(for key: Key) -> Action {
        switch key {
        case .return: .commitAndRelease
        case .escape: .revertAndRelease
        case .other: .type
        }
    }

    /// Whether the draft in the field reaches the document.
    public static func lands(_ action: Action) -> Bool {
        action == .commitAndRelease
    }

    /// Whether the keyboard goes back to the picture after this action.
    public static func releasesKeyboard(_ action: Action) -> Bool {
        switch action {
        case .commitAndRelease, .revertAndRelease: true
        case .type: false
        }
    }

    /// The name a field would land, or nil when there is nothing to land. Blank
    /// is refused everywhere: a thing with no name at all cannot be pointed at
    /// in a list. Same trimming the component fields already used, so the two
    /// cannot drift.
    public static func landedName(_ draft: String) -> String? {
        ComponentNaming.normalized(draft)
    }
}
