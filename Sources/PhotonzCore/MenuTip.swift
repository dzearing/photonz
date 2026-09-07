import Foundation

/// What a menu says when someone hovers it.
///
/// A menu in the dock already carries its name in the caption above it, so the
/// tip normally only has to say what the row reaches: "the font of all 3
/// selected layers". But a box held to one width can only show so many letters,
/// and a name shortened to "Bodoni 72 Smallc..." is a name nobody can read. When
/// that happens the tip leads with the value IN FULL, because that is the thing
/// the pointer went looking for, and says what it is afterwards.
public enum MenuTip {
    /// `subject` is the sentence the menu always says. `value` is what the box
    /// is showing right now, or nil when the picked layers differ and it is
    /// showing the word Mixed. `isClipped` is whether the box had to shorten it.
    public static func text(about subject: String, showing value: String?, isClipped: Bool) -> String {
        guard isClipped, let value, !value.isEmpty else { return subject }
        return "\(value), \(uncapitalized(subject))"
    }

    /// The subject as the second half of a sentence. Only the first letter
    /// moves down: a subject naming something in capitals keeps them.
    private static func uncapitalized(_ subject: String) -> String {
        guard let first = subject.first else { return subject }
        return first.lowercased() + subject.dropFirst()
    }
}
