import Foundation

/// Picking a colour up off one swatch and letting go of it on another.
///
/// A colour well on a Mac has always been something you can drag a colour out
/// of and drop a colour onto, and the right hand panel is full of wells:
/// Outline, Fill, Text, a shadow's colour, a collage backdrop. Putting one
/// colour on two of them used to mean opening the picker twice and matching by
/// eye or by copying a code out of one and into the other.
///
/// The swatch has to answer BEFORE the pointer is let go — that is what the
/// highlight under the pointer means — so the whole answer is worked out here,
/// away from any view. The same answer feeds the highlight, the words in the
/// tip, and the drop itself, so what the swatch promises while the colour is
/// in the air is exactly what letting go does.
public enum ColorDrop {

    /// The swatch a paint is being held over, in the only terms the answer
    /// depends on.
    public struct Target: Hashable, Sendable {
        /// What this swatch paints, in its row's own words: "Fill", "Outline",
        /// "Shadow". The sentence the swatch says is built out of it.
        public var part: String
        /// What the swatch is wearing right now.
        public var wearing: Paint
        /// The saved colour it is wearing, by name, when it wears one. A drop
        /// takes the swatch off it, and says so before it does.
        public var styleName: String?
        /// How many layers letting go here would paint. Zero means the swatch
        /// has nothing behind it and cannot take a colour at all.
        public var reaches: Int
        /// True when this is the very swatch the drag started from, where
        /// letting go can only put back what is already there.
        public var isSource: Bool
        /// Whether this swatch can hold a ramp. The wells that are not part of
        /// a layer's colour set — a shadow, a backdrop — cannot, and neither
        /// can Text or a border.
        public var acceptsGradient: Bool

        public init(part: String, wearing: Paint, styleName: String? = nil,
                    reaches: Int = 1, isSource: Bool = false,
                    acceptsGradient: Bool = false) {
            self.part = part
            self.wearing = wearing
            self.styleName = styleName
            self.reaches = reaches
            self.isSource = isSource
            self.acceptsGradient = acceptsGradient
        }
    }

    /// What actually lands when the pointer is let go.
    public struct Landing: Hashable, Sendable {
        /// The paint the swatch takes, already flattened where it had to be.
        public var paint: Paint
        /// True when a gradient gave up its ramp to fit a swatch that cannot
        /// hold one.
        public var flattened: Bool
        /// The saved colour this drop takes the swatch off, by name.
        public var letsGoOf: String?
    }

    /// A swatch's reply to a paint held over it: whether it lights up, what
    /// letting go would do, and the one sentence that says so.
    public struct Answer: Hashable, Sendable {
        /// Nil when the swatch refuses, which is also when it does not light
        /// up and letting go there changes nothing.
        public var landing: Landing?
        /// What the tip says while the colour is over the swatch. Written
        /// either way round: a refusal says why, so a swatch that stays dark
        /// is never a mystery.
        public var note: String

        public var lightsUp: Bool { landing != nil }
    }

    /// What this swatch would do with the paint being held over it.
    public static func answer(dropping paint: Paint, on target: Target) -> Answer {
        guard !target.isSource else {
            return Answer(landing: nil, note: "This is where the colour came from.")
        }
        guard target.reaches > 0 else {
            return Answer(landing: nil, note: "There is nothing here to paint.")
        }
        let flattens = paint.isGradient && !target.acceptsGradient
        let landing = flattens ? Paint(hex: paint.hex) : paint
        // A swatch already wearing this colour has nothing to do, and a no-op
        // that lights up and writes an undo step is worse than one that says
        // so. Wearing a SAVED colour is different: letting go there still
        // takes it off the name, whatever colour the name stands for today.
        if target.styleName == nil, landing.draws(sameAs: target.wearing) {
            return Answer(landing: nil, note: "\(opening(target.part)) is already this colour.")
        }
        let result = Landing(paint: landing, flattened: flattens, letsGoOf: target.styleName)
        return Answer(landing: result, note: note(for: result, on: target))
    }

    /// The sentence a swatch says while a colour is over it. One clause about
    /// what gets painted, and one about what that costs — a ramp given up, a
    /// saved colour let go of — because both are things somebody would rather
    /// know before letting go than after.
    private static func note(for landing: Landing, on target: Target) -> String {
        if landing.flattened {
            return "\(opening(target.part)) cannot hold a gradient, so it takes its flat colour."
        }
        var sentence = target.reaches > 1
            ? "Paints \(target.part) on all \(target.reaches) of them with this colour"
            : "Paints \(target.part) with this colour"
        if let name = landing.letsGoOf { sentence += " and lets go of \(name)" }
        return sentence + "."
    }

    /// A part at the START of a sentence.
    ///
    /// The panel's swatches are named after the row they sit on — "Fill",
    /// "Outline" — and read as themselves anywhere in a sentence. The
    /// toolbar's swatch has no row: what it stands for is the next shape you
    /// draw, and the only honest name for it is those words, which have to be
    /// capitalised where they start the sentence and left alone where they do
    /// not. Only the first letter is touched, so "the next shape's border"
    /// keeps everything after it exactly as the swatch wrote it.
    private static func opening(_ part: String) -> String {
        guard let first = part.first else { return part }
        return first.uppercased() + part.dropFirst()
    }
}

// MARK: - Letting a colour go on the Library shelf

extension ColorDrop {

    /// The Library shelf as somewhere to let a colour go.
    ///
    /// Every other drop target in the app PAINTS with the colour. This one
    /// KEEPS it: letting go asks for a name and the colour becomes a tile you
    /// can reach from any colour row afterwards. So the shelf has none of a
    /// swatch's refusals — it wears nothing, it lets go of nothing, and it
    /// holds a ramp as happily as a flat colour — and the only reason it ever
    /// stays dark is that there is nowhere to save a colour to.
    public struct Shelf: Hashable, Sendable {
        /// Whether saved colours are on at all. False is the whole reason the
        /// shelf would refuse a colour.
        public var canSave: Bool
        /// The name of a colour already on the shelf that draws the same, when
        /// there is one. The drop is still taken — one blue really is both
        /// Brand and Link — but it is said out loud first.
        public var alreadySaved: String?

        public init(canSave: Bool = true, alreadySaved: String? = nil) {
            self.canSave = canSave
            self.alreadySaved = alreadySaved
        }
    }

    /// What the Library shelf would do with the paint being held over it.
    public static func answer(dropping paint: Paint, on shelf: Shelf) -> Answer {
        guard shelf.canSave else {
            return Answer(landing: nil, note: "Saved colors are turned off.")
        }
        // Nothing is flattened and nothing is let go of: the shelf keeps the
        // paint exactly as it arrived.
        let landing = Landing(paint: paint, flattened: false, letsGoOf: nil)
        if let name = shelf.alreadySaved {
            return Answer(landing: landing,
                          note: "\(name) is already this color. Saving keeps a second one.")
        }
        return Answer(landing: landing,
                      note: "Saves this \(ColorStyleNaming.subject(paint)) "
                          + "under a name you choose.")
    }
}
