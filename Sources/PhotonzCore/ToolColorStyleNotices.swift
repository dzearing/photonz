import Foundation

/// The two moments where the saved colour a tool is holding cannot come with
/// it, and what the app says about each.
///
/// A tool that has been pointed at Accent draws in Accent, and keeps doing it
/// until one of two things happens. You pick a plain colour underneath the
/// Using Accent line, which is what picking a plain colour has always meant.
/// Or you draw in a document that has never heard of Accent, and the shape
/// comes out the flat colour the tool remembers beside the name, because a
/// saved colour lives inside ONE document and what a tool holds outlives it.
///
/// Both were true and both were silent, so what landed on the canvas was not
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
        case .notInThisDocument:
            return "The \(shape.title) is the plain color the tool remembers, not a saved color"
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
    /// saved colour it has never heard of. Nil when every name the tool held
    /// came with it, which is the ordinary case of drawing where you saved it.
    ///
    /// Read the shape the tool actually built, so this and
    /// `wearingArmedColorStyles` are answering about the same layer: one dresses
    /// it, this one says what could not be put on. A box holding two lost names
    /// leads with the first of its slots, because to the person one shape being
    /// drawn is one thing that happened and the pill holds one line.
    func armedColorStyleMissingHere(_ layer: Layer,
                                    styles: AnnotationStyles) -> ToolColorStyleNotice? {
        guard let shape = layer.annotation?.shape else { return nil }
        for slot in layer.colorSlots {
            guard let id = styles.colorStyleID(forShape: shape, slot: slot),
                  colorStyle(id: id) == nil else { continue }
            return ToolColorStyleNotice(kind: .notInThisDocument, styleID: id,
                                        name: styles.heldColorStyleName(id) ?? "",
                                        shape: shape, slot: slot)
        }
        return nil
    }
}
