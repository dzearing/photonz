import Foundation

/// The rules for opening a piece of text for typing — a text block on the
/// canvas, a label inside a button, an arrow's caption. Every field that opens
/// over the picture reads from here, so they cannot drift from one another.
///
/// The idea in one line: **opening words offers them ready to be replaced.**
/// Words you already have are held up highlighted, so the first thing typed
/// takes their place, which is what double clicking a label does in every
/// other app. Getting the caret instead is how a new label ended up welded to
/// the old one ("ButtonSave all the changes", reported 2026-09-04).
///
/// This is only about the moment the field OPENS. Once it is open the field
/// behaves like any other: clicking inside the words puts the caret where you
/// clicked, and the highlight goes away.
public enum TextEntry {

    /// A stretch of a field's contents, measured the way the field measures
    /// it: in UTF-16 units, so an emoji or an accent never leaves the
    /// highlight stopping half a character short.
    public struct Selection: Equatable, Sendable {
        public var location: Int
        public var length: Int

        public init(location: Int, length: Int) {
            self.location = location
            self.length = length
        }

        /// True when the whole of `string` is held up for replacement.
        public func selectsEverything(of string: String) -> Bool {
            location == 0 && length == string.utf16.count && length > 0
        }

        /// True when this selection covers something rather than being a bare
        /// caret. Handy where the string is not at hand.
        public var selectsEverything: Bool { location == 0 && length > 0 }
    }

    /// What is highlighted the moment a field opens over `string`: all of it,
    /// so typing replaces it. An empty field opens with a plain caret, since
    /// there is nothing to offer.
    public static func openingSelection(for string: String) -> Selection {
        Selection(location: 0, length: string.utf16.count)
    }
}
