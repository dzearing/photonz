/// How a menu row, a menu heading and a button label are capitalised: the Mac
/// way, Title Case, the way the menu bar macOS writes into every app already
/// reads (Select All, Enter Full Screen) and the way Photoshop, Premiere and
/// Final Cut write theirs (Merge Down, Ripple Delete, Add Cross Dissolve).
///
/// The mocks write their rows in sentence case ("Apply to every cut"); the
/// user chose the Mac's casing over the mocks' on 2026-09-30
/// (`the-design-rules-say-how-a-menu-row-is-capitalis`), and UX-PATTERNS §7
/// "How a menu row is capitalised" is the rule. A label beside a control in
/// the panel ("Between the keys") keeps sentence case: it is a label, not a
/// command.
///
/// Apple's style: every word is capitalised except articles, coordinating
/// conjunctions and short prepositions, and those are capitalised too when
/// they open or close the title (or a phrase after a colon). A short word
/// that is the particle of a verb or a noun (Punch In, Clear In and Out, Turn
/// Off Snapping) may keep its capital. Names that are not capitalised the
/// ordinary way (macOS, iCloud) and anything with a digit in it (2x, H.264)
/// are left alone.
public enum MenuTitleCase {

    /// Written small in the middle of a title.
    static let smallWords: Set<String> = [
        "a", "an", "the",
        "and", "but", "or", "nor", "for", "so", "yet",
        "as", "at", "by", "from", "in", "into", "of", "off", "on", "onto", "out", "over",
        "per", "to", "up", "via", "vs", "with",
    ]

    /// Small words that may keep a capital in the middle, because they are
    /// just as often a verb's particle or a noun: Clear In and Out, Turn Off.
    static let particles: Set<String> = ["in", "out", "up", "off", "on", "over"]

    /// The words of `title` that break Title Case, in order, as written.
    public static func departures(in title: String) -> [String] {
        words(of: title).compactMap { word in
            guard let wanted = wantedCapital(word) else { return nil }
            return word.isCapitalised == wanted ? nil : word.core
        }
    }

    /// `title` in Title Case, with its punctuation and its names untouched.
    public static func titleCased(_ title: String) -> String {
        var tokens = title.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        for word in words(of: title) {
            guard let wanted = wantedCapital(word), word.isCapitalised != wanted else { continue }
            let token = tokens[word.token]
            guard let first = token.firstIndex(where: \.isLetter) else { continue }
            let letter = String(token[first])
            tokens[word.token] = token.replacingCharacters(in: first...first,
                                                          with: wanted ? letter.uppercased() : letter.lowercased())
        }
        return tokens.joined(separator: " ")
    }

    // MARK: Reading a title

    struct Word {
        /// Which space separated piece of the title it is.
        let token: Int
        /// The word without the punctuation around it, and only up to a hyphen.
        let core: String
        /// Opens or closes the title, or a phrase after a colon.
        let atAnEdge: Bool

        var isCapitalised: Bool { core.first?.isUppercase ?? false }
    }

    /// Whether `word` should start with a capital, or nil when it is not a
    /// word to judge (a name, a number, a key).
    static func wantedCapital(_ word: Word) -> Bool? {
        let core = word.core
        guard let first = core.first, first.isLetter else { return nil }
        if core.contains(where: \.isNumber) { return nil }
        // macOS, iCloud: a name with its own capitals.
        if first.isLowercase, core.dropFirst().contains(where: \.isUppercase) { return nil }
        if word.atAnEdge { return true }
        let lower = core.lowercased()
        guard smallWords.contains(lower) else { return true }
        if particles.contains(lower), word.isCapitalised { return nil }
        return false
    }

    static func words(of title: String) -> [Word] {
        struct Piece { let token: Int; let core: String; let closesAPhrase: Bool }
        var pieces: [Piece] = []
        for (index, token) in title.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            guard let start = token.firstIndex(where: { $0.isLetter || $0.isNumber }),
                  let end = token.lastIndex(where: { $0.isLetter || $0.isNumber }) else { continue }
            let body = token[start...end]
            let core = body.split(separator: "-").first.map(String.init) ?? String(body)
            let after = token[token.index(after: end)...]
            pieces.append(Piece(token: index, core: core, closesAPhrase: after.contains(":")))
        }
        return pieces.enumerated().map { offset, piece in
            let opens = offset == 0 || pieces[offset - 1].closesAPhrase
            let closes = offset == pieces.count - 1 || piece.closesAPhrase
            return Word(token: piece.token, core: piece.core, atAnEdge: opens || closes)
        }
    }
}
