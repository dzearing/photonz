import CoreGraphics
import Foundation

/// Reshaping a path that has already been drawn: picking a point up, pulling a
/// handle, turning a corner into a bend and back again, adding a point on a run
/// and taking one out (`docs/design/vector-paths.md`).
///
/// Every one of these is pure geometry on a value, so the canvas can apply one
/// to a copy, hand the result to `History.perform`, and get an undo step for
/// nothing. Nothing here knows about zoom except the hit test, which is the one
/// thing that has to think in screen distances.

// MARK: - Where a run is

extension PathSegment {

    /// Where this run is at `t`, from 0 at its start to 1 at its end.
    public func point(at t: CGFloat) -> CGPoint {
        CGPoint(x: Bezier.value(start.x, control1.x, control2.x, end.x, at: t),
                y: Bezier.value(start.y, control1.y, control2.y, end.y, at: t))
    }
}

// MARK: - What a press landed on

/// The piece of a path a press can catch.
public enum PathEditTarget: Hashable, Sendable {
    /// An anchor, by its place in the path.
    case anchor(Int)
    /// One end of one anchor's lever.
    case handle(anchor: Int, side: PathHandleSide)
    /// The outline itself, on the run at `index` and `at` of the way along it.
    /// A press here is where a new point goes.
    case segment(Int, at: CGFloat)
}

extension PathContent {

    /// How near a press has to get to an anchor or a handle, ON SCREEN, to
    /// catch it. The same eight points a resize handle and the Pen's own
    /// anchor target both use, so a dot means the same size everywhere.
    public static let editTargetRadius: CGFloat = 8

    /// How near a press has to get to the OUTLINE to land on it, on screen.
    /// Wider than an anchor because the line is what you aim at when you want
    /// a new point, and a curve is a thin thing to hit.
    public static let outlineTargetRadius: CGFloat = 6

    /// What a press at `point`, in the layer's own coordinates, has caught.
    ///
    /// Anchors first, because moving a point is what you came for and an
    /// anchor always sits ON the outline it would otherwise lose to. Handles
    /// next, and only for the anchors whose levers are actually on screen: a
    /// lever you cannot see is not a target, or a press in clear air near a
    /// shape would catch something invisible.
    public func editTarget(at point: CGPoint, zoom: CGFloat,
                           handlesShowing: Set<Int>) -> PathEditTarget? {
        let scale = zoom > 0 ? zoom : 1
        let dotReach = Self.editTargetRadius / scale
        var best: (target: PathEditTarget, distance: CGFloat)?
        func offer(_ target: PathEditTarget, _ at: CGPoint, within reach: CGFloat) {
            let d = hypot(point.x - at.x, point.y - at.y)
            guard d <= reach else { return }
            if let found = best, found.distance <= d { return }
            best = (target, d)
        }
        for (i, anchor) in anchors.enumerated() {
            offer(.anchor(i), anchor.point, within: dotReach)
        }
        if best != nil { return best?.target }
        for i in handlesShowing.sorted() {
            guard anchors.indices.contains(i) else { continue }
            let anchor = anchors[i]
            if anchor.handleIn != nil {
                offer(.handle(anchor: i, side: .handleIn), anchor.controlIn, within: dotReach)
            }
            if anchor.handleOut != nil {
                offer(.handle(anchor: i, side: .handleOut), anchor.controlOut, within: dotReach)
            }
        }
        if best != nil { return best?.target }
        guard let run = nearestRun(to: point, within: Self.outlineTargetRadius / scale) else {
            return nil
        }
        return .segment(run.index, at: run.t)
    }

    /// The run nearest `point` and how far along it the nearest spot is, or nil
    /// when nothing is within `reach`.
    ///
    /// The curve is walked in short steps rather than solved: a press is
    /// answered to within a fraction of a point either way, and being exact
    /// here would buy nothing — where a new anchor LANDS is exact, because the
    /// split is exact whatever `t` it is given.
    func nearestRun(to point: CGPoint, within reach: CGFloat,
                    steps: Int = 24) -> (index: Int, t: CGFloat, distance: CGFloat)? {
        var best: (index: Int, t: CGFloat, distance: CGFloat)?
        for (index, run) in segments.enumerated() {
            let count = run.isStraight ? 1 : steps
            var from = run.start
            for step in 1...count {
                let t1 = CGFloat(step) / CGFloat(count)
                let to = run.point(at: t1)
                let d = Geometry.distance(from: point, toSegmentFrom: from, to: to)
                if best == nil || d < best!.distance {
                    let t0 = CGFloat(step - 1) / CGFloat(count)
                    let along = Geometry.fraction(of: point, alongSegmentFrom: from, to: to)
                    best = (index, t0 + (t1 - t0) * along, d)
                }
                from = to
            }
        }
        guard let best, best.distance <= reach else { return nil }
        return best
    }

