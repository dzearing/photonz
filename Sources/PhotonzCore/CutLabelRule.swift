import CoreGraphics
import Foundation

/// A label the chrome cut short, found by the ellipsis it was cut with.
///
/// The words are read off a picture of the window (`labelsWhole`), so the
/// rule sees what a person sees: "Write Ag…" beside a caption count, "Ease In
/// and..." in the timeline's bar. The reader gives the glyph back as "…" or
/// as three dots (or two, having lost one), so they all count, at the end of the words or in the middle of
/// a name cut in two ("Tutori…e.mp4").
///
/// Two places are left out on purpose, as zones: the picture being edited
/// (its words are the document's, not the app's) and the clips on the lanes,
/// where a long name cut to the clip's length is how Premiere and Final Cut
/// draw one too.
public enum CutLabelRule {
    /// Words read off the window, in window points, top-left origin.
    public struct Reading: Hashable, Sendable, Codable {
        public let text: String
        public let frame: CGRect

        public init(text: String, frame: CGRect) {
            self.text = text
            self.frame = frame
        }
    }

    /// Whether these words were cut short to fit.
    public static func isCut(_ text: String) -> Bool {
        // Dots with no words around them are an icon (the "•••" menu button
        // reads as "•.."), never a label cut short: a cut label keeps some of
        // its words.
        guard text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) else { return false }
        // The reader sometimes loses a dot of the three ("Lower..").
        return text.contains("…") || text.contains("...") || text.hasSuffix("..")
    }

    /// The readings that are cut, leaving out any whose middle sits in one of
    /// `zones`.
    public static func cut(_ readings: [Reading], outside zones: [CGRect]) -> [Reading] {
        readings.filter { reading in
            let middle = CGPoint(x: reading.frame.midX, y: reading.frame.midY)
            return isCut(reading.text) && !zones.contains { $0.contains(middle) }
        }
    }

    /// The words in `wanted` that no reading carries whole, as a word of its
    /// own (so "Rewrite" is found in "Rewrite 10 captions" and never in a
    /// cut "Rewr…").
    public static func missing(_ wanted: [String], in readings: [Reading]) -> [String] {
        wanted.filter { word in
            !readings.contains { reading in
                guard let range = reading.text.range(of: word, options: .caseInsensitive) else { return false }
                let after = reading.text[range.upperBound...]
                return !after.hasPrefix("…") && !after.hasPrefix("..")
            }
        }
    }
}
