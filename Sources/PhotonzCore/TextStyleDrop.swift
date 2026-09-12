import CoreGraphics
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

    /// Words that belong to a COPY of a component, in the terms the sentence
    /// about them needs.
    ///
    /// The hit test stops at the copy, because a copy's contents are its
    /// original's and a click picks the whole thing. So words inside one used
    /// to arrive looking like anything that is not text, and got told "Save
    /// button is not text" over the top of words anybody can read. Reaching
    /// one level further to say what is really there is what this is for: the
    /// name of the piece, the name of the original, and whether this copy may
    /// simply wear the style itself.
    public struct CopyPiece: Hashable, Sendable {
        /// The original's name for this piece, "Label" for a button's words.
        /// Empty when nobody named it.
        public var piece: String
        /// What the original is called, empty when nobody named it.
        public var component: String
        /// Whether stopping this copy from following its original is a real way
        /// forward. It is not for a copy inside another copy: the outer copy
        /// rebuilds the inner one, so detaching the inner one does not stick.
        public var canDetach: Bool
        /// Whether this copy may wear a type of its own for these words
        /// (`ComponentPieceTextStyle`). It may not inside a copy that is
        /// itself inside another copy, for the same reason detaching does not
        /// stick there: the outer copy rebuilds the inner one, and the answer
        /// goes with it.
        public var canWearItsOwn: Bool
        /// The style these words already wear, by id, whether it came from the
        /// original or from this copy's own answer. The same name arriving on
        /// them has nothing to do.
        public var wearingID: UUID?
        /// The style this copy has already set these words in, by name. A drop
        /// takes them off it, and says so before it does. Nil when the type
        /// they wear is the original's, because nothing is being given up
        /// there: what the original says still reaches every other part.
        public var wearingName: String?

        public init(piece: String, component: String, canDetach: Bool,
                    canWearItsOwn: Bool = false, wearingID: UUID? = nil,
                    wearingName: String? = nil) {
            self.piece = piece
            self.component = component
            self.canDetach = canDetach
            self.canWearItsOwn = canWearItsOwn
            self.wearingID = wearingID
            self.wearingName = wearingName
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
        /// Set when the pointer is on the words of a copy. The hit test stops
        /// at the copy, so `isText` is false and `name` is the copy's name;
        /// this is what the words themselves are.
        public var copyPiece: CopyPiece?
        /// Whether this text is locked. The one case a ROW meets that the
        /// picture never does: the canvas hit test walks straight past a
        /// locked layer, so a style can only ever be aimed at one in the
        /// layers list. Locked means there what it means everywhere else —
        /// the Text section will not dress a locked layer either — so it is a
        /// refusal, and one worth naming, because the layer plainly IS text
        /// and "not text" would be a lie.
        public var isLocked: Bool

        public init(name: String?, isText: Bool, wearingID: UUID? = nil,
                    wearingName: String? = nil, reaches: Int = 1,
                    copyPiece: CopyPiece? = nil, isLocked: Bool = false) {
            self.name = name
            self.isText = isText
            self.wearingID = wearingID
            self.wearingName = wearingName
            self.reaches = reaches
            self.copyPiece = copyPiece
            self.isLocked = isLocked
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
        if let copy = target.copyPiece {
            // One copy may wear its own type, answered on 2026-09-09: somebody
            // aiming a style at the words in ONE button meant that button, and
            // the two moves that used to be offered instead are both bigger
            // than what was asked for. So it lands, on this copy and nothing
            // else, and the sentence says which of the two it is before the
            // pointer is let go.
            if copy.canWearItsOwn {
                guard copy.wearingID != style.id else {
                    let subject = copy.piece.isEmpty ? "This text" : copy.piece
                    return Answer(lands: false, note: "\(subject) is already \(style.name).")
                }
                let subject = copy.piece.isEmpty ? "these words" : copy.piece
                var sentence = "Sets \(subject) in \(style.name) on this copy only"
                if let worn = copy.wearingName { sentence += " and lets go of \(worn)" }
                return Answer(lands: true, note: sentence + ".", letsGoOf: copy.wearingName)
            }
            // Nowhere for an answer to live — a copy inside a copy is rebuilt
            // by the outer one — and the words are right there under the
            // pointer, so saying the copy "is not text" would tell somebody
            // that what they can see is false. What is true is where the words
            // come from, and it comes with the move that DOES work: the style
            // goes on the original, which every copy then follows.
            let piece = copy.piece.isEmpty ? "This text" : copy.piece
            let origin = copy.component.isEmpty ? "the original" : copy.component
            // "there" rather than "on the original" when the sentence has
            // already had to call it that, so it is not said twice.
            let place = copy.component.isEmpty ? "there" : "on the original"
            var sentence = "\(piece) comes from \(origin). Set \(style.name) \(place)"
            if copy.canDetach { sentence += ", or detach this copy" }
            return Answer(lands: false, note: sentence + ".")
        }
        guard target.isText else {
            // The one place a name earns its keep. Nothing is outlined, so what
            // somebody needs told is what KIND of thing they are pointing at,
            // and its name is the fastest way to say that.
            let subject = name.isEmpty ? "That" : name
            return Answer(lands: false,
                          note: "\(subject) is not text, so it cannot wear \(style.name).")
        }
        guard !target.isLocked else {
            // Named, and for the same reason a shape is: the sentence has to
            // say which of the two things is in the way, and a padlock two
            // rows up is not what somebody carrying a style is looking at.
            let subject = name.isEmpty ? "That" : name
            return Answer(lands: false,
                          note: "\(subject) is locked, so it cannot wear \(style.name).")
        }
        guard target.wearingID != style.id else {
            return Answer(lands: false, note: "This text is already \(style.name).")
        }
        // Text is never named, however it is named in the layers list. The
        // outline round it and the pointer on it already say WHICH text, and
        // the made-up name a fresh block gets ("Text 2") would say less than
        // the two words it is drawn over.
        let who = CrowdWords.them(target.reaches) ?? "this text"
        var sentence = "Sets \(who) in \(style.name)"
        // Only worth saying for the one piece of text being named. A crowd
        // could be letting go of several different names at once, and picking
        // one of them to print would be a promise about the others.
        let letsGoOf = target.reaches > 1 ? nil : target.wearingName
        if let letsGoOf { sentence += " and lets go of \(letsGoOf)" }
        return Answer(lands: true, note: sentence + ".", letsGoOf: letsGoOf)
    }
}

extension PhotonzDocument {

    /// The words of a copy under a canvas point, described for the one line the
    /// canvas says while a style is in the air, and for the drop itself. Nil
    /// everywhere else, which is every point that is not on a copy's own
    /// words.
    ///
    /// A style let go here lands on THIS copy and nothing else
    /// (`ComponentPieceTextStyle`), except inside a copy that is itself inside
    /// another copy: the outer one rebuilds the inner one after every edit, so
    /// an answer given there is gone by the next redraw, and that is the one
    /// case still refused with a reason.
    public func textStyleCopyPiece(at point: CGPoint, zoom: CGFloat = 1)
    -> TextStyleDrop.CopyPiece? {
        guard let words = textPiece(at: point, zoom: zoom),
              let piece = componentPiece(of: words) else { return nil }
        // What this copy has already set these words in, which is the only
        // name a drop takes them off: the type they get from the original is
        // not given up by one copy answering for itself.
        let own = pieceTextStyles(instance: piece.instance)
            .first { $0.source == piece.source }
        return TextStyleDrop.CopyPiece(
            piece: layer(id: piece.source)?.name ?? "",
            component: mainComponent(componentID: piece.componentID)?.name
                ?? layer(id: piece.instance)?.name ?? "",
            canDetach: !piece.isNested,
            canWearItsOwn: canSetPieceTextStyle(of: words),
            wearingID: pieceTextStyleID(of: words),
            wearingName: own?.styleID.flatMap { textStyle(id: $0)?.name })
    }
}

// MARK: - Letting a style go on a row in the layers list

extension PhotonzDocument {

    /// What letting a saved text style go on a ROW in the layers list would do,
    /// and which layers it would reach.
    ///
    /// The picture was the only place a style could be put down, and the row is
    /// the other obvious place to aim: the list is where a layer is named,
    /// picked and reordered, so it is where somebody expects to be able to
    /// dress it too.
    ///
    /// This is a second drop TARGET, not a second set of rules. It works out
    /// the same `Target` the canvas works out and hands it to the same
    /// `answer`, so the sentence a row says and the sentence the picture says
    /// are the same sentence, and what lands is the same thing.
    ///
    /// Two differences, and both come from the row being a NAME rather than a
    /// picture of the words. A locked layer is invisible to the canvas hit test
    /// and unmissable in the list, so a row can be aimed at one and has to
    /// refuse it. And nothing here can be a piece of a copy: a copy's row never
    /// opens, because its contents belong to its original, so the words inside
    /// one have no row to aim at in the first place.
    ///
    /// - Parameter picked: what is selected right now. Aiming at a row that is
    ///   part of the selection reaches every picked piece of text, the way the
    ///   canvas drop does; aiming at a row nobody picked reaches only that row,
    ///   because the pointer named it.
    public func textStyleRowDrop(_ style: TextStyleDrop.SavedStyle, onRow id: UUID,
                                 picked: Set<UUID> = [])
    -> (answer: TextStyleDrop.Answer, layerIDs: [UUID]) {
        // A row that is not there any more — deleted mid-drag, or a list
        // rebuilt out from under the pointer — is pointing at nothing, and
        // gets the signpost bare canvas gets rather than a refusal about a
        // layer nobody can see.
        guard let layer = layer(id: id) else {
            return (TextStyleDrop.answer(dropping: style,
                                         on: TextStyleDrop.Target(name: nil, isText: false)), [])
        }
        guard layer.textTreatment != nil else {
            return (TextStyleDrop.answer(dropping: style,
                                         on: TextStyleDrop.Target(name: layer.name,
                                                                  isText: false)), [])
        }
        guard !layer.isLocked else {
            return (TextStyleDrop.answer(dropping: style,
                                         on: TextStyleDrop.Target(name: layer.name, isText: true,
                                                                  isLocked: true)), [])
        }
        var reached = [id]
        if picked.contains(id) {
            let crowd = allLayers
                .filter { picked.contains($0.id) && $0.textTreatment != nil && !$0.isLocked }
                .map(\.id)
            if crowd.count > 1 { reached = crowd }
        }
        // A crowd where some already wear the style still has work to do, so
        // the no-op refusal only speaks for the one row being named.
        let target = TextStyleDrop.Target(
            name: layer.name, isText: true,
            wearingID: reached.count > 1 ? nil : layer.textStyleID,
            wearingName: reached.count > 1 ? nil
                : layer.textStyleID.flatMap { textStyle(id: $0)?.name },
            reaches: reached.count)
        return (TextStyleDrop.answer(dropping: style, on: target), reached)
    }
}
