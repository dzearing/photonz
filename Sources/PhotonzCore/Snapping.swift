import CoreGraphics
import Foundation

/// Snapping for both ways of dragging a layer about: MOVING it, where its
/// edges and centres attract to the canvas edges and centre and to the edges
/// and centres of the other layers, and RESIZING it, where the edge under the
/// pointer attracts to the same things and the opposite one stays anchored.
/// Tolerance is expressed in screen points so the magnetic feel is constant at
/// any zoom level.
///
/// The canvas grid comes in underneath all of that, as a quantize rather than a
/// magnet: whatever nothing else caught lands on the nearest grid line. So a
/// grid never stops you matching a real edge, and away from real edges things
/// sit on the grid rather than near it.
///
/// A screen's COLUMNS come in as peers of their own (`FrameColumns`): each
/// column is one more box to line up with, so a column edge catches, holds,
/// releases and draws its line exactly the way another layer's edge does, and
/// ⌘ frees a drag from it with no new rule. The one difference is that a column
/// band feeds the sideways axis only. A column is a sideways idea; the top and
/// bottom of a band are the screen's own edges, and a box quietly sticking to
/// the top of the screen it happens to be over is not what anybody asked for.
/// With no columns showing anywhere — a screenshot, a plain canvas, a screen
/// with the switch off — the list is empty and every answer here is bit for bit
/// what it was before columns existed.
///
/// Peers are what makes this useful for building UI rather than annotating a
/// picture: a button dragged next to another button lines up with it, sits
/// flush against it, or centres on it, and the line that appears says which of
/// those just happened. The line only spans the boxes actually involved, so a
/// crowded canvas does not fill with full-height rules; a canvas edge or the
/// canvas centre still draws right across the picture, because that is what it
/// is lined up with.
public enum Snapping {
    /// How far a drawn guide reaches, in canvas points along the axis the line
    /// does NOT run down. Absent means the whole picture.
    public struct Span: Equatable, Sendable {
        public var start: CGFloat
        public var end: CGFloat

        public init(start: CGFloat, end: CGFloat) {
            self.start = start
            self.end = end
        }

        func union(_ other: Span) -> Span {
            Span(start: Swift.min(start, other.start), end: Swift.max(end, other.end))
        }
    }

    public struct Result: Equatable, Sendable {
        /// The (possibly snapped) frame origin.
        public var origin: CGPoint
        /// Canvas-space x of the vertical guide that captured, for drawing.
        public var guideX: CGFloat?
        /// Canvas-space y of the horizontal guide that captured.
        public var guideY: CGFloat?
        /// How far down the vertical guide reaches; nil means the whole picture.
        public var guideXSpan: Span?
        /// How far across the horizontal guide reaches; nil means all of it.
        public var guideYSpan: Span?
        /// The GRID line the point came to rest on down this axis, when the
        /// grid is what placed it. Nil when a real edge won instead, or when
        /// the grid is not pulling. Kept apart from `guideX` because the two
        /// mean different things and are drawn differently: a guide says "you
        /// lined up with that thing", a grid line says "you are on this line
        /// of the paper", and the canvas lights up the line already on screen
        /// rather than laying a second rule over it.
        public var gridX: CGFloat?
        /// The same for the horizontal grid line.
        public var gridY: CGFloat?

        public init(origin: CGPoint, guideX: CGFloat? = nil, guideY: CGFloat? = nil,
                    guideXSpan: Span? = nil, guideYSpan: Span? = nil,
                    gridX: CGFloat? = nil, gridY: CGFloat? = nil) {
            self.origin = origin
            self.guideX = guideX
            self.guideY = guideY
            self.guideXSpan = guideXSpan
            self.guideYSpan = guideYSpan
            self.gridX = gridX
            self.gridY = gridY
        }
    }

