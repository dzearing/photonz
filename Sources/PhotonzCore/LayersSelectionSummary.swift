import Foundation

/// The one line under the layers list: how many layers are picked, and how
/// many of them the list has no row for.
///
/// Almost every selection is the rows you can see highlighted, and then this
/// says what it has always said. The exception is a copy of a component: what
/// is inside a copy belongs to its original, so the list never gives those
/// pieces rows (`panelRows`) — and Select What Uses This is allowed to pick
/// them anyway, because "everywhere this colour is worn" has to mean
/// everywhere. That is how the list came to read "4 layers selected" over two
/// highlighted rows, which is the app counting something you cannot see and
/// not saying so.
///
/// A layer inside a SHUT group is not the same case and is deliberately not
/// counted here: its row exists and a twist brings it into view, so the
/// numbers only look apart until you open the group. A piece inside a copy has
/// no row to open at all.
public struct LayersSelectionSummary: Hashable, Sendable {
    /// How many layers are picked altogether, which is the number the list has
    /// always shown.
    public let count: Int
    /// How many of those are pieces inside a copy, and so have no row.
    public let insideCopies: Int
    /// How many copies those pieces are spread across, which only decides
    /// whether the sentence says "a copy" or "copies".
    public let copiesReached: Int

    public init(count: Int, insideCopies: Int, copiesReached: Int) {
        self.count = count
        self.insideCopies = insideCopies
        self.copiesReached = copiesReached
    }

    /// The words the list shows, or nil when there is nothing to say: one
    /// layer picked is described by the whole panel around it, and none at all
    /// by the empty panel.
    public var text: String? {
        guard count >= 2 else { return nil }
        let picked = "\(count) layers selected"
        guard insideCopies > 0 else { return picked }
        let copy = copiesReached == 1 ? "a copy" : "copies"
        let many = insideCopies == count ? "all" : "\(insideCopies)"
        return "\(picked), \(many) inside \(copy)"
    }
}

extension PhotonzDocument {

    /// What the layers list says about this selection.
    ///
    /// `count` is the selection exactly as it is held, an id this document has
    /// never heard of included, so the number cannot start disagreeing with
    /// the rest of the app over a layer that has just been deleted.
    public func layersSelectionSummary(picked ids: Set<UUID>) -> LayersSelectionSummary {
        var insideCopies = 0
        var copies: Set<UUID> = []
        // The copy a layer is inside is the OUTERMOST one, because that is the
        // one with a row: a copy nested in a copy is as rowless as any other
        // piece, and saying the selection reached two copies when the person
        // can see one would be a second number nobody could check.
        func walk(_ list: [Layer], copy: UUID?) {
            for layer in list {
                if let copy, ids.contains(layer.id) {
                    insideCopies += 1
                    copies.insert(copy)
                }
                let inside = copy ?? (layer.isComponentInstance ? layer.id : nil)
                walk(layer.children, copy: inside)
            }
        }
        walk(layers, copy: nil)
        return LayersSelectionSummary(count: ids.count, insideCopies: insideCopies,
                                      copiesReached: copies.count)
    }
}
