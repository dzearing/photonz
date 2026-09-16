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
        // Later children draw on top, so the last one whose corners ARE the
        // box's corners is the one whose curve you can actually see. A child
        // bigger than the box is not that child: its own curve is outside the
        // box altogether, and what meets the box's corners is the middle of
        // it, which is square. That is the everyday case inside a card that
        // crops, where a photo is deliberately larger than what is shown of
        // it.
        for child in group.children.reversed() where child.isVisible {
            let childBox = child.localBounds
            guard childBox.matches(box) else { continue }
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

    /// True when this box is the same box as `other`, give or take the half
    /// point that rounding a drag to the grid can leave behind.
    func matches(_ other: CGRect, slack: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= slack && abs(minY - other.minY) <= slack
            && abs(maxX - other.maxX) <= slack && abs(maxY - other.maxY) <= slack
    }
}

// MARK: - Reaching through a group to what is inside it

/// Where a mask stops, the pull reaches.
///
/// Masking works only where the group's contents are pressed against its
/// edges. Give the same button a caption under it, or put it in a stack with
/// padding, and the group's own corners are empty air: the row read 0, and
/// pulling it changed nothing on the canvas but the dashed selection marquee,
/// which goes away the moment you click elsewhere. Proven on a probe build on
/// 2026-09-12, pixel for pixel.
///
/// The user settled it on 2026-09-13: **the row rounds what is inside the
/// group**. So over a group the Corner Radius row is not about the group at
/// all. It speaks for the things inside it that have corners and paint them,
/// exactly as if those things had been picked instead — which is a rule
/// already in the app, since picking two boxes and pulling this row rounds
/// both.
///
/// Three containers are left exactly as they were:
///
/// - **A screen**, which has a box and a surface of its own, so its corners are
///   painted and rounding them is plainly visible.
/// - **A copy of a component**, which is rounded through its knob or not at
///   all; reaching inside one would write an override nobody asked for.
/// - **A group somebody already masked**, because a mask can only have got
///   there by being asked for and is not taken away underneath anybody. Pull it
///   back down off the group and the row starts reaching through from then on.
/// - **A card that CROPS**, told to cut off whatever sticks out past its edge.
///   That edge is drawn — it is the line a photo stops at — so it has corners
///   you can see, and the number rounds the curve it crops with. Reaching
///   through one rounded the photo and left the square crop to cut the rounded
///   photo back to a hard box, so the canvas never moved.
extension Layer {

    /// Whether anything is painted at this layer's OWN corners, so rounding it
    /// changes the picture. Words, a measurement and a path paint nothing
    /// there: a label's glyphs never reach the corners of its box, so a curve
    /// written onto one is a number that moves no pixel.
    var paintsItsOwnCorners: Bool {
        guard isVisible else { return false }
        switch content {
        case .annotation, .image, .collage, .lens, .zoomCallout: return true
        case .text, .measure, .path: return false
        // A container paints its corners when it has a surface behind its
        // contents, or a mask somebody asked for.
        // ...and when it crops, because the edge it crops at is a line you
        // can see and rounding it rounds what the crop cuts.
        case .group(let group):
            return group.background != nil || style.cornerRadii.isRound || clipsToBounds
        }
    }

    /// Whether the Corner Radius row reaches PAST this container to what is
    /// inside it, rather than masking the container itself.
    var roundingReachesItsContents: Bool {
        guard let group, !group.isFrame, !isComponentInstance, !clipsToBounds else { return false }
        return !style.cornerRadii.isRound && !group.children.isEmpty
    }

    /// Whether the Corner Radius row over this layer is rounding the edge it
    /// CROPS with, rather than a corner it paints or a corner inside it. What
    /// lets the row say so, since "this card cuts off what sticks out, so this
    /// rounds the edge it cuts with" is the whole difference between a number
    /// that works and a number you have to experiment with.
    public var roundingCropsItsContents: Bool {
        clipsToBounds && !isFrame && !isComponentInstance
    }

    /// The layers a pull on this container's Corner Radius row rounds: the
    /// things inside it that have corners and paint them, all the way down
    /// through any groups among them. Empty for everything that rounds itself,
    /// and for a container with nothing inside it that could show a curve, so
    /// the row falls back to masking the way it always did rather than going
    /// dead.
    public var roundableContents: [Layer] {
        guard roundingReachesItsContents, let group else { return [] }
        var reached: [Layer] = []
        for child in group.children where child.isVisible && !child.isLocked {
            if child.roundingReachesItsContents {
                reached += child.roundableContents
            } else if child.hasCorners && child.paintsItsOwnCorners {
                reached.append(child)
            }
        }
        return reached
    }
}
