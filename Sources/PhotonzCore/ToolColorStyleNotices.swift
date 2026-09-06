import Foundation

/// The moments where the saved colour a tool is holding cannot come with it,
/// and what the app says about each.
///
/// A tool that has been pointed at Accent draws in Accent, and keeps doing it
/// until one of two things happens. You pick a plain colour underneath the
/// Using Accent line, which is what picking a plain colour has always meant.
/// Or you draw in a document that has never heard of Accent, and the shape
/// comes out the flat colour the tool remembers beside the name, because a
/// saved colour lives inside ONE document and what a tool holds outlives it.
///
/// Or the document has the name but keeps it for other parts — a colour ticked
/// back to outlines and text does not pour into the inside of a box — so that
/// part comes out the flat colour too.
///
/// All of them were true and all of them were silent, so what landed on the canvas was not
/// the colour the person thought they had picked. Each now hands the app a
/// sentence, and each says it where the eye already is. Drawing where the name
/// does not exist happens on the canvas, so it takes the canvas pill every
/// other broken link uses (`LinkBreakReport`). Letting go happens inside an
/// open picker, which covers that pill, so it takes the row the Using line was
/// in — one short `line` in the spot that has just stopped being true.
public struct ToolColorStyleNotice: Hashable, Sendable {

    public enum Kind: Hashable, Sendable {
        /// A plain colour was picked while the tool was holding a name, so the
        /// tool let the name go.
        case letGo
        /// The tool drew where the name does not exist, so the shape came out
        /// the plain colour the tool remembers. The tool KEEPS the name: go
        /// back to the document that has it and the next shape wears it again.
        case notInThisDocument
        /// The document HAS the name, but not for the part the tool was
        /// holding it on: it has since been ticked back to outlines and text,
        /// or to fills and backgrounds, and that part is not in the list. So
        /// that part came out the plain colour the tool remembers instead.
        case notForThisPart
    }

    public var kind: Kind
    /// Which saved colour, so the app can say a thing once rather than on
    /// every shape of a run.
    public var styleID: UUID
    /// What it is called, as the tool remembers it. Empty for a tool that was
    /// armed before names rode along with the id.
    public var name: String
    /// The kind of shape whose tool this is.
    public var shape: AnnotationShape
    /// The part of it the saved colour was painting: its outline, or its
    /// inside. A box holds one name on each and only one of them let go.
    public var slot: ColorSlot

    public init(kind: Kind, styleID: UUID, name: String,
                shape: AnnotationShape, slot: ColorSlot) {
        self.kind = kind
        self.styleID = styleID
        self.name = name
        self.shape = shape
        self.slot = slot
    }

    /// The verdict, set in its own weight at the head of the pill.
    ///
    /// Letting go borrows the words every other broken link uses, because it is
    /// one: something stopped following what it came from. Drawing where the
    /// name does not exist is NOT that — nothing broke, the name simply is not
    /// here — so it says its own thing.
    public var title: String {
        switch kind {
        case .letGo: return "Stopped following"
        case .notInThisDocument:
            return name.isEmpty ? "Saved color left behind" : "No \(name) here"
        case .notForThisPart:
            return name.isEmpty ? "Saved color left behind"
                                : "\(name) is not for \(Self.partsTitle(slot))"
        }
    }

    /// The parts a saved colour is or is not offered for, in the plural, so the
    /// verdict reads as a rule about the colour rather than as a complaint
    /// about this one shape.
    private static func partsTitle(_ slot: ColorSlot) -> String {
        switch slot {
        case .fill: return "fills"
        case .stroke: return "outlines"
        case .text: return "text"
        case .border: return "borders"
        }
    }