    /// The same answer for a RESIZE: which edges moved, where they came to
    /// rest, and the guides that say why.
    public struct FrameResult: Equatable, Sendable {
        /// The (possibly snapped) frame.
        public var frame: CGRect
        public var guideX: CGFloat?
        public var guideY: CGFloat?
        public var guideXSpan: Span?
        public var guideYSpan: Span?
        /// The grid line the dragged edge came to rest on. See `Result.gridX`.
        public var gridX: CGFloat?
        public var gridY: CGFloat?

        public init(frame: CGRect, guideX: CGFloat? = nil, guideY: CGFloat? = nil,
                    guideXSpan: Span? = nil, guideYSpan: Span? = nil,
                    gridX: CGFloat? = nil, gridY: CGFloat? = nil) {
            self.frame = frame
            self.guideX = guideX
            self.guideY = guideY
            self.guideXSpan = guideXSpan
            self.guideYSpan = guideYSpan
            self.gridX = gridX
            self.gridY = gridY
        }
    }

    /// `holding` carries the lines this drag is already standing on: one of
    /// them keeps the frame until the pointer is clearly away from it, so the
    /// guide you can see is the guide you get. See `SnapHold`.
    public static func snapFrameOrigin(_ proposed: CGPoint, size: CGSize, canvas: CGSize,
                                       peers: [CGRect] = [], columnBands: [CGRect] = [],
                                       gridSpacing: CGFloat? = nil,
                                       gridOrigin: CGPoint = .zero,
                                       gridAxes: CanvasGridAxes = .columnsAndRows,
                                       guides: [CanvasGuide] = [],
                                       zoom: CGFloat, screenTolerance: CGFloat = 8,
                                       holding held: SnapHold = .none) -> Result {
        let tolerance = zoom > 0 ? screenTolerance / zoom : screenTolerance
        // A grid set to columns draws no lines across, so there is nothing to
        // land on down that axis and nothing pulls there.
        let gridRows = gridAxes.drawsRows ? gridSpacing : nil
        let x = snapAxis(origin: proposed.x, length: size.width, canvasLength: canvas.width,
                         crossOrigin: proposed.y, crossLength: size.height,
                         peers: peers.map { Peer(along: ($0.minX, $0.maxX), cross: ($0.minY, $0.maxY)) }
                             + columnBands.map { Peer(along: ($0.minX, $0.maxX), cross: ($0.minY, $0.maxY)) },
                         guideLines: CanvasGuides.positions(guides, axis: .vertical),
                         gridSpacing: gridSpacing, gridOrigin: gridOrigin.x,
                         tolerance: tolerance, held: held.x)
        let y = snapAxis(origin: proposed.y, length: size.height, canvasLength: canvas.height,
                         crossOrigin: proposed.x, crossLength: size.width,
                         peers: peers.map { Peer(along: ($0.minY, $0.maxY), cross: ($0.minX, $0.maxX)) },
                         guideLines: CanvasGuides.positions(guides, axis: .horizontal),
                         gridSpacing: gridRows, gridOrigin: gridOrigin.y,
                         tolerance: tolerance, held: held.y)
        return Result(origin: CGPoint(x: x.origin, y: y.origin),
                      guideX: x.guide, guideY: y.guide,
                      guideXSpan: x.span, guideYSpan: y.span,
                      gridX: x.grid, gridY: y.grid)
    }

