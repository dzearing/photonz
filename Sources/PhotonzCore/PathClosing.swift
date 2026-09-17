import CoreGraphics
import Foundation

/// Shutting an outline you already finished (`docs/design/vector-paths.md`).
///
/// The Pen closes a path only WHILE you are drawing it, by clicking back on
/// the first point. Press Return and the run is open for good: there is no
/// inside, so it can never be filled, and somebody building an icon is exactly
/// the person who finishes an outline, looks at it and then wants it shut.
///
/// **It is not the join** (`PathJoining.swift`). The join welds the ends of
/// SEVERAL outlines to each other, and it only does so across a two point gap,
/// because welding two lines forty points apart by surprise is worse than not
/// welding at all. This acts on ONE outline's own two ends, asked for by name,
/// so the gap can be any size: you said close it, so it closes.
///
/// **Nothing moves.** The two ends stay exactly where they are and a straight
/// run is laid between them, so the picture only gains the run you asked for.
public enum PathClose {

    /// What the menu row says when the only thing picked is an open outline.
    ///
    /// The same row as Turn Into Path and Join Paths, retitled for what is
    /// picked: one row, one question, one undo step, and one place to learn
    /// that any of it exists. The ellipsis is the macOS promise that a
    /// question comes next.
    public static let menuItem = "Close Path\u{2026}"

    /// A distance written the way a sentence says it, so the question and the
    /// arithmetic cannot drift apart.
    public static func gapText(_ value: CGFloat) -> String { PathJoin.toleranceText(value) }
}

extension PathContent {

    /// This outline closed into a ring, or nil when closing it would enclose
    /// nothing.
    ///
    /// The refusal is the Pen's own: an outline that doubles back along its own
    /// line sweeps no area, and closing it would leave a layer on the canvas
    /// painting no pixels and findable only by hunting the layer list
    /// (`PenSession.flatCloseReason`).
    ///
    /// The run that closes the ring is STRAIGHT. A handle on the way in to the
    /// first anchor, or out of the last, shapes only that run, and on an open
    /// path that run does not exist — so those two handles are invisible
    /// before this and would bend the new run into a shape nobody drew. Every
    /// other handle on the outline is left exactly as it was.
    public func closingTheOutline() -> PathContent? {
        guard !isClosed, anchors.count >= 2, !hasSeveralRings else { return nil }
        var ring = self
        let head = anchors[0]
        let tail = anchors[anchors.count - 1]
        if head.point == tail.point {
            // The two ends already sit on the same spot, which is what a run
            // that was welded from several pieces can look like. One anchor,
            // not two on top of each other: the second would be a point you can
            // pick up and drag off a corner that has no corner in it.
            var joint = head
            joint.handleIn = tail.handleIn
            if joint.handleIn == nil, joint.handleOut == nil { joint.kind = .corner }
            ring.anchors[0] = joint
            ring.anchors.removeLast()
        } else {
            var start = head
            start.handleIn = nil
            if start.handleOut == nil { start.kind = .corner }
            var finish = tail
            finish.handleOut = nil
            if finish.handleIn == nil { finish.kind = .corner }
            ring.anchors[0] = start
            ring.anchors[ring.anchors.count - 1] = finish
        }
        ring.isClosed = true
        guard ring.anchors.count >= 2, ring.enclosesAnArea else { return nil }
        return ring
    }

    /// How far apart this outline's two ends are, which is the length of the
    /// run that closing it would lay between them. Zero for an outline whose
    /// ends already sit on the same spot.
    public var gapBetweenEnds: CGFloat {
        guard let head = anchors.first?.point, let tail = anchors.last?.point,
              anchors.count >= 2 else { return 0 }
        return PathJoin.distance(head, tail)
    }
}

// MARK: - What the command would do

/// What "Close Path" over a selection would leave behind, worked out before
/// anything changes so the question can say it in plain words.
///
/// Pure counting: it holds no layers and mutates nothing, so the copy that
/// hangs off it can be read in a test without an app around it.
public struct ClosePathPlan: Hashable, Sendable {
    /// How many picked outlines would close.
    public var closes: Int
    /// How many were refused because closing them would enclose nothing.
    public var refused: Int
    /// The widest gap a straight run has to cross, in document points. Zero
    /// when every outline's two ends already sit on the same spot.
    public var gap: CGFloat

    public init(closes: Int = 0, refused: Int = 0, gap: CGFloat = 0) {
        self.closes = closes
        self.refused = refused
        self.gap = gap
    }

    /// Whether the command would do anything at all.
    public var isEmpty: Bool { closes == 0 }
}

extension PhotonzDocument {

