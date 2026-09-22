import Foundation

/// What a layer says on its row in the layers list when it is one half of a
/// mask.
///
/// **The row has to say it, because the canvas cannot.** Cutting a layer to the
/// shape of the one under it (`LayerMatte`) spends that lower layer: it stops
/// drawing itself and becomes the shape instead. So one click on Masked by
/// takes a rectangle off the canvas while its row keeps its name, its
/// thumbnail and its eye, and the only way to find out where the rectangle went
/// was to undo. One line under each name closes it, on both rows, so the pair
/// can be read off the list without selecting anything:
///
///     Background   Masked by Rectangle
///     Rectangle    Mask for Background
///
/// It is the state of the PICTURE and not the setting: a layer whose eye is
/// shut draws nothing either way, and a mask whose owner is hidden is not
/// cutting anything, so neither row says anything then. That is the same rule
/// the renderer composites by (`DocumentRenderer.compositeLayers`), which is
/// what makes the line trustworthy.
public struct LayerMaskNote: Hashable, Sendable {

    /// Which half of the pair this row is.
    public enum Role: String, Hashable, Sendable, CaseIterable {
        /// This layer IS the shape. The layer directly above it is cut to it,
        /// so this one draws none of its own pixels.
        case theMask
        /// This layer is the one being cut, to the shape or the brightness of
        /// the layer directly under it.
        case wearingOne
    }

    public let role: Role
    /// What is being borrowed: the lower layer's shape, or its brightness.
    public let matte: LayerMatte
    /// The other layer of the pair, in the words the list is calling it.
    public let otherName: String

    public init(role: Role, matte: LayerMatte, otherName: String) {
        self.role = role
        self.matte = matte
        self.otherName = otherName
    }

    /// The line the row prints under its name.
    ///
    /// The other layer's name is IN it, so the pair reads off the list rather
    /// than being two rows you have to work out are related. The meaning is in
    /// the first two words, which is what a narrow row keeps when it cuts the
    /// tail off a long name: `SeparationLeftover` measured this slot at about
    /// eighteen characters once the thumbnail, the padlock and the eye have
    /// taken theirs, and the hover carries the whole of it.
    public var text: String {
        switch role {
        case .theMask: "Mask for \(otherName)"
        case .wearingOne: "Masked by \(otherName)"
        }
    }

    /// The sentence there is no room for on the row: what happened to the
    /// picture, and where the control that undoes it lives.
    public var help: String {
        switch role {
        case .theMask:
            "\(otherName), above, is cut to this layer's \(matte.borrowedThing). "
                + "That spends this layer: it is not drawn on its own any more, it is the "
                + "shape of the picture. Set Masked by back to Nothing on \(otherName) to "
                + "bring it back."
        case .wearingOne:
            "Cut to the \(matte.borrowedThing) of \(otherName), the layer directly under it, "
                + "which is why \(otherName) has stopped drawing itself. Masked by, in this "
                + "layer's own properties, is where that is turned off."
        }
    }
}

extension LayerMaskNote {

    /// What the layer at `index` of one sibling list has to say about masks,
    /// or nothing at all, which is the answer on nearly every row.
    ///
    /// `naming` is how the list is calling a layer right now, which is not
    /// always its stored name: a piece of text nobody has renamed says its own
    /// words (`Layer.displayName`).
    ///
    /// Being spent as somebody's mask wins over wearing one, for stacks three
    /// deep where the middle layer does both. The renderer agrees: a layer it
    /// skips draws nothing, so its own Masked by changes no pixel, and a row
    /// saying "Masked by" about a layer that is not in the picture would be the
    /// more confusing of the two truths.
    public static func forRow(in list: [Layer], at index: Int,
                              naming: (Layer) -> String) -> LayerMaskNote? {
        let layer = list[index]
        // A layer with its eye shut is not in the picture whatever the stack
        // says, so neither half of the pair is happening to it.
        guard layer.isVisible else { return nil }
        if let above = PhotonzDocument.matteUser(in: list, at: index),
           let matte = above.style.matte {
            return LayerMaskNote(role: .theMask, matte: matte, otherName: naming(above))
        }
        if let matte = layer.style.matte,
           let below = PhotonzDocument.matteSource(in: list, at: index) {
            return LayerMaskNote(role: .wearingOne, matte: matte, otherName: naming(below))
        }
        return nil
    }
}
