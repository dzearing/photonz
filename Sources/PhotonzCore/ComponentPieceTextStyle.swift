import CoreGraphics
import Foundation

/// One copy wearing its own TYPE for one piece inside it.
///
/// A copy follows its original, and the way it is allowed to differ is by
/// owning one fact at a time: its colour, its size, its room, its opacity, its
/// wording. This is one more of that family, and it comes from the question
/// answered on 2026-09-09 — should a saved text style let go on the words
/// inside one copy set THAT copy? The answer was yes, because somebody aiming
/// a style at one button plainly meant that button, and the two moves that
/// were on offer instead are both bigger: setting it on the original changes
/// every copy, and detaching gives up following the original for good.
///
/// It is not a knob. Every other per-copy fact is an answer to something the
/// ORIGINAL chose to expose, which is the rule that keeps adjusting from
/// becoming drifting. A text style arrives from outside the component
/// altogether — off the Library shelf, in one gesture, often onto a copy whose
/// original somebody else drew — so there is nobody to ask for a knob first.
/// What keeps it honest instead is that the copy says out loud that its type
/// is its own, and one press puts it back (`instanceOwnTypeLabel`).
///
/// The shape is deliberately the shape of a colour answer
/// (`ComponentColorAnswer`): the thing that gets drawn, plus a pointer to the
/// name it came from. The treatment means nothing downstream has to know what
/// a style is, and the pointer is what makes editing Heading later reach this
/// copy, and what lets the name be taken off the shelf without re-setting
/// anybody's work.
public struct ComponentPieceTextStyle: Hashable, Codable, Sendable {
    /// The layer INSIDE the original these words are a picture of. The copy's
    /// own piece is derived from it, so this id is the one stable handle —
    /// exactly what a knob stores.
    public var source: UUID
    /// The type this copy sets those words in. Kept in step with the style
    /// while it points at one, so it is an honest answer the moment the name
    /// goes away.
    public var treatment: TextTreatment
    /// The saved style it points at, or nil for type of its own — which is
    /// what a piece is left holding when the style is taken off the shelf.
    public var styleID: UUID?

    public init(source: UUID, treatment: TextTreatment, styleID: UUID? = nil) {
        self.source = source
        self.treatment = treatment
        self.styleID = styleID
    }
}

// MARK: - Setting it, and taking it back

extension PhotonzDocument {

    /// The answers a copy has given about type, empty for everything that is
    /// not a copy.
    public func pieceTextStyles(instance: UUID) -> [ComponentPieceTextStyle] {
        layer(id: instance)?.group?.pieceTextStyles ?? []
    }

    /// Whether these words could be given type of their own here.
    ///
    /// The same two things that stop a wording edit landing stop this one: a
    /// locked copy changes in no way until it is unlocked, and a copy inside
    /// another copy is rebuilt by the outer one, so an answer given to it has
    /// nowhere to live.
    public func canSetPieceTextStyle(of id: UUID) -> Bool {
        guard let piece = componentPiece(of: id), !piece.isNested,
              layer(id: piece.instance)?.isLocked == false,
              layer(id: id)?.textTreatment != nil else { return false }
        return true
    }

    /// The style these words wear: the copy's own answer where it gave one,
    /// and otherwise whatever the original's piece wears. Nil for words that
    /// wear no name at all.
    public func pieceTextStyleID(of id: UUID) -> UUID? {
        guard let piece = componentPiece(of: id) else { return nil }
        if let own = pieceTextStyles(instance: piece.instance)
            .first(where: { $0.source == piece.source }) {
            return own.styleID
        }
        return layer(id: piece.source)?.textStyleID
    }

    /// Sets the words inside ONE copy in a saved style. Nothing else about the
    /// copy changes, no other copy changes, and the original is untouched.
    ///
    /// False when there is nowhere for the answer to live, which is the
    /// caller's cue to say why rather than to look as if it worked.
    @discardableResult
    public mutating func setPieceTextStyle(of id: UUID, styleID: UUID) -> Bool {
        guard canSetPieceTextStyle(of: id), let piece = componentPiece(of: id),
              let style = textStyle(id: styleID) else { return false }
        let answer = ComponentPieceTextStyle(source: piece.source, treatment: style.treatment,
                                             styleID: styleID)
        updateLayer(id: piece.instance) { layer in
            guard var group = layer.group else { return }
            if let index = group.pieceTextStyles.firstIndex(where: { $0.source == piece.source }) {
                group.pieceTextStyles[index] = answer
            } else {
                group.pieceTextStyles.append(answer)
            }
            layer.content = .group(group)
        }
        return true
    }

    /// Puts one piece back to the type its original wears.
    @discardableResult
    public mutating func clearPieceTextStyle(of id: UUID) -> Bool {
        guard let piece = componentPiece(of: id),
              pieceTextStyles(instance: piece.instance).contains(where: { $0.source == piece.source })
        else { return false }
        updateLayer(id: piece.instance) { layer in
            guard var group = layer.group else { return }
            group.pieceTextStyles.removeAll { $0.source == piece.source }
            layer.content = .group(group)
        }
        return true
    }

    /// Puts every piece of these copies back to the type their original wears,
    /// in one step. Returns how many copies had something to put back, which is
    /// what a notice can say out loud.
    @discardableResult
    public mutating func clearInstancePieceTextStyles(instances: [UUID]) -> Int {
        var count = 0
        for id in instances {
            guard !pieceTextStyles(instance: id).isEmpty,
                  layer(id: id)?.isLocked == false else { continue }
            updateLayer(id: id) { layer in
                guard var group = layer.group else { return }
                group.pieceTextStyles = []
                layer.content = .group(group)
            }
            count += 1
        }
        return count
    }