    // MARK: - Picking points up

    /// Moves every anchor named, leaving the rest where they are. Handles are
    /// offsets, so the curves either side travel with the point rather than
    /// being left behind.
    public mutating func moveAnchors(_ indices: Set<Int>, by delta: CGPoint) {
        for i in indices where anchors.indices.contains(i) {
            anchors[i].point = CGPoint(x: anchors[i].point.x + delta.x,
                                       y: anchors[i].point.y + delta.y)
        }
    }

    // MARK: - Pulling handles

    /// Puts one end of one anchor's lever at `control`, in the layer's own
    /// coordinates.
    ///
    /// On a smooth anchor the far handle swings round to stay in line, keeping
    /// its own length, which is the promise `smooth` makes. `breaking` is the
    /// Option key: it frees the two sides first, so the other one holds still
    /// and the point becomes a hard turn.
    public mutating func setHandle(anchor index: Int, side: PathHandleSide,
                                   control: CGPoint, breaking: Bool = false) {
        guard anchors.indices.contains(index) else { return }
        var anchor = anchors[index]
        if breaking { anchor.kind = .corner }
        let offset = CGPoint(x: control.x - anchor.point.x, y: control.y - anchor.point.y)
        if side == .handleIn { anchor.handleIn = offset } else { anchor.handleOut = offset }
        anchor.alignHandles(keeping: side)
        anchors[index] = anchor
    }

    /// Pulls one side's handle in, so the run on that side goes straight. The
    /// other side keeps its curve, which is a point that is curved on one side
    /// and straight on the other: the commonest thing in a real icon.
    public mutating func clearHandle(anchor index: Int, side: PathHandleSide) {
        guard anchors.indices.contains(index) else { return }
        if side == .handleIn { anchors[index].handleIn = nil } else { anchors[index].handleOut = nil }
        // A promise to keep two handles in line means nothing with one left.
        anchors[index].kind = .corner
    }

    // MARK: - Corner and smooth

    /// Turns a corner into a smooth bend, or a bend back into a hard corner,
    /// whichever this point is not. Hands back what it became.
    @discardableResult
    public mutating func toggleAnchorKind(at index: Int) -> PathAnchorKind? {
        guard anchors.indices.contains(index) else { return nil }
        if anchors[index].kind == .smooth { makeCorner(at: index) } else { makeSmooth(at: index) }
        return anchors[index].kind
    }

    /// Gives a point two handles in line with each other, so the outline runs
    /// through it without a kink.
    ///
    /// The line they take is the one from the point BEFORE to the point AFTER,
    /// which is what every drawing app smooths along. A side that already had
    /// a handle keeps its length, so joining a broken point back up does not
    /// also flatten the curve somebody drew.
    public mutating func makeSmooth(at index: Int) {
        guard anchors.indices.contains(index) else { return }
        let before = neighbour(of: index, step: -1)
        let after = neighbour(of: index, step: 1)
        // With nothing either side there is no line to lie along, so the point
        // is left exactly as it is rather than sprouting handles from nowhere.
        guard before != nil || after != nil else { return }
        var anchor = anchors[index]
        let from = before?.point ?? anchor.point
        let to = after?.point ?? anchor.point
        var direction = CGPoint(x: to.x - from.x, y: to.y - from.y)
        var span = hypot(direction.x, direction.y)
        if span <= 0 {
            // The two neighbours sit on top of each other: fall back to the
            // way the outline leaves this point.
            direction = CGPoint(x: to.x - anchor.point.x, y: to.y - anchor.point.y)
            span = hypot(direction.x, direction.y)
            guard span > 0 else { return }
        }
        let unit = CGPoint(x: direction.x / span, y: direction.y / span)
        func length(_ handle: CGPoint?, toward neighbour: PathAnchor?) -> CGFloat? {
            if let handle { return hypot(handle.x, handle.y) }
            guard let neighbour else { return nil }
            return hypot(neighbour.point.x - anchor.point.x,
                         neighbour.point.y - anchor.point.y) / 3
        }
        if let out = length(anchor.handleOut, toward: after) {
            anchor.handleOut = CGPoint(x: unit.x * out, y: unit.y * out)
        }
        if let into = length(anchor.handleIn, toward: before) {
            anchor.handleIn = CGPoint(x: -unit.x * into, y: -unit.y * into)
        }
        anchor.kind = .smooth
        anchors[index] = anchor
    }