    /// The picked layers that are open outlines this command could close.
    ///
    /// Cheap on purpose: a menu asks it every time it opens, so it counts
    /// candidates and never walks their geometry. Whether closing one would
    /// actually enclose an area is the plan's business
    /// (`closingPaths(ids:)`), and the command is offered either way: a row
    /// dimmed because three points happen to be in a line teaches nobody what
    /// to do about it, where a refusal that names the reason teaches it once.
    ///
    /// Unlike the join, a TURNED path is welcome. The join reads one layer's
    /// anchors against another's, so a rotated layer is not where its numbers
    /// say it is; closing reads one outline against itself, and the run it
    /// lays is inside the box the outline already covers, so the layer neither
    /// moves nor changes size.
    public func openPathsThatCouldClose(ids: Set<UUID>) -> Set<UUID> {
        var found: Set<UUID> = []
        for id in ids {
            guard let candidate = layer(id: id), let outline = candidate.path,
                  !outline.isClosed, outline.anchors.count >= 2,
                  !outline.hasSeveralRings, !candidate.isLocked else { continue }
            found.insert(id)
        }
        return found
    }

    /// The document as "Close Path" would leave it, with the plan that says
    /// what happened.
    ///
    /// Each picked outline closes on its OWN two ends. Nothing is welded to
    /// anything else and no layer is swallowed, so every row in the list is
    /// still there afterwards wearing the name, the colour and the line it had.
    public func closingPaths(ids: Set<UUID>)
        -> (document: PhotonzDocument, plan: ClosePathPlan) {
        var next = self
        var plan = ClosePathPlan()
        for id in openPathsThatCouldClose(ids: ids).sorted(by: {
            (path(of: $0) ?? []).lexicographicallyPrecedes(path(of: $1) ?? [])
        }) {
            guard let outline = layer(id: id)?.path else { continue }
            guard let ring = outline.closingTheOutline() else {
                plan.refused += 1
                continue
            }
            plan.closes += 1
            plan.gap = max(plan.gap, outline.gapBetweenEnds)
            next.updateLayer(id: id) { layer in
                layer = PathBuilder.refit(layer, content: ring)
            }
        }
        return (next, plan)
    }

    /// Closes every picked open outline in ONE mutation, so the whole batch is
    /// one undo step (`closingPaths(ids:)` says what it would do first).
    @discardableResult
    public mutating func closePaths(ids: Set<UUID>) -> ClosePathPlan {
        let (next, plan) = closingPaths(ids: ids)
        self = next
        return plan
    }
}

// MARK: - The question it asks first

/// The question asked before an outline is closed.
///
/// It asks for the reason every other one-way turn in this family asks: the
/// canvas cannot show what is about to happen. A run laid across a gap of
/// forty points is a line that was not there a moment ago, and the outline
/// stops being a line and starts being a shape with an inside. Saying which,
/// with the gap in points, is the difference between a command that worked and
/// a command you have to take on trust.
///
/// Pure copy: it holds a `ClosePathPlan` and nothing else, so every sentence
/// can be read in a test without an app around it.
public struct ClosePathQuestion: Hashable, Sendable {
    public var plan: ClosePathPlan

    /// The question for this selection, or nil when nothing would close.
    public init?(plan: ClosePathPlan) {
        guard !plan.isEmpty else { return nil }
        self.plan = plan
    }

    public var title: String {
        switch plan.closes {
        case 1: return "Close this path?"
        case 2: return "Close both paths?"
        default: return "Close these \(plan.closes) paths?"
        }
    }

    /// What is about to appear, then what does NOT happen, then what you gain,
    /// then the way back.
    public var message: String {
        var parts: [String] = []
        if plan.gap > 0 {
            parts.append(plan.closes == 1
                ? "A straight run joins its two ends, \(PathClose.gapText(plan.gap)) apart."
                : "A straight run joins each one's two ends, "
                    + "the widest \(PathClose.gapText(plan.gap)) across.")
            parts.append(plan.closes == 1 ? "Neither end moves." : "No end moves.")
        } else {
            parts.append(plan.closes == 1
                ? "Its two ends are already in the same place, so nothing moves."
                : "Their ends are already in the same place, so nothing moves.")
        }
        parts.append(plan.closes == 1
            ? "The outline closes, so you can paint inside it."
            : "The outlines close, so you can paint inside them.")
        parts.append("Undo puts it back.")
        return parts.joined(separator: " ")
    }

    /// The button carries the verb, so somebody reading only the buttons still
    /// knows which one does the thing.
    public var confirm: String { plan.closes == 1 ? "Close Path" : "Close Paths" }
    public var cancel: String { "Cancel" }
}
