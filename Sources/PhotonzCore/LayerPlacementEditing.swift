import CoreGraphics
import Foundation

/// Setting where a piece sits when its container is resized: the container's
/// default, and one piece's override of it.
///
/// Both are one-field edits that change nothing on screen until the container
/// is next resized, which is exactly what makes them safe to set in advance:
/// you say what a button's label does, and then it does it forever.
/// See `docs/design/ui-building.md`, "Resizing places the pieces".
extension PhotonzDocument {

    /// What a group tells everything inside it to do, one axis at a time.
    /// Passing nil for an axis clears the default for that axis, which puts it
    /// back to the proportional multiply.
    public mutating func setContentPlacement(id: UUID, horizontal: HorizontalPlacement?) {
        setContentPlacement(id: id) { $0.horizontal = horizontal }
    }

    public mutating func setContentPlacement(id: UUID, vertical: VerticalPlacement?) {
        setContentPlacement(id: id) { $0.vertical = vertical }
    }

    private mutating func setContentPlacement(id: UUID,
                                              _ change: (inout LayerPlacement) -> Void) {
        guard let group = layer(id: id)?.group else { return }
        var placement = group.contentPlacement ?? LayerPlacement()
        change(&placement)
        updateLayer(id: id) { layer in
            var group = group
            group.children = layer.children
            group.contentPlacement = placement.normalized
            layer.content = .group(group)
        }
    }

    /// What ONE piece does, overriding whatever its container says. Passing nil
    /// for an axis hands that axis back to the container.
    ///
    /// Telling TEXT to stretch also moves its words to the middle of the box
    /// they now fill, unless they have been given a place of their own, so the
    /// choice does something the moment it is made rather than widening an
    /// invisible box. One edit, one undo. See `Layer.textAlignedToFill`.
    public mutating func setPlacement(id: UUID, horizontal: HorizontalPlacement?) {
        guard let layer = layer(id: id) else { return }
        let next = layer.settingPlacement(horizontal: horizontal)
        let filled = layer.textAlignedToFill(horizontal: horizontal)
        updateLayer(id: id) {
            $0.placement = next
            if let filled { $0.content = .text(filled) }
        }
    }

    public mutating func setPlacement(id: UUID, vertical: VerticalPlacement?) {
        guard let layer = layer(id: id) else { return }
        let next = layer.settingPlacement(vertical: vertical)
        let filled = layer.textAlignedToFill(vertical: vertical)
        updateLayer(id: id) {
            $0.placement = next
            if let filled { $0.content = .text(filled) }
        }
    }

    /// The group a layer sits in, or nil when it sits loose on the canvas —
    /// which is also the answer to "is there a container to line this up in".
    public func containingGroup(of id: UUID) -> Layer? {
        parentID(of: id).flatMap { layer(id: $0) }
    }
}