    /// Snaps the edge or corner a resize is DRAGGING, and leaves the one it is
    /// anchored on exactly where it was.
    ///
    /// A move carries a whole box and lines its leading edge, its middle and
    /// its trailing edge up with things. A resize carries one edge, or two at a
    /// corner, and that edge is the only thing to line up: the box's middle
    /// moves as a consequence of the drag, so a middle that happens to land on
    /// something is not a relationship anyone was aiming for. A side handle
    /// therefore touches ONE axis and never quietly tidies the other, or a row
    /// of boxes would resettle every time one of them was made wider.
    ///
    /// What the dragged edge attracts to is what a move attracts to: the canvas
    /// edges and middle, every other layer's edges and middle, and, when the
    /// grid is pulling, the nearest grid line. A snap that would turn the box
    /// inside out is refused rather than clamped, because a clamped box is a
    /// box that stopped following the pointer for no visible reason.
    public static func snapResizedFrame(_ proposed: CGRect, handle: ResizeHandle,
                                        canvas: CGSize, peers: [CGRect] = [],
                                        columnBands: [CGRect] = [],
                                        gridSpacing: CGFloat? = nil,
                                        gridOrigin: CGPoint = .zero,
                                        gridAxes: CanvasGridAxes = .columnsAndRows,
                                        guides: [CanvasGuide] = [],
                                        zoom: CGFloat,
                                        screenTolerance: CGFloat = 8,
                                        minSize: CGFloat = 1,
                                        holding held: SnapHold = .none) -> FrameResult {
        let tolerance = zoom > 0 ? screenTolerance / zoom : screenTolerance
        // Columns only: nothing is drawn across the canvas, so a top or bottom
        // edge pulls to nothing rather than to a line that is not there.
        let gridRows = gridAxes.drawsRows ? gridSpacing : nil
        var frame = proposed
        var result = FrameResult(frame: proposed)

        let crossX = Span(start: proposed.minY, end: proposed.maxY)
        let crossY = Span(start: proposed.minX, end: proposed.maxX)
        let xPeers = peers.map { Peer(along: ($0.minX, $0.maxX), cross: ($0.minY, $0.maxY)) }
            + columnBands.map { Peer(along: ($0.minX, $0.maxX), cross: ($0.minY, $0.maxY)) }
        let yPeers = peers.map { Peer(along: ($0.minY, $0.maxY), cross: ($0.minX, $0.maxX)) }

        if handle.movesMinX || handle.movesMaxX {
            let moving = handle.movesMinX ? proposed.minX : proposed.maxX
            let snap = snapEdge(moving, canvasLength: canvas.width, crossSpan: crossX,
                                peers: xPeers,
                                guideLines: CanvasGuides.positions(guides, axis: .vertical),
                                gridSpacing: gridSpacing, gridOrigin: gridOrigin.x,
                                tolerance: tolerance,
                                held: held.x)
            let limit = handle.movesMinX ? proposed.maxX - minSize : proposed.minX + minSize
            if handle.movesMinX ? snap.value <= limit : snap.value >= limit {
                // Only rewrite the geometry when the edge actually moved: an
                // untouched frame must come back bit for bit, not through a
                // subtraction that shifts its width by a millionth.
                if snap.value != moving {
                    frame.origin.x = handle.movesMinX ? snap.value : proposed.minX
                    frame.size.width = handle.movesMinX ? proposed.maxX - snap.value
                                                        : snap.value - proposed.minX
                }
                result.guideX = snap.guide
                result.guideXSpan = snap.span
                result.gridX = snap.grid
            }
        }
        if handle.movesMinY || handle.movesMaxY {
            let moving = handle.movesMinY ? proposed.minY : proposed.maxY
            let snap = snapEdge(moving, canvasLength: canvas.height, crossSpan: crossY,
                                peers: yPeers,
                                guideLines: CanvasGuides.positions(guides, axis: .horizontal),
                                gridSpacing: gridRows, gridOrigin: gridOrigin.y,
                                tolerance: tolerance,
                                held: held.y)
            let limit = handle.movesMinY ? proposed.maxY - minSize : proposed.minY + minSize
            if handle.movesMinY ? snap.value <= limit : snap.value >= limit {
                if snap.value != moving {
                    frame.origin.y = handle.movesMinY ? snap.value : proposed.minY
                    frame.size.height = handle.movesMinY ? proposed.maxY - snap.value
                                                         : snap.value - proposed.minY
                }
                result.guideY = snap.guide
                result.guideYSpan = snap.span
                result.gridY = snap.grid
            }
        }
        result.frame = frame
        return result
    }

