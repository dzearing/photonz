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

    /// Down the box, where a group that stops stretching its contents also has
    /// to hand every text box's height back: a label still at the height of the
    /// row it used to fill has no handle and no field that could shrink it.
    public mutating func setContentPlacement(id: UUID, vertical: VerticalPlacement?) {
        // A copy's contents are its original's, down to where they sit, so
        // nothing is released either: the answer never lands.
        guard ownsContentRules(id: id) else { return }
        let released = vertical == .stretch ? [] : textsReleasedFromFill(in: id)
        setContentPlacement(id: id) { $0.vertical = vertical }
        for (child, box) in released { updateLayer(id: child) { $0.frame = box } }
    }

    /// The text directly inside this group that is filling its height because
    /// the GROUP says so rather than because it says so itself, each with the
    /// box it goes back to. Text with a rule of its own is left alone: that
    /// rule still says stretch, and it is not what just changed.
    private func textsReleasedFromFill(in id: UUID) -> [(UUID, CGRect)] {
        guard let group = layer(id: id),
              group.group?.contentPlacement?.vertical == .stretch else { return [] }
        return group.children.compactMap { child in
            guard child.placement?.vertical == nil,
                  let box = child.textReleasedFromFill else { return nil }
            return (child.id, box)
        }
    }

    private mutating func setContentPlacement(id: UUID,
                                              _ change: (inout LayerPlacement) -> Void) {
        // A copy is refilled from its original after every edit, and that
        // includes what it tells its contents to do, so an answer typed here
        // would be gone by the next redraw. It is refused instead, and the
        // Layout section says who owns it.
        guard let group = layer(id: id)?.group, ownsContentRules(id: id) else { return }
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

    /// Down the box the same edit runs backwards too: text that STOPS filling
    /// the height goes back to the height of its words, because nothing else
    /// could ever give that height back (`Layer.textReleasedFromFill`).
    public mutating func setPlacement(id: UUID, vertical: VerticalPlacement?) {
        guard let layer = layer(id: id) else { return }
        let next = layer.settingPlacement(vertical: vertical)
        let filled = layer.textAlignedToFill(vertical: vertical)
        let released = vertical != .stretch && layer.placement?.vertical == .stretch
            ? layer.textReleasedFromFill : nil
        updateLayer(id: id) {
            $0.placement = next
            if let filled { $0.content = .text(filled) }
            if let released { $0.frame = released }
        }
    }

    /// Telling ONE piece to take the room the stack it is in has left over
    /// along the way that stack runs, or telling it to stop.
    ///
    /// Stopping hands back the size the piece had before it started filling,
    /// and nothing else could: the flow writes the size it worked out straight
    /// into the piece, so without this a button tried at Fill for a second
    /// would be stuck at whatever the room made it, with nobody left who
    /// remembers what it was. One edit, one undo.
    ///
    /// Words are the exception down a column: their height is however tall
    /// they came out, so they are handed back to their own measurement rather
    /// than to a number remembered from before (`Layer.textReleasedFromFill`).
    public mutating func setFillsTheFlow(id: UUID, _ fills: Bool) {
        guard let layer = layer(id: id), fills != layer.fillsTheFlow else { return }
        let across = containingGroup(of: id)?.group?.layout?.direction.isHorizontal ?? true
        updateLayer(id: id) { out in
            guard !fills else {
                out.flowFill = FlowFill(sizeBefore: out.frame.standardized.size)
                return
            }
            if let before = out.flowFill?.sizeBefore {
                let box = out.frame.standardized
                let back = CGRect(x: box.minX, y: box.minY,
                                  width: across ? before.width : box.width,
                                  height: across ? box.height : before.height)
                // Handed back BY the container, so a copy does not take the
                // width as a size of its own on the way past.
                out = out.resized(to: back, placedByContainer: true)
                if !across, let released = out.textReleasedFromFill { out.frame = released }
            }
            out.flowFill = nil
        }
    }

    /// The same three edits over EVERY picked layer, in one step that one undo
    /// puts back. Three buttons in a bar are told to stretch once rather than
    /// three times over, and each returns how many it reached so a caller can
    /// tell a no-op from an edit.
    @discardableResult
    public mutating func setPlacement(ids: [UUID], horizontal: HorizontalPlacement?) -> Int {
        var count = 0
        for id in ids where layer(id: id) != nil {
            setPlacement(id: id, horizontal: horizontal)
            count += 1
        }
        return count
    }

    @discardableResult
    public mutating func setPlacement(ids: [UUID], vertical: VerticalPlacement?) -> Int {
        var count = 0
        for id in ids where layer(id: id) != nil {
            setPlacement(id: id, vertical: vertical)
            count += 1
        }
        return count
    }

    @discardableResult
    public mutating func setFillsTheFlow(ids: [UUID], _ fills: Bool) -> Int {
        var count = 0
        for id in ids where layer(id: id)?.fillsTheFlow != fills {
            setFillsTheFlow(id: id, fills)
            count += 1
        }
        return count
    }

    /// The group a layer sits in, or nil when it sits loose on the canvas —
    /// which is also the answer to "is there a container to line this up in".
    public func containingGroup(of id: UUID) -> Layer? {
        parentID(of: id).flatMap { layer(id: $0) }
    }
}
