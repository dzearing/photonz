import CoreGraphics
import Foundation

/// Which separated piece sits inside which.
///
/// Separating a screenshot hands back a pile of pieces: boxes and runs of text,
/// each with a rectangle. A pile is not what the screen looked like. A label
/// that sits in a button is PART of that button, and the whole point of taking
/// the screenshot apart is to be able to pick the button up and have its label
/// come with it.
///
/// The rule, in one sentence: **a piece belongs to the smallest thing that
/// holds it.** Everything else here is what "holds" means when a cut is a
/// pixel or two generous, and what happens when nothing holds it.
///
/// This is the same judgement the measure tool already makes when it decides
/// that words centred in a rung not much taller than they are belong to that
/// rung rather than being an element of their own
/// (`ElementBounds.captionHeightRatio`) — reached from the other end. There the
/// question is what the pointer means; here it is what the layers list should
/// read like. Both answer it the same way: the label is the button's.
///
/// Nothing here knows what a piece IS. It takes rectangles and gives back a
/// tree of indices into them, so the same rule serves a run of text, a box, and
/// whatever a later slice finds.
///
/// Full design: `docs/design/separate-into-layers.md`.
public enum LayerNesting {

    /// One piece and everything that sits on it. `index` points back into the
    /// list handed to `nest`.
    public struct Node: Equatable, Sendable {
        public let index: Int
        public var children: [Node]

        public init(index: Int, children: [Node] = []) {
            self.index = index
            self.children = children
        }
    }

    /// How much of a piece has to sit inside something before that thing can be
    /// its parent. Not 100%, because the cut is deliberately generous: a run of
    /// text is grown by a halo before it is taken, so a label that filled its
    /// button edge to edge comes back a pixel or two proud of it and would
    /// otherwise be orphaned by arithmetic rather than by anything a person can
    /// see.
    ///
    /// Nine tenths is far enough from a half that a piece straddling the seam
    /// between two cards is refused by both, which is the property that matters:
    /// a piece is in exactly one place or in none, never in two.
    public static let minimumInsideShare = 0.9

    /// The pieces arranged the way the screen was, outermost first.
    ///
    /// Order is preserved inside every level, so the stacking order the
    /// separator chose — boxes first, then the words that sit on them — is the
    /// stacking order that comes out.
    ///
    /// The tree stops at `SeparateBudget.maxDepth` levels. Nothing is lost when
    /// it does: a piece deeper than that joins the deepest group that holds it,
    /// so it still travels with the thing a person would drag, and the layers
    /// list never indents a row further in than the twist that opens it.
    public static func nest(_ rects: [CGRect]) -> [Node] {
        let boxes = rects.map { $0.standardized }
        let areas = boxes.map { $0.width * $0.height }

        // The smallest thing that holds it. Strictly smaller candidates, and
        // strictly smaller than the candidate itself, so the parent relation
        // can never cycle and two identical rectangles never swallow each
        // other.
        var parent = [Int?](repeating: nil, count: boxes.count)
        for child in boxes.indices where areas[child] > 0 {
            var best: Int?
            for candidate in boxes.indices where candidate != child {
                guard areas[candidate] > areas[child], holds(boxes[candidate], boxes[child])
                else { continue }
                if let current = best, areas[current] <= areas[candidate] { continue }
                best = candidate
            }
            parent[child] = best
        }

        // Indices into a tree, keeping each level in the order it came in.
        var children = [[Int]](repeating: [], count: boxes.count)
        var roots: [Int] = []
        for index in boxes.indices {
            if let parent = parent[index] { children[parent].append(index) } else { roots.append(index) }
        }
        // At the last level a group is allowed, everything still under it comes
        // in as ONE flat row of children rather than a ladder nobody can see
        // the end of.
        func build(_ index: Int, level: Int) -> Node {
            guard level < SeparateBudget.maxDepth - 1 else {
                return Node(index: index, children: descendants(of: index, in: children)
                    .map { Node(index: $0) })
            }
            return Node(index: index, children: children[index].map { build($0, level: level + 1) })
        }
        return roots.map { build($0, level: 1) }
    }

    /// Everything under `index`, in the order the levels came in.
    private static func descendants(of index: Int, in children: [[Int]]) -> [Int] {
        children[index].flatMap { [$0] + descendants(of: $0, in: children) }
    }

    /// How many levels deep a forest goes. Zero for nothing at all.
    public static func depth(of nodes: [Node]) -> Int {
        nodes.reduce(0) { max($0, 1 + depth(of: $1.children)) }
    }

    /// Whether `outer` holds enough of `inner` to be its parent: nine tenths of
    /// the piece's own area, so a cut that ran a pixel or two wide still lands
    /// where a person would put it and a piece hanging halfway out lands
    /// nowhere.
    static func holds(_ outer: CGRect, _ inner: CGRect) -> Bool {
        let area = inner.width * inner.height
        guard area > 0 else { return false }
        let shared = outer.intersection(inner)
        guard !shared.isNull else { return false }
        return shared.width * shared.height >= minimumInsideShare * area
    }
}