    /// Turns a point into a hard corner: both handles come off, so both sides
    /// run straight. What "convert to corner" means in every drawing app.
    public mutating func makeCorner(at index: Int) {
        guard anchors.indices.contains(index) else { return }
        anchors[index].handleIn = nil
        anchors[index].handleOut = nil
        anchors[index].kind = .corner
    }

    /// The anchor one step either side of `index`, wrapping round the end of
    /// its OWN ring on a closed path and running out at the ends of an open
    /// one.
    ///
    /// Within the ring, because the anchor after the last one on the rim is
    /// the rim's own first anchor, never the first anchor of the hole.
    private func neighbour(of index: Int, step: Int) -> PathAnchor? {
        guard let (_, range) = ring(containing: index), range.count > 1 else { return nil }
        let next = index + step
        if range.contains(next) { return anchors[next] }
        guard isClosed else { return nil }
        let span = range.count
        return anchors[range.lowerBound + ((next - range.lowerBound) % span + span) % span]
    }

    // MARK: - Adding a point

    /// Puts a new anchor on the run at `index`, `t` of the way along it, and
    /// hands back where it landed in the list.
    ///
    /// **The shape does not change.** Splitting a cubic at a parameter has an
    /// exact answer — de Casteljau — and the two halves it gives are the same
    /// curve written twice, to the last decimal place. Doing it approximately
    /// is immediately visible as the outline twitching under the pointer.
    ///
    /// A run that was STRAIGHT stays two straight runs: a handle that was
    /// absent stays absent rather than becoming a zero nobody can tell from a
    /// handle dragged all the way in.
    @discardableResult
    public mutating func insertAnchor(onSegment index: Int, at t: CGFloat) -> Int? {
        guard segments.indices.contains(index), let ends = segmentEnds(index) else { return nil }
        let t = min(max(t, 0), 1)
        let startIndex = ends.start
        let endIndex = ends.end
        let start = anchors[startIndex]
        let end = anchors[endIndex]
        let p0 = start.point, p1 = start.controlOut, p2 = end.controlIn, p3 = end.point
        func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let q0 = lerp(p0, p1), q1 = lerp(p1, p2), q2 = lerp(p2, p3)
        let r0 = lerp(q0, q1), r1 = lerp(q1, q2)
        func offset(_ from: CGPoint, _ to: CGPoint) -> CGPoint {
            CGPoint(x: to.x - from.x, y: to.y - from.y)
        }
        let straight = segments[index].isStraight
        // A straight run is a cubic with both control points sitting on its
        // ends, and THAT cubic does not travel at an even rate: splitting it at
        // a quarter lands at 15.6% of the way along the line, not 25%. A press
        // a quarter of the way down an edge means a quarter of the way down the
        // edge, so a straight run is split along the line itself.
        let middle = straight
            ? CGPoint(x: p0.x + (p3.x - p0.x) * t, y: p0.y + (p3.y - p0.y) * t)
            : lerp(r0, r1)
        var added = PathAnchor(point: middle)
        if !straight {
            added.handleIn = offset(middle, r0)
            added.handleOut = offset(middle, r1)
            added.kind = .smooth
        }
        // A handle that was not there stays not there: its control point is the
        // anchor itself, which is exactly where the split leaves it.
        if start.handleOut != nil { anchors[startIndex].handleOut = offset(p0, q0) }
        if end.handleIn != nil { anchors[endIndex].handleIn = offset(p3, q2) }
        anchors.insert(added, at: startIndex + 1)
        // Every ring that begins after the new point begins one anchor later.
        ringStarts = ringStarts.map { $0 > startIndex ? $0 + 1 : $0 }
        return startIndex + 1
    }

    /// Which two anchors the run at `index` in `segments` lies between.
    ///
    /// `segments` walks ring by ring, so its numbering only lines up with the
    /// anchor numbering on the first ring. On a shape with a hole in it the
    /// run's two ends have to be found by walking the rings, and the last run
    /// of a ring comes back to that ring's own first anchor.
    func segmentEnds(_ index: Int) -> (start: Int, end: Int)? {
        var remaining = index
        for range in ringRanges {
            let ring = anchors[range]
            guard ring.count >= 2 else { continue }
            let runs = ring.count - 1 + (isClosed ? 1 : 0)
            if remaining < runs {
                let start = range.lowerBound + remaining
                let end = remaining == ring.count - 1 ? range.lowerBound : start + 1
                return (start, end)
            }
            remaining -= runs
        }
        return nil
    }

