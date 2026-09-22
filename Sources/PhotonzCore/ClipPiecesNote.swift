import Foundation

/// What a cut clip says on its row in the layers list: how many pieces it is
/// in.
///
/// **A cut adds a piece to a clip, never a second layer** (UX-PATTERNS D18
/// item 3, `docs/design/video-surface.md` §10.5). That is the rule that stops
/// a timeline growing a row per cut, and its cost is that the layers list —
/// the same list read a different way — showed a recording chopped into six
/// exactly as it showed one nobody had touched. One line closes it: the row
/// keeps its single name and says underneath it how many pieces that name is
/// now in.
///
/// It appears only when there IS more than one piece. Every layer with time
/// answers `clipPieces`, because an uncut clip is one piece, so a note on
/// every clip would be a line reading "1 piece" on every recording in the app.
public struct ClipPiecesNote: Hashable, Sendable {
    /// How many pieces the clip is cut into. Always two or more: one is not a
    /// cut clip and has nothing to say.
    public let count: Int

    /// Nil for a clip that is not cut, which is the answer for a fresh
    /// recording and for a clip retimed without ever being split: what a
    /// single piece is doing with time is the Speed section's sentence
    /// (`SpeedInspector.swift`), not a count of pieces there is only one of.
    public init?(pieces: ClipPieces) {
        guard pieces.count > 1 else { return nil }
        self.count = pieces.count
    }

    /// The line the row prints under the clip's name.
    ///
    /// Two words, and the short one is measured rather than chosen:
    /// `SeparationLeftover` found this same slot — what is left of a narrow
    /// row once the thumbnail, the padlock and the eye have taken theirs — cuts
    /// off at about eighteen characters. "Cut into 12 pieces" would sit exactly
    /// on that edge for the sake of two words the hover already says, and
    /// "pieces" is the word the clip's own trim bar says anyway.
    public var text: String { "\(count) pieces" }

    /// The sentence there is no room for on the row, and the one a person
    /// actually needs: the clip did not become three layers.
    public var help: String {
        "Cut into \(count) pieces. A cut adds a piece to the clip rather than a "
            + "second layer, so it keeps one row however many times you cut it. "
            + "The pieces themselves are on the timeline."
    }
}
