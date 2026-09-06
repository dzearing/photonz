import CoreGraphics
import Foundation

/// Why the layers list marks a row as out of view.
///
/// A container that cuts off what does not fit (`Layer.clipsToBounds`) makes
/// anything past its edge disappear completely: the canvas stops drawing it,
/// clicks go straight through where it used to be, and the layers list shows a
/// row that looks exactly like every other row. Somebody who drags a label a
/// little too far has lost it, with undo as the only way back.
///
/// So the row carries the one fact that was missing. Either this layer itself
/// has been cut off, and by which container, or the row is a shut group
/// speaking for what it is hiding, because a mark you have to open a group to
/// find is a mark nobody sees.
public struct RowOutOfView: Hashable, Sendable {
    /// The container cutting THIS layer off, named the way its row is named.
    /// Nil when the layer itself is in view and the row is only reporting for
    /// what is inside it.
    public let container: String?
    /// How many layers inside this SHUT group are out of view. Zero on an open
    /// group, whose own rows carry their own marks, and on a leaf.
    ///
    /// A group that is itself cut off counts as one, not as one per layer
    /// inside it: everything in it went the same way at the same moment, and a
    /// card reading "17 layers out of view" for one card nobody moved is noise.
    public let hiddenInside: Int

    public init(container: String?, hiddenInside: Int) {
        self.container = container
        self.hiddenInside = hiddenInside
    }
}

/// A clipping container's box, measured in the space of the layers it is
/// cutting off — that is, against the group's own corner, the same space its
/// children's frames are stored in.
struct ClipScope: Hashable, Sendable {
    var rect: CGRect
    var name: String

    /// The same box seen from one level further in, where child frames are
    /// stored against `origin` instead.
    func inside(_ origin: CGPoint) -> ClipScope {
        ClipScope(rect: rect.offsetBy(dx: -origin.x, dy: -origin.y), name: name)
    }
}

enum OutOfView {

    /// Whether `box` has nothing at all left inside `clip`.
    ///
    /// Deliberately not `!clip.intersects(box)`: an arrow drawn flat or a
    /// divider one point tall is an EMPTY rect, which intersects nothing, and
    /// marking every hairline in the document as out of view would be worse
    /// than saying nothing at all. Comparing the edges instead asks the
    /// question that matters — is every part of this past one side of the box.
    static func isOutside(_ box: CGRect, of clip: CGRect) -> Bool {
        let b = box.standardized, c = clip.standardized
        return b.maxX <= c.minX || b.minX >= c.maxX || b.maxY <= c.minY || b.minY >= c.maxY
    }

    /// The scopes in force for the layers INSIDE `layer`: everything already
    /// cutting `layer` seen from one level in, plus `layer`'s own box when it
    /// cuts off what does not fit.
    ///
    /// `box` is the layer's `localBounds`, passed in because the caller has
    /// already worked it out and it is not a cheap thing to ask for twice.
    static func scopes(inside layer: Layer, box: CGRect, under clips: [ClipScope]) -> [ClipScope] {
        let origin = layer.frame.origin
        var inner = clips.map { $0.inside(origin) }
        if layer.clipsToBounds {
            inner.append(ClipScope(rect: box.offsetBy(dx: -origin.x, dy: -origin.y),
                                   name: layer.name))
        }
        return inner
    }

    /// The container cutting `box` off, nearest first, or nil while any part of
    /// it is still on screen.
    ///
    /// Nearest wins because that is the box somebody would go and open: a label
    /// pushed out of a card inside a screen is the card's doing, and saying
    /// "Screen" would send them to the wrong place.
    static func cutter(of box: CGRect, under clips: [ClipScope]) -> String? {
        clips.last { isOutside(box, of: $0.rect) }?.name
    }

    /// How many layers under `clips` are out of view, counting a whole group
    /// that has gone as one. Used for the row of a SHUT group, which is the
    /// only row standing between somebody and a layer they cannot see.
    static func hiddenCount(in children: [Layer], under clips: [ClipScope]) -> Int {
        guard !clips.isEmpty else { return 0 }
        var count = 0
        for child in children {
            let box = child.localBounds
            if cutter(of: box, under: clips) != nil {
                count += 1
                continue
            }
            // A copy of a component is one object: what is inside it belongs to
            // its original, so nothing in there is somebody's lost layer.
            guard child.isOpenableGroup else { continue }
            count += hiddenCount(in: child.children,
                                 under: scopes(inside: child, box: box, under: clips))
        }
        return count
    }
}