    /// What the sentence is about: the part of the shape that came out plain,
    /// pointed at the way a person would point at it.
    ///
    /// A box has two colours and only one of them lost a name, so saying only
    /// "The Rectangle" leaves the reader looking for which. A line, an arrow
    /// and a highlight ARE their one colour, so naming a part there would be
    /// naming the shape twice.
    public var part: String {
        switch (shape, slot) {
        case (.rectangle, .fill), (.ellipse, .fill): return "The \(shape.title)\u{2019}s inside"
        case (.rectangle, .stroke), (.ellipse, .stroke): return "The \(shape.title)\u{2019}s outline"
        default: return "The \(shape.title)"
        }
    }

    /// The whole thing in one short line, for the row inside the picker that
    /// the Using line was in. A verdict over a sentence is the shape of a pill
    /// and does not fit a row, and the row does not need the shape's name: it
    /// is the row belonging to that tool.
    public var line: String {
        name.isEmpty ? "Let go of the saved color" : "Let go of \(name)"
    }

    /// The one line under it.
    public var detail: String {
        switch kind {
        case .letGo:
            let followed = name.isEmpty ? "the saved color it was holding" : name
            return "The \(shape.title) tool no longer follows \(followed)"
        case .notInThisDocument, .notForThisPart:
            return "\(part) is the plain color the tool remembers, not a saved color"
        }
    }
}

public extension AnnotationStyles {

    /// What to say when `slot` is about to be painted a plain colour and this
    /// shape's tool is holding a saved one there. Nil when it is holding none,
    /// which is every ordinary colour pick.
    ///
    /// Ask BEFORE the pick lands: painting a slot is exactly how the name comes
    /// off, so afterwards there is nothing left to report. That is also what
    /// keeps the sentence to one showing — a second pull of the same picker has
    /// no name to let go of.
    func lettingGoOfColorStyle(slot: ColorSlot,
                               forShape shape: AnnotationShape) -> ToolColorStyleNotice? {
        guard let id = colorStyleID(forShape: shape, slot: slot) else { return nil }
        return ToolColorStyleNotice(kind: .letGo, styleID: id,
                                    name: heldColorStyleName(id) ?? "",
                                    shape: shape, slot: slot)
    }
}

public extension PhotonzDocument {

    /// What to say about a shape this document just took from a tool holding a
    /// saved colour that could not come with it. Nil when every name the tool
    /// held came along, which is the ordinary case of drawing where you saved
    /// it.
    ///
    /// A name is left behind for one of two reasons, and the person is told
    /// which. This document may never have heard of it, because a saved colour
    /// lives inside ONE document and what a tool holds outlives it. Or this
    /// document has it and keeps it for other parts: a colour ticked back to
    /// outlines and text is not poured into the inside of a box, so the inside
    /// comes out the flat colour the tool remembers.
    ///
    /// A part the tool draws NOTHING in is not one of them. A box asked for
    /// without an inside is a box without an inside, and a name must never
    /// switch one on, so there is nothing there that came out the wrong colour
    /// and nothing to say.
    ///
    /// Read the shape the tool actually built, so this and
    /// `wearingArmedColorStyles` are answering about the same layer: one dresses
    /// it, this one says what could not be put on. A box holding two lost names
    /// leads with the first of its slots, because to the person one shape being
    /// drawn is one thing that happened and the pill holds one line.
    func armedColorStyleLeftBehind(_ layer: Layer,
                                   styles: AnnotationStyles) -> ToolColorStyleNotice? {
        guard let shape = layer.annotation?.shape else { return nil }
        for slot in layer.colorSlots {
            guard let id = styles.colorStyleID(forShape: shape, slot: slot),
                  layer.paint(for: slot) != nil else { continue }
            let kind: ToolColorStyleNotice.Kind
            if colorStyle(id: id) == nil {
                kind = .notInThisDocument
            } else if !colorStyles(for: slot).contains(where: { $0.id == id }) {
                kind = .notForThisPart
            } else {
                continue
            }
            return ToolColorStyleNotice(kind: kind, styleID: id,
                                        name: styles.heldColorStyleName(id) ?? "",
                                        shape: shape, slot: slot)
        }
        return nil
    }
}
