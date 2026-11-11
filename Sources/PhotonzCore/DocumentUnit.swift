import CoreGraphics
import Foundation

/// The ONE word the app says for a length, and the one place a length is
/// written out for a person to read.
///
/// Everything the document measures is in the same space: where a layer sits,
/// how wide it is, how round its corners are, how thick its outline is, how far
/// apart the grid's lines are, how big its type is. A person redlining a
/// screenshot copies those numbers into a spec side by side, so two words for
/// one space is two units to reconcile in their head, every time.
///
/// The word is `px`: a layer's position, size, corners and outline are in the
/// picture's own pixels. A measurement is the one readout that may say
/// something else, and only because it measures something else: on a Retina
/// picture its default unit is points (the on-screen size a developer types
/// into a layout), and it says `pt` there so "124" is never mistaken for the
/// 248 pixels it spans (`MeasureUnit.suffix(pixelScale:)`, the user's
/// calm-redline checklist of 2026-10-20). On a 1x picture the two are the
/// same number and both say px.
///
/// Write every readout through here. The panel drifted in the first place
/// because the unit was an independent string literal in nine files, and a
/// tenth would drift again.
public enum DocumentUnit {

    /// The word itself, for a control that draws the number and the unit apart
    /// (a field with its suffix beside the box).
    public static var word: String { MeasureUnit.pixels.suffix(pixelScale: 1) }

    /// A whole length, rounded the way a readout rounds it: "18 px".
    public static func text(_ value: CGFloat) -> String {
        text(digits: String(Int(value.rounded())))
    }

    /// The unit word put after a number somebody else has already written out,
    /// for the readouts that do their own rounding — the grid says halves
    /// ("7.5 px") and its chip says a range ("4 → 32 px").
    public static func text(digits: String) -> String {
        "\(digits) \(word)"
    }
}

extension DocumentUnit {

    /// A readout caught saying a length in some word other than the app's.
    public struct Stray: Hashable, Sendable {
        /// The readout exactly as a person is reading it, so a failure can
        /// quote what is on screen rather than describe it.
        public let text: String
        /// The word it used instead.
        public let word: String

        public init(text: String, word: String) {
            self.text = text
            self.word = word
        }
    }

    /// Every spelling of a length the app must never grow a second of. Not only
    /// `pt`: the point is that ONE word is on screen, so a row that starts
    /// saying "pts" or "dp" is the same fault and is caught the same way.
    ///
    /// `in` is deliberately absent. A panel will say "3 in the group" long
    /// before it says "3 in", and a check that cries wolf is a check somebody
    /// deletes.
    static let lengthWords: Set<String> = [
        "pt", "pts", "point", "points",
        "px", "pixel", "pixels",
        "dp", "dip", "em", "rem", "cm", "mm",
    ]

    /// Reads a pile of readouts — whatever the right hand panel is showing —
    /// and hands back the ones spelling a length in anything but `word`.
    ///
    /// A unit only counts when it is sitting ON a number, so "Points of
    /// interest" is prose and "18 pt" is a readout, and it has to be a whole
    /// word, so the Border's "Inside" is not an inch.
    ///
    /// `measuringIn` is the word a measurement on this picture says, when it
    /// says another one (`pt` on a Retina picture); a readout in it is a
    /// measurement's, not a stray.
    public static func strays(in readouts: [String], measuringIn measureWord: String? = nil) -> [Stray] {
        readouts.compactMap { text in
            guard let stray = strayWord(in: text), stray != measureWord else { return nil }
            return Stray(text: text, word: stray)
        }
    }

    /// The first word in one readout that says a length the wrong way, if any.
    static func strayWord(in text: String) -> String? {
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            guard characters[index].isNumber else {
                index += 1
                continue
            }
            // Walk to the end of the number, then over the one space a readout
            // puts between a number and its unit.
            while index < characters.count,
                  characters[index].isNumber || characters[index] == "." {
                index += 1
            }
            var start = index
            if start < characters.count, characters[start] == " " { start += 1 }
            var end = start
            while end < characters.count, characters[end].isLetter { end += 1 }
            // A unit is the WHOLE word: "4 pointing" is not four points, so a
            // letter still running on means this was never a unit.
            guard end > start else {
                index = max(index, start)
                continue
            }
            let candidate = String(characters[start..<end]).lowercased()
            if candidate != word, lengthWords.contains(candidate) { return candidate }
            index = end
        }
        return nil
    }
}