    /// What the "its own type" row says: which pieces of the one picked copy
    /// answered for themselves and in what, or how many of several copies did.
    /// Nil when none of them has type of its own, which is when the row is not
    /// there at all.
    public func instanceOwnTypeLabel(instances: [UUID]) -> String? {
        let own = instances.filter { !pieceTextStyles(instance: $0).isEmpty }
        guard !own.isEmpty else { return nil }
        if instances.count == 1 {
            let parts = pieceTextStyles(instance: instances[0]).map { answer -> String in
                let piece = layer(id: answer.source)?.name ?? ""
                let name = answer.styleID.flatMap { textStyle(id: $0)?.name } ?? "type of its own"
                return piece.isEmpty ? name : "\(piece) in \(name)"
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        return ComponentInstanceCount.phrase(own.count, of: instances.count,
                                             singular: "has type of its own",
                                             plural: "have type of their own")
    }

    /// Whether every one of these layers is words inside a copy. What it
    /// decides is whether an edit to them is news about copies following an
    /// original, or just the thing somebody did.
    public func allAreComponentPieces(_ ids: [UUID]) -> Bool {
        !ids.isEmpty && ids.allSatisfy { componentPiece(of: $0) != nil }
    }

    /// Dresses each of these in a saved style, each in the way that STICKS
    /// where it is: the words inside a copy become that copy's own answer,
    /// everything else is bound to the name the ordinary way.
    ///
    /// One call, because a drop is aimed rather than typed: the pointer named
    /// some words and should not have to know whether they turned out to
    /// belong to a copy. Returns whether anything was dressed.
    @discardableResult
    public mutating func applyTextStyle(_ styleID: UUID, to ids: [UUID]) -> Bool {
        guard textStyle(id: styleID) != nil else { return false }
        var dressed = false
        var plain: [UUID] = []
        for id in ids {
            if componentPiece(of: id) != nil {
                if setPieceTextStyle(of: id, styleID: styleID) { dressed = true }
            } else {
                plain.append(id)
            }
        }
        if !plain.isEmpty, bindTextStyle(layerIDs: plain, styleID: styleID) { dressed = true }
        return dressed
    }
}

// MARK: - Putting the answers on

extension PhotonzDocument {

    /// Writes a copy's own type onto the contents it has just been refilled
    /// with. Runs after the refill and after the knob answers, for the same
    /// reason they do: the original's picture whole, then the few facts the
    /// copy owns over the top.
    func applyPieceTextStyles(_ answers: [ComponentPieceTextStyle], to children: inout [Layer],
                              instance: UUID, contents: LayerPlacement?) {
        guard !answers.isEmpty else { return }
        for answer in answers {
            // What the name means TODAY, so a copy pointing at a saved style
            // follows every edit to it; the type it is wearing stands on its
            // own once the name is gone.
            let style = answer.styleID.flatMap { textStyle(id: $0) }
            let treatment = style?.treatment ?? answer.treatment
            let derived = ComponentIdentity.derived(instance: instance, source: answer.source)
            Self.mutate(id: derived, in: &children, contents: contents) { layer, holder in
                guard layer.textTreatment != nil else { return }
                // Bigger type needs a bigger box, exactly as longer words do:
                // a label hugging its words keeps hugging, and one somebody
                // narrowed into a paragraph keeps its wrap width.
                let hugging = layer.textHugsItsWords
                layer.setTextTreatment(treatment)
                layer.textStyleID = style == nil ? nil : answer.styleID
                // A text style keeps a colour of its own, so a colour style
                // the original's piece claimed would be a second name claiming
                // one colour. The text style wins, the same way it does on any
                // other piece of text.
                layer.unbindColorStyle(for: .text)
                layer = layer.textRefitted(
                    hugging: hugging,
                    anchor: LayerPlacement.resolving(child: layer.placement,
                                                     container: holder).horizontal)
            }
        }
    }

    /// Keeps every copy's own type honest after the shelf changes underneath
    /// it: a style that was edited leaves the answers pointing at it holding
    /// the new type, and one taken off the shelf leaves them holding exactly
    /// the type they were wearing, owned outright.
    ///
    /// Run from `deleteTextStyle` and `setTextStyle`, which are the only two
    /// ways the shelf moves under an answer.
    mutating func refreshPieceTextStyles() {
        guard holdsComponentInstance else { return }
        let styles = Dictionary(textStyles.map { ($0.id, $0.treatment) },
                                uniquingKeysWith: { first, _ in first })
        func walk(_ list: inout [Layer]) {
            for index in list.indices {
                if var group = list[index].group {
                    if !group.pieceTextStyles.isEmpty {
                        for slot in group.pieceTextStyles.indices {
                            guard let styleID = group.pieceTextStyles[slot].styleID else { continue }
                            if let treatment = styles[styleID] {
                                group.pieceTextStyles[slot].treatment = treatment
                            } else {
                                // The name is gone. The type it was wearing
                                // stays, and the copy owns it now: deleting a
                                // style must never re-set somebody's work.
                                group.pieceTextStyles[slot].styleID = nil
                            }
                        }
                    }
                    walk(&group.children)
                    list[index].content = .group(group)
                }
            }
        }
        walk(&layers)
    }
}
