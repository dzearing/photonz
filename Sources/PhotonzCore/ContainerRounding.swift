import CoreGraphics
import Foundation

/// What Corner Radius means over a GROUP.
///
/// A group draws no outline of its own, so it rounds the only way a container
/// can: by masking its corners off. A mask can cut a corner away and it can
/// never put a curve back, which is the whole of the problem this file fixes.
///
/// Pick a group holding a button rounded 18 and the old row read the group's
/// own mask — nought — with the knob at the far left, beside a button that was
/// plainly round. Worse than the wrong number, the first stretch of the pull
/// did nothing: from 0 to 18 the mask was still cutting less than the button's
/// own curve, so the canvas sat perfectly still, and only past 18 did the
/// button start to round. The row was never dead, it was OFFSET. It counted
/// from a box nobody can see.
///
/// So the row reads what is drawn at the group's corners and stops where the
/// contents already are:
///
/// - **Reading** — the group's own mask and the curve its contents already
///   have, whichever cuts more. That is the curve on screen.
/// - **Bottom stop** — the curve its contents already have. There is nothing
///   under it to pull down to, so the knob does not go there.
/// - **Writing** — only a number that does something. Pulled back down to the
///   contents' own curve, the group is left carrying no mask at all, so
///   squaring the button later squares the group with it rather than leaving it
///   clipped to a curve nobody chose.
///
/// Nothing here touches a shape that rounds its own outline, or a picture with
/// a mask on it: neither has anything inside it, so both read and write exactly
/// as they always did.
extension Layer {

    /// This container's own box, in the space its children are placed in.
    ///
    /// `localBounds` answers in the PARENT's space, which is one origin too far
    /// out to compare a child against, so the container's own origin comes back
    /// off. A frame lands at the origin, a group that hugs lands wherever its
    /// contents put it.
    var contentsBox: CGRect {
        let box = localBounds
        return CGRect(x: box.minX - frame.origin.x, y: box.minY - frame.origin.y,
                      width: box.width, height: box.height)
    }

    /// The curve already painted at this container's corners by whatever is
    /// inside it, and `.none` for anything that is not a container.
    ///
    /// Only a child that covers the container's whole box can put a curve on
    /// its corners, which in practice is the backing shape: group a rounded
    /// rectangle with a label on top and the rectangle IS the group's box.
    /// Where the corners are held by different things, or by nothing, there is
    /// no one curve that is true of the box and the answer is square.
    public var containedCornerRadii: CornerRadii {
        guard let group else { return .none }
        let box = contentsBox
        guard box.width > 0, box.height > 0 else { return .none }
        // Later children draw on top, so the last one covering the box is the
        // one whose corners you can actually see.
        for child in group.children.reversed() where child.isVisible {
            let childBox = child.localBounds
            guard childBox.covers(box) else { continue }
            return child.boxCornerRadii(boxSize: childBox.size).fitted(in: box.size)
        }
        return .none
    }

    /// How round this layer's corners LOOK: its own rounding, and whatever is
    /// inside it, whichever cuts more.
    ///
    /// `style` is passed in so a caller previewing a drag reads what is on
    /// screen rather than what is on disk, exactly as `roundedCornerRadii`
    /// does.
    public func shownCornerRadii(style: LayerStyle) -> CornerRadii {
        let own = roundedCornerRadii(style: style)
        let inside = containedCornerRadii
        guard inside.isRound else { return own }
        return own.takingTheLargerOf(inside)
    }

    /// The lowest number the Corner Radius row can mean over this layer. Nought
    /// for everything that rounds itself; for a container, the curve its
    /// contents already have, because it can cut a corner off and never put one
    /// back.
    public var cornerRadiusFloor: CornerRadii { containedCornerRadii }
}

extension CornerRadii {

    /// Corner by corner, whichever of the two cuts more. What you SEE where a
    /// mask and the shape under it both round the same box.
    func takingTheLargerOf(_ other: CornerRadii) -> CornerRadii {
        CornerRadii(topLeft: Swift.max(topLeft, other.topLeft),
                    topRight: Swift.max(topRight, other.topRight),
                    bottomRight: Swift.max(bottomRight, other.bottomRight),
                    bottomLeft: Swift.max(bottomLeft, other.bottomLeft))
    }

    /// The part of these radii that would actually do something over `floor`:
    /// a corner already rounder than the number asked for is left alone at
    /// nought, so the container carries no mask that cuts nothing.
    func doingSomethingOver(_ floor: CornerRadii) -> CornerRadii {
        CornerRadii(topLeft: topLeft > floor.topLeft ? topLeft : 0,
                    topRight: topRight > floor.topRight ? topRight : 0,
                    bottomRight: bottomRight > floor.bottomRight ? bottomRight : 0,
                    bottomLeft: bottomLeft > floor.bottomLeft ? bottomLeft : 0)
    }
}

extension CGRect {

    /// True when this box covers all of `other`, give or take the half point
    /// that rounding a drag to the grid can leave behind.
    func covers(_ other: CGRect, slack: CGFloat = 0.5) -> Bool {
        minX <= other.minX + slack && minY <= other.minY + slack
            && maxX >= other.maxX - slack && maxY >= other.maxY - slack
    }
}
