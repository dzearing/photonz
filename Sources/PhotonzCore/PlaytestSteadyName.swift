import Foundation

/// The name a scripted walk calls a panel row by when it wants that name to
/// outlive the words on the row.
///
/// A walk says `in: "Border"` because Border is what the row says, and that is
/// the honest way to write one: it reads like the thing a person would do. It
/// is also why renaming a row breaks walks by the dozen. In the last day alone
/// the queue carried "Thirteen scripted walks still look for an Outline row
/// that is now a Border", "Five stale walks still ask for the outline that
/// moved into Effects" and "Four walks cannot find the Shadow entry in the
/// Effects list": five tasks, one cause, and the bill fell on whatever feature
/// was in focus, because building panel UI means editing that copy.
///
/// So a row carries a second name beside its words — its STEADY name — and a
/// walk may use either. `in: "Border"` still works and still reads well.
/// `in: "@border"` reaches the same row and keeps reaching it after somebody
/// changes what it says.
///
/// Two rules make this safe rather than merely convenient:
///
/// - **A steady name is never typed next to the copy.** It comes off the model
///   (`EffectKind.rawValue`, `LayerPartRow.id`), so an edit to what the row
///   SAYS physically cannot reach what it IS. A scheme where a renamer is
///   asked to leave an old word behind is a scheme that depends on the same
///   discipline that just failed.
/// - **The two namespaces never touch.** A plain word only ever matches words
///   and a marked name only ever matches steady names. Let them mix and a row
///   whose word is Border would fight a different row whose steady name is
///   border, and which one a walk got would be whichever the panel built
///   first. It also means a row that has genuinely GONE has no steady name
///   anywhere in the panel, so the walk fails loudly instead of drifting onto
///   a neighbour, which is what an old-words-still-work alias scheme would do.
public enum PlaytestSteadyName {

    /// What a walk puts in front of a name to say it means the steady one.
    public static let mark = "@"

    /// Whether a name a walk wrote is asking for a steady name. The mark on
    /// its own names nothing, so it stays an ordinary word.
    public static func isSteady(_ written: String) -> Bool {
        written.count > mark.count && written.hasPrefix(mark)
    }

    /// A steady name written the way a walk would write it, for the panel
    /// listing and for the "no control called that" failures. The first thing
    /// an author sees when a walk cannot find a row is the list of what IS
    /// there, so the durable name has to be in that list, spelled the way it
    /// gets pasted into a step.
    public static func written(_ steady: String) -> String { mark + steady }

    /// Whether a name a walk wrote reaches a row carrying these steady names.
    /// False for anything unmarked, whatever it says.
    public static func matches(_ written: String, steady: [String]) -> Bool {
        guard isSteady(written) else { return false }
        let wanted = String(written.dropFirst(mark.count))
        return steady.contains { $0.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    /// The steady names of one entry in a list that can hold several of a kind:
    /// an Effects list with two borders in it, an Appearance list with two of a
    /// countable part.
    ///
    /// The first of a kind answers to the bare kind as well as to its number,
    /// so an ordinary walk writes `@border` and keeps working on the day a
    /// second border arrives above nothing. The second answers to its number
    /// only, because `@border` has to keep meaning one row and the top of the
    /// list is the one a walk that never thought about this meant.
    public static func entry(kind: String, ordinal: Int) -> [String] {
        ordinal <= 1 ? [kind, "\(kind).1"] : ["\(kind).\(ordinal)"]
    }
}