    /// One other layer, reduced to the two ranges this axis cares about.
    private struct Peer {
        let along: (min: CGFloat, max: CGFloat)
        let cross: (min: CGFloat, max: CGFloat)
    }

    /// One way the dragged frame could line up: move `offset` points into the
    /// frame onto `target`. `span` is how far the resulting line reaches, or
    /// nil for a canvas line, which reaches everywhere.
    private struct Candidate {
        let offset: CGFloat
        let target: CGFloat
        let span: Span?
    }

    /// Snaps one axis. The frame's leading edge, centre and trailing edge each
    /// attract to the canvas edge/centre/edge and to every other layer's
    /// edge/centre/edge; the nearest in-tolerance pair wins, and ties go to the
    /// canvas, then to the earliest layer, so the answer never flickers between
    /// two equally good ones.
    private static func snapAxis(origin: CGFloat, length: CGFloat, canvasLength: CGFloat,
                                 crossOrigin: CGFloat, crossLength: CGFloat,
                                 peers: [Peer], guideLines: [CGFloat] = [],
                                 gridSpacing: CGFloat?, gridOrigin: CGFloat = 0,
                                 tolerance: CGFloat, held: CGFloat? = nil)
        -> (origin: CGFloat, guide: CGFloat?, span: Span?, grid: CGFloat?) {
        let mine = Span(start: crossOrigin, end: crossOrigin + crossLength)
        var candidates: [Candidate] = [
            Candidate(offset: 0, target: 0, span: nil),
            Candidate(offset: length / 2, target: canvasLength / 2, span: nil),
            Candidate(offset: length, target: canvasLength, span: nil),
        ]
        // A pinned guide is a line somebody put there on purpose, so it comes
        // in ahead of the other layers: where a guide and a layer edge sit on
        // the same number the guide wins the tie. It attracts the leading edge,
        // the middle and the trailing edge, exactly as a canvas edge does, and
        // it draws right across the picture for the same reason.
        for line in guideLines {
            candidates.append(Candidate(offset: 0, target: line, span: nil))
            candidates.append(Candidate(offset: length / 2, target: line, span: nil))
            candidates.append(Candidate(offset: length, target: line, span: nil))
        }
        for peer in peers {
            let span = mine.union(Span(start: peer.cross.min, end: peer.cross.max))
            let middle = (peer.along.min + peer.along.max) / 2
            // Same edge to same edge, middle to middle, and the two ways of
            // sitting flush against it. Deliberately NOT centre-to-edge: a box
            // whose middle happens to sit on another box's edge is a
            // coincidence, not a relationship anyone was aiming for.
            candidates.append(Candidate(offset: 0, target: peer.along.min, span: span))
            candidates.append(Candidate(offset: length / 2, target: middle, span: span))
            candidates.append(Candidate(offset: length, target: peer.along.max, span: span))
            candidates.append(Candidate(offset: 0, target: peer.along.max, span: span))
            candidates.append(Candidate(offset: length, target: peer.along.min, span: span))
        }

        guard let best = capture(origin, among: candidates, tolerance: tolerance, held: held) else {
            // Nothing to line up with, so the grid decides. It has no tolerance
            // of its own: the whole point of switching a grid on is that things
            // land on it, and a magnet whose reach is half the gap would be on
            // everywhere anyway. ⌘ is what turns it off for one drag.
            let landed = quantized(origin, to: gridSpacing, from: gridOrigin, held: held,
                                   tolerance: tolerance)
            // The line it landed on is the answer itself: the leading edge is
            // what the grid holds, so lighting up `landed` lights up the line
            // the edge is standing on.
            return (landed, nil, nil, gridSpacing == nil ? nil : landed)
        }
        return (best.candidate.target - best.candidate.offset, best.candidate.target,
                widened(best.candidate.span, sharing: best.candidate.target, among: candidates),
                nil)
    }

