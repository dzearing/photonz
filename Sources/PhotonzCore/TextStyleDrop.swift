import Foundation

/// Picking a saved text style up off the Library shelf and letting go of it on
/// a piece of text.
///
/// A saved colour has always been a handle: its tile is picked up and dropped
/// on any swatch, which is what makes the shelf a place styles come FROM. A
/// text style had no such handle, so the only way to wear one was to select the
/// text and find the name in a menu, and the shelf was a place text styles went
/// and never came back out of.
///
/// The picture has to answer BEFORE the pointer is let go — that is what the
/// outline under the pointer means — so the whole answer is worked out here,
/// away from any view. The outline, the one line that says what letting go
/// would do, and the drop itself all read the same answer, so what the canvas
/// promises while the style is in the air is exactly what letting go does.
public enum TextStyleDrop {

    /// The style a drag IS: not a copy of what it looks like, but the saved
    /// name itself, so text dropped on follows the name the day the style
    /// behind it is edited. That is the whole point of having saved it, and it
    /// is exactly what picking the name out of the Style menu does.
    public struct SavedStyle: Hashable, Codable, Sendable {
        public var id: UUID
        public var name: String

        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// What is under the pointer, in the only terms the answer depends on.
    public struct Target: Hashable, Sendable {
        /// The name of the layer under the pointer, nil when there is nothing
        /// there at all. Empty for a layer nobody has named.
        public var name: String?
        /// Whether it is text. Everything else in a document can be painted
        /// but not SET, so a style has nowhere to land on it.
        public var isText: Bool
        /// The style this text already wears, by id. The same name arriving on
        /// text already wearing it has nothing to do.
        public var wearingID: UUID?
        /// The style this text already wears, by name. A drop takes it off
        /// that name, and says so before it does.
        public var wearingName: String?
        /// How many pieces of text letting go here would set. More than one
        /// when the text under the pointer is part of a bigger selection, the
        /// same way a swatch paints everything its row speaks for.
        public var reaches: Int

        public init(name: String?, isText: Bool, wearingID: UUID? = nil,
                    wearingName: String? = nil, reaches: Int = 1) {
            self.name = name
            self.isText = isText
            self.wearingID = wearingID
            self.wearingName = wearingName
            self.reaches = reaches
        }
    }

    /// What the picture says back: whether letting go here does anything, the
    /// one line that says what, and the name being given up if there is one.
    ///
    /// Written either way round, because a refusal that says why is never a
    /// mystery and a canvas that quietly does nothing always is.
    public struct Answer: Hashable, Sendable {
        public var lands: Bool
        public var note: String
        public var letsGoOf: String?

        public init(lands: Bool, note: String, letsGoOf: String? = nil) {
            self.lands = lands
            self.note = note
            self.letsGoOf = letsGoOf
        }
    }

    /// What letting go of this style here would do.
    public static func answer(dropping style: SavedStyle, on target: Target) -> Answer {
        guard let name = target.name else {
            // Not a refusal to explain away: somebody is carrying a style and
            // has not found where it goes yet, so this is a signpost.
            return Answer(lands: false,
                          note: "Drop this on a piece of text to set it in \(style.name).")
        }
        guard target.isText else {
            // The one place a name earns its keep. Nothing is outlined, so what
            // somebody needs told is what KIND of thing they are pointing at,
            // and its name is the fastest way to say that.
            let subject = name.isEmpty ? "That" : name
            return Answer(lands: false,
                          note: "\(subject) is not text, so it cannot wear \(style.name).")
        }
        guard target.wearingID != style.id else {
            return Answer(lands: false, note: "This text is already \(style.name).")
        }
        // Text is never named, however it is named in the layers list. The
        // outline round it and the pointer on it already say WHICH text, and
        // the made-up name a fresh block gets ("Text 2") would say less than
        // the two words it is drawn over.
        let who = target.reaches > 1 ? "all \(target.reaches) of them" : "this text"
        var sentence = "Sets \(who) in \(style.name)"
        // Only worth saying for the one piece of text being named. A crowd
        // could be letting go of several different names at once, and picking
        // one of them to print would be a promise about the others.
        let letsGoOf = target.reaches > 1 ? nil : target.wearingName
        if let letsGoOf { sentence += " and lets go of \(letsGoOf)" }
        return Answer(lands: true, note: sentence + ".", letsGoOf: letsGoOf)
    }
}
