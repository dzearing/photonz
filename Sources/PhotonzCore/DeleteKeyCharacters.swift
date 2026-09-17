import Foundation

/// What the keys that mean "take this away" really type.
///
/// This is here because the obvious answer is wrong. SwiftUI's own
/// `KeyEquivalent.delete` holds U+0008, the backspace control character, while
/// pressing ⌫ on a Mac keyboard delivers U+007F. The two never meet, so a view
/// matching `press.key` against `.delete` never sees a real press, and a menu
/// item given `.keyboardShortcut(.delete)` registers a chord no keyboard can
/// type. Both were measured on 2026-09-17: `onKeyPress` in the video editor
/// reported `key=U+007F isDelete=false` for a real ⌫, and an `NSMenu` carrying
/// U+0008 answered `performKeyEquivalent` with false for the same press while
/// an identical menu carrying U+007F ran its item, with and without ⌘ or ⌥.
///
/// So anything in the app that answers to a delete key compares against these
/// characters rather than against `KeyEquivalent.delete`.
public enum DeleteKeyCharacters {

    /// ⌫, the key above Return, as a Mac keyboard reports it.
    public static let backwards: Character = "\u{7F}"

    /// ⌦, forward delete, which arrives in the function-key block.
    public static let forwards: Character = "\u{F728}"

    /// The backspace control character SwiftUI calls `.delete`. Nothing on a
    /// Mac keyboard sends it, but a press routed through something that
    /// normalises to it still means the same key, so it is accepted rather
    /// than left as a gap somebody has to rediscover.
    public static let backspaceControl: Character = "\u{8}"

    /// Whether a pressed character is one of the delete keys.
    public static func means(deleteKey character: Character) -> Bool {
        character == backwards || character == forwards || character == backspaceControl
    }
}