    /// Snaps ONE edge: the leading or trailing edge a resize is dragging. The
    /// candidates are the same ones a move sees, minus every one that involves
    /// the box's own middle or its far side, since neither of those is what the
    /// pointer is holding.
    private static func snapEdge(_ value: CGFloat, canvasLength: CGFloat, crossSpan: Span,
                                 peers: [Peer], guideLines: [CGFloat] = [],
                                 gridSpacing: CGFloat?, gridOrigin: CGFloat = 0,
                                 tolerance: CGFloat, held: CGFloat? = nil)
        -> (value: CGFloat, guide: CGFloat?, span: Span?, grid: CGFloat?) {
        var candidates: [Candidate] = [
            Candidate(offset: 0, target: 0, span: nil),
            Candidate(offset: 0, target: canvasLength / 2, span: nil),
            Candidate(offset: 0, target: canvasLength, span: nil),
        ]
        // The dragged edge catches a pinned guide the same way it catches the
        // canvas's own edge. See `snapAxis`.
        for line in guideLines {
            candidates.append(Candidate(offset: 0, target: line, span: nil))
        }
        for peer in peers {
            let span = crossSpan.union(Span(start: peer.cross.min, end: peer.cross.max))
            candidates.append(Candidate(offset: 0, target: peer.along.min, span: span))
            candidates.append(Candidate(offset: 0,
                                        target: (peer.along.min + peer.along.max) / 2,
                                        span: span))
            candidates.append(Candidate(offset: 0, target: peer.along.max, span: span))
        }

        guard let best = capture(value, among: candidates, tolerance: tolerance, held: held) else {
            let landed = quantized(value, to: gridSpacing, from: gridOrigin, held: held,
                                   tolerance: tolerance)
            return (landed, nil, nil, gridSpacing == nil ? nil : landed)
        }
        return (best.candidate.target, best.candidate.target,
                widened(best.candidate.span, sharing: best.candidate.target, among: candidates),
                nil)
    }

    /// The nearest candidate within reach. Ties go to the canvas, then to the
    /// earliest layer, so the answer never flickers between two equally good
    /// ones.
    ///
    /// `held` is the line the drag is already standing on, and it gets first
    /// refusal at `releaseFactor` times the reach: a line only lets go once the
    /// pointer has travelled clearly farther than it took to catch it, which is
    /// the difference between a magnet and a coin toss.
    private static func capture(_ value: CGFloat, among candidates: [Candidate],
                                tolerance: CGFloat, held: CGFloat? = nil)
        -> (candidate: Candidate, distance: CGFloat)? {
        if let held {
            var kept: (candidate: Candidate, distance: CGFloat)?
            for candidate in candidates where abs(candidate.target - held) < 0.01 {
                let distance = abs(value + candidate.offset - candidate.target)
                if distance <= tolerance * SnapHold.releaseFactor,
                   distance < (kept?.distance ?? .infinity) {
                    kept = (candidate, distance)
                }
            }
            if let kept { return kept }
        }
        var best: (candidate: Candidate, distance: CGFloat)?
        for candidate in candidates {
            let distance = abs(value + candidate.offset - candidate.target)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (candidate, distance)
            }
        }
        return best
    }

    /// Every layer that shares the winning line is on it, so the line reaches
    /// all of them: three boxes on one left edge get one line down all three,
    /// not a line to whichever one won by a hair.
    private static func widened(_ span: Span?, sharing target: CGFloat,
                                among candidates: [Candidate]) -> Span? {
        guard var span else { return nil }
        for candidate in candidates {
            guard let other = candidate.span,
                  abs(candidate.target - target) < 0.01 else { continue }
            span = span.union(other)
        }
        return span
    }

    /// The nearest grid line, or the value untouched when nothing is pulling.
    /// `origin` is where the grid starts. Counting whole steps FROM it is what
    /// makes a snapped edge land exactly on a drawn line: the grid's lines are
    /// counted from the same point in exactly the same way.
    ///
    /// `held` is the grid line the drag is already standing on, and it is lit
    /// on screen. Since the pull is as coarse as the lines a person can see,
    /// the halfway mark between two of them is a cliff: without a dead band, a
    /// hand wobbling either side of it throws the whole box a cell back and
    /// forth. So a lit line keeps the drag a few SCREEN points past halfway — a
    /// tremor is the same few points whatever the zoom — and only a clear move
    /// hands it on. Same promise as a guide's hold: a line that is showing is a
    /// line you get.
    static func quantized(_ value: CGFloat, to spacing: CGFloat?,
                          from origin: CGFloat = 0,
                          held: CGFloat? = nil,
                          tolerance: CGFloat = 0) -> CGFloat {
        guard let spacing, spacing.isFinite, spacing > 0, value.isFinite,
              origin.isFinite else { return value }
        let landed = origin + ((value - origin) / spacing).rounded() * spacing
        // Only a line of THIS grid can hold a drag on this grid: a guide left
        // over from a layer edge is a different kind of line and has no say.
        // Never more than one whole cell of hold: a magnet whose reach is wide
        // compared with the cell (a fine grid seen from far away) must not be
        // able to leave the box a cell and a half behind the pointer.
        let slack = min(max(0, tolerance) * SnapHold.gridReleaseSlack, spacing / 2)
        let keep = spacing / 2 + slack
        guard let held, held.isFinite, isOnGrid(held, spacing: spacing, from: origin),
              abs(value - held) <= keep else { return landed }
        return held
    }

    /// Whether `value` is a whole number of steps from where the grid starts.
    private static func isOnGrid(_ value: CGFloat, spacing: CGFloat,
                                 from origin: CGFloat) -> Bool {
        let steps = (value - origin) / spacing
        return abs(steps - steps.rounded()) < 1e-6
    }
}