    // MARK: - Taking a point out

    /// Takes the named points out, closing the curve over each gap. False when
    /// it would leave the path with fewer than two points, which is not a shape
    /// any more: deleting a whole path is the layer's business, not the
    /// outline's.
    ///
    /// The gap is closed by undoing the split that would have made this point:
    /// the two runs either side become one, with the outer handles stretched
    /// back to the lengths they had before the point was there. Where the point
    /// really was made by adding one, that puts the curve back exactly.
    @discardableResult
    public mutating func removeAnchors(_ indices: Set<Int>) -> Bool {
        let doomed = indices.filter { anchors.indices.contains($0) }.sorted(by: >)
        guard !doomed.isEmpty, anchors.count - doomed.count >= 2 else { return false }
        // Each RING has to keep at least two points of its own: a hole cannot
        // be worn down to one anchor and go on being a loop. A ring that would
        // be left with fewer is taken out whole, so deleting the last two
        // points of a hole fills the hole in rather than leaving a stub.
        var going = Set(doomed)
        for range in ringRanges {
            let left = range.count - range.filter { going.contains($0) }.count
            if left > 0 && left < 2 { going.formUnion(range) }
        }
        guard anchors.count - going.count >= 2 else { return false }
        for index in going.sorted(by: >) { removeOne(at: index) }
        return true
    }

    private mutating func removeOne(at index: Int) {
        let removed = anchors[index]
        let range = ring(containing: index)?.range ?? 0..<anchors.count
        let count = range.count
        let beforeIndex = index - 1 >= range.lowerBound
            ? index - 1 : (isClosed && count > 1 ? range.upperBound - 1 : nil)
        let afterIndex = index + 1 < range.upperBound
            ? index + 1 : (isClosed && count > 1 ? range.lowerBound : nil)
        if let beforeIndex, let afterIndex {
            // Where the point came from a split, `t` is written in its own two
            // handles: the point sits exactly that far along the line between
            // them (`insertAnchor`). Where it does not, the lengths of the runs
            // either side say the same thing well enough to look right.
            let t = splitParameter(of: removed, before: anchors[beforeIndex],
                                   after: anchors[afterIndex])
            if let out = anchors[beforeIndex].handleOut {
                anchors[beforeIndex].handleOut = CGPoint(x: out.x / t, y: out.y / t)
            }
            if let into = anchors[afterIndex].handleIn {
                anchors[afterIndex].handleIn = CGPoint(x: into.x / (1 - t),
                                                       y: into.y / (1 - t))
            }
        }
        anchors.remove(at: index)
        ringStarts = PathContent.tidyRingStarts(ringStarts.map { $0 > index ? $0 - 1 : $0 },
                                                count: anchors.count)
    }

    /// How far along the joined run the point being removed sat, between 0 and
    /// 1 and never so near either end that stretching a handle by its inverse
    /// runs away with the shape.
    private func splitParameter(of anchor: PathAnchor, before: PathAnchor,
                                after: PathAnchor) -> CGFloat {
        let t: CGFloat
        if let into = anchor.handleIn, let out = anchor.handleOut {
            let lengthIn = hypot(into.x, into.y)
            let lengthOut = hypot(out.x, out.y)
            t = lengthIn + lengthOut > 0 ? lengthIn / (lengthIn + lengthOut) : 0.5
        } else {
            let first = hypot(anchor.point.x - before.point.x, anchor.point.y - before.point.y)
            let second = hypot(after.point.x - anchor.point.x, after.point.y - anchor.point.y)
            t = first + second > 0 ? first / (first + second) : 0.5
        }
        return min(max(t, 0.05), 0.95)
    }
}

// MARK: - Putting the box back round the shape

extension PathBuilder {

    /// The layer with `content` on it and its box put back round the shape,
    /// after anchors have been moved about.
    ///
    /// Anchors are stored against the layer's own corner, so a point dragged
    /// out past the edge has to move the corner as well as the point, or the
    /// selection outline would sit across the middle of the shape and the
    /// numbers in the Position panel would stop meaning anything.
    public static func refit(_ layer: Layer, content: PathContent) -> Layer {
        let box = content.bounds
        var fitted = layer
        fitted.content = .path(content.offsetBy(dx: -box.origin.x, dy: -box.origin.y))
        fitted.frame = CGRect(x: layer.frame.origin.x + box.origin.x,
                              y: layer.frame.origin.y + box.origin.y,
                              width: box.width, height: box.height)
        return fitted
    }
}
