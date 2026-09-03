import CoreGraphics
import Foundation

/// Drag-to-move snapping: a dragged layer's edges and centres attract to the
/// canvas edges and centre, and to the edges and centres of the other layers.
/// Tolerance is expressed in screen points so the magnetic feel is constant at
/// any zoom level.
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

        public init(origin: CGPoint, guideX: CGFloat? = nil, guideY: CGFloat? = nil,
                    guideXSpan: Span? = nil, guideYSpan: Span? = nil) {
            self.origin = origin
            self.guideX = guideX
            self.guideY = guideY
            self.guideXSpan = guideXSpan
            self.guideYSpan = guideYSpan
        }
    }

    public static func snapFrameOrigin(_ proposed: CGPoint, size: CGSize, canvas: CGSize,
                                       peers: [CGRect] = [], zoom: CGFloat,
                                       screenTolerance: CGFloat = 8) -> Result {
        let tolerance = zoom > 0 ? screenTolerance / zoom : screenTolerance
        let x = snapAxis(origin: proposed.x, length: size.width, canvasLength: canvas.width,
                         crossOrigin: proposed.y, crossLength: size.height,
                         peers: peers.map { Peer(along: ($0.minX, $0.maxX), cross: ($0.minY, $0.maxY)) },
                         tolerance: tolerance)
        let y = snapAxis(origin: proposed.y, length: size.height, canvasLength: canvas.height,
                         crossOrigin: proposed.x, crossLength: size.width,
                         peers: peers.map { Peer(along: ($0.minY, $0.maxY), cross: ($0.minX, $0.maxX)) },
                         tolerance: tolerance)
        return Result(origin: CGPoint(x: x.origin, y: y.origin),
                      guideX: x.guide, guideY: y.guide,
                      guideXSpan: x.span, guideYSpan: y.span)
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
                                 peers: [Peer], tolerance: CGFloat)
        -> (origin: CGFloat, guide: CGFloat?, span: Span?) {
        let mine = Span(start: crossOrigin, end: crossOrigin + crossLength)
        var candidates: [Candidate] = [
            Candidate(offset: 0, target: 0, span: nil),
            Candidate(offset: length / 2, target: canvasLength / 2, span: nil),
            Candidate(offset: length, target: canvasLength, span: nil),
        ]
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

        var best: (candidate: Candidate, distance: CGFloat)?
        for candidate in candidates {
            let distance = abs(origin + candidate.offset - candidate.target)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (candidate, distance)
            }
        }
        guard let best else { return (origin, nil, nil) }

        // Every layer that shares the winning line is on it, so the line
        // reaches all of them: three boxes on one left edge get one line down
        // all three, not a line to whichever one won by a hair.
        var span = best.candidate.span
        if span != nil {
            for candidate in candidates where candidate.span != nil {
                guard abs(candidate.target - best.candidate.target) < 0.01 else { continue }
                span = span?.union(candidate.span!)
            }
        }
        return (best.candidate.target - best.candidate.offset, best.candidate.target, span)
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
                    boxes.append(layer.localBounds.offsetBy(dx: origin.x, dy: origin.y))
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