public extension PhotonzDocument {
    /// The boxes a dragged layer lines itself up with: every other visible
    /// layer, in canvas coordinates.
    ///
    /// Three kinds of layer are deliberately left out, and each for a reason
    /// you would notice if it were in:
    ///
    /// - the dragged layer and everything inside it, which travel with the
    ///   drag and so can never be lined up with;
    /// - the groups the dragged layer sits inside, whose boxes are drawn from
    ///   its own position and would chase it as it moves;
    /// - hidden layers, and everything inside a hidden group, because a layer
    ///   sticking to something invisible looks like a bug.
    ///
    /// Groups themselves stay in: a card's outer box is a real edge on screen
    /// and lining a caption up with it is exactly what someone is trying to do.
    func snapPeers(excluding id: UUID) -> [CGRect] {
        snapPeers(excluding: [id])
    }

    /// The same list for a whole multi-selection being dragged at once: every
    /// member travels with the drag, so not one of them is something the drag
    /// can line itself up with.
    func snapPeers(excluding ids: Set<UUID>) -> [CGRect] {
        var dragged: Set<UUID> = ids
        var ancestors: Set<UUID> = []
        for id in ids {
            dragged.formUnion(layer(id: id)?.selfAndDescendants.map(\.id) ?? [id])
            var walk = parentID(of: id)
            while let up = walk {
                ancestors.insert(up)
                walk = parentID(of: up)
            }
        }

        var boxes: [CGRect] = []
        func collect(_ list: [Layer], origin: CGPoint) {
            for layer in list {
                guard layer.isVisible, !dragged.contains(layer.id) else { continue }
                if !ancestors.contains(layer.id) {
                    // The box a person can SEE: a label lines up by its last
                    // letter, not by the empty room past it.
                    boxes.append(layer.contentBounds.offsetBy(dx: origin.x, dy: origin.y))
                }
                if layer.isGroup {
                    collect(layer.children,
                            origin: CGPoint(x: origin.x + layer.frame.minX,
                                            y: origin.y + layer.frame.minY))
                }
            }
        }
        collect(layers, origin: .zero)
        return boxes
    }
}
