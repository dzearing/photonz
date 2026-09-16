import CoreGraphics
import Foundation

/// Two shapes become one: join them, cut one out of the other, keep only where
/// they overlap, or keep everything but the overlap
/// (`docs/design/mocks/pages/draw-boolean.html`).
///
/// This is how an icon actually gets built. A circle with a smaller circle cut
/// out of it is a ring; two rounded rectangles joined are a chat bubble; the
/// overlap of a square and a circle is a squircle. Almost nobody draws those
/// point by point, and nobody should have to.
///
/// **It is not `PathJoin`**, however much the word "join" suggests it. That one
/// welds the ENDS of open runs together, so three lines drawn end to end become
/// a triangle. This one combines AREA, and three lines enclose no area at all.
///
/// **The arithmetic is Core Graphics'.** `CGPath` has had union, subtraction,
/// intersection and symmetric difference since macOS 13, they are exact, and
/// they keep curves as curves. Writing a bezier clipper by hand to do the same
/// thing worse is not the work. The work is on either side of it: handing the
/// outlines over in the app's own top-left space, and walking the answer back
/// into anchors and handles so what you get is a shape you can still pull
/// points on rather than a picture of one.
///
/// Everything here is geometry on values. Nothing draws, and nothing here knows
/// what a layer is: `PhotonzDocument.combiningLayers(ids:_:)` carries it across.
public enum PathCombine {

    /// The four ways two shapes become one.
    ///
    /// The plain names are the ones on the menu. Every other drawing program
    /// calls these union, subtract, intersect and exclude, and those words are
    /// said once in the feature's description so somebody arriving from one of
    /// them can find the commands; they are not what the menu says.
    public enum Operation: String, CaseIterable, Hashable, Codable, Sendable {
        /// Everything either shape covered, as one outline.
        case join
        /// The bottom shape with everything above it taken away.
        case cutOut
        /// Only the part every shape covered.
        case keepOverlap
        /// Everything the shapes covered except the part they share.
        case dropOverlap

        /// What the menu calls it.
        public var title: String {
            switch self {
            case .join: return "Join"
            case .cutOut: return "Cut Out"
            case .keepOverlap: return "Keep Overlap"
            case .dropOverlap: return "Drop Overlap"
            }
        }

        /// What it did, in the past tense, for the line under the canvas.
        public var pastTense: String {
            switch self {
            case .join: return "Joined"
            case .cutOut: return "Cut out"
            case .keepOverlap: return "Kept the overlap of"
            case .dropOverlap: return "Dropped the overlap of"
            }
        }
    }

    /// What the submenu holding the four commands is called, in the Layer menu
    /// and on a layer row's own menu.
    public static let menuItem = "Combine Shapes"

    /// Whether a shape can take part in an area operation at all.
    ///
    /// It has to enclose something. An OPEN path is a line, and a line has no
    /// inside to add, cut or overlap; so is a closed outline whose points all
    /// sit on one line. Neither is refused loudly: they are simply left out and
    /// stay their own layer, because the alternative — quietly closing a line
    /// and filling it — changes a picture nobody asked to change.
    public static func canTakePart(_ path: PathContent) -> Bool {
        path.isClosed && path.anchors.count >= 3 && path.enclosesAnArea
    }

    /// The one outline `operation` makes of `paths`, or nil when the answer is
    /// nothing at all.
    ///
    /// **`paths` arrive BOTTOM FIRST**, the order the layers panel reads from
    /// the foot up, and that order is the whole of what makes these operations
    /// predictable:
    ///
    /// - The bottom shape is the one that SURVIVES: the result comes out
    ///   wearing its fill, its outline and everything else it was wearing, so
    ///   there is one rule to remember rather than four.
    /// - Cut Out cuts everything above out of the bottom shape. Restack and the
    ///   answer changes, which is what "cut the top one out of the one below"
    ///   means once there are three of them.
    ///
    /// Nil is a real answer and not a failure: shapes that never touch have no
    /// overlap to keep, and a shape cut out of itself leaves nothing. The
    /// caller is expected to say so rather than dropping a layer that paints no
    /// pixels on the canvas.
    public static func combine(_ paths: [PathContent], _ operation: Operation) -> PathContent? {
        let taking = paths.filter(canTakePart)
        guard taking.count >= 2, let keeper = taking.first else { return nil }
        // Every outline is restated under the nonzero winding rule first, so a
        // shape that was drawn even-odd — one whose hole only exists because of
        // the rule it wears — still arrives as the area it looks like.
        let shapes = taking.map {
            $0.cgPath.normalized(using: $0.fillRule == .evenOdd ? .evenOdd : .winding)
        }
        var result = shapes[0]
        for next in shapes.dropFirst() {
            switch operation {
            case .join: result = result.union(next)
            case .cutOut: result = result.subtracting(next)
            case .keepOverlap: result = result.intersection(next)
            case .dropOverlap: result = result.symmetricDifference(next)
            }
        }
        guard var combined = PathContent(result) else { return nil }
        combined.wear(keeper)
        return combined
    }
}

// MARK: - The app's outline as a Core Graphics one

extension PathContent {

    /// This outline as a `CGPath`, in the layer's own top-left coordinates.
    ///
    /// Ring by ring: a shape with a hole in it is one path of several loops,
    /// each started with its own move, so the fill rule can decide the inner
    /// one is a hole instead of a line being drawn across the middle of the
    /// shape to reach it.
    ///
    /// A run with no handle on either end is emitted as a LINE rather than as a
    /// cubic that happens to look flat, so a straight edge is exactly straight
    /// and stays that way through an area operation.
    public var cgPath: CGPath {
        let path = CGMutablePath()
        var runs = segments[...]
        for range in ringRanges {
            let ring = anchors[range]
            guard let first = ring.first else { continue }
            path.move(to: first.point)
            guard ring.count >= 2 else { continue }
            let count = ring.count - 1 + (isClosed ? 1 : 0)
            for run in runs.prefix(count) {
                if run.isStraight {
                    path.addLine(to: run.end)
                } else {
                    path.addCurve(to: run.end, control1: run.control1, control2: run.control2)
                }
            }
            runs = runs.dropFirst(count)
            if isClosed { path.closeSubpath() }
        }
        return path
    }

    /// The app's own outline rebuilt from a Core Graphics one, or nil when
    /// there is nothing there.
    ///
    /// This is the half of an area operation that is actually work. A `CGPath`
    /// is a flat list of "move here, curve to there", with no idea of an anchor
    /// that has a handle on each side, and a walk that reads it naively turns
    /// every curve into the straight line between its ends. So each curve's
    /// first control point is written back onto the anchor it LEAVES and its
    /// second onto the anchor it ARRIVES at, which is the same cubic said the
    /// app's way, to the last decimal place.
    ///
    /// Every loop that comes back is kept, as its own ring, so a hole and a
    /// result in unconnected pieces both land in one shape. Loops that enclose
    /// nothing are dropped: an area operation can leave a hairline where two
    /// edges grazed, and a layer with a hairline in it is a layer with a point
    /// nobody can grab.
    public init?(_ path: CGPath) {
        var rings: [[PathAnchor]] = []
        var ring: [PathAnchor] = []
        path.applyWithBlock { element in
            let piece = element.pointee
            let points = piece.points
            switch piece.type {
            case .moveToPoint:
                if !ring.isEmpty { rings.append(ring) }
                ring = [PathAnchor(point: points[0])]
            case .addLineToPoint:
                ring.append(PathAnchor(point: points[0]))
            case .addQuadCurveToPoint:
                // A quadratic is a cubic whose two control points sit two
                // thirds of the way to the one control point it has. Exact, so
                // nothing is lost saying it the only way this model can.
                guard let from = ring.last?.point else { break }
                let q = points[0], end = points[1]
                PathContent.addCurve(to: end,
                                     control1: CGPoint(x: from.x + 2 / 3 * (q.x - from.x),
                                                       y: from.y + 2 / 3 * (q.y - from.y)),
                                     control2: CGPoint(x: end.x + 2 / 3 * (q.x - end.x),
                                                       y: end.y + 2 / 3 * (q.y - end.y)),
                                     into: &ring)
            case .addCurveToPoint:
                PathContent.addCurve(to: points[2], control1: points[0], control2: points[1],
                                     into: &ring)
            case .closeSubpath:
                if !ring.isEmpty { rings.append(ring) }
                ring = []
            @unknown default:
                break
            }
        }
        if !ring.isEmpty { rings.append(ring) }

        var anchors: [PathAnchor] = []
        var starts: [Int] = []
        for loop in rings {
            guard var loop = PathContent.closedLoop(loop) else { continue }
            for index in loop.indices { loop[index].kind = PathContent.kind(of: loop[index]) }
            if !anchors.isEmpty { starts.append(anchors.count) }
            anchors += loop
        }
        guard anchors.count >= 2 else { return nil }
        self.init(anchors: anchors, isClosed: true, ringStarts: starts)
    }

    /// Writes one curve into the loop being built: the control point it leaves
    /// on goes back onto the anchor already there, and the one it arrives on
    /// comes in with the new anchor.
    private static func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint,
                                 into ring: inout [PathAnchor]) {
        guard let from = ring.last else { return }
        if control1 != from.point {
            ring[ring.count - 1].handleOut = CGPoint(x: control1.x - from.point.x,
                                                     y: control1.y - from.point.y)
        }
        var arriving = PathAnchor(point: end)
        if control2 != end {
            arriving.handleIn = CGPoint(x: control2.x - end.x, y: control2.y - end.y)
        }
        ring.append(arriving)
    }

    /// A loop as this model states one: the last anchor folded back into the
    /// first when they are the same point, because a closed ring joins its last
    /// anchor to its first by itself and a repeat of that point would be a
    /// zero-length run nobody can see or grab.
    ///
    /// Nil for a loop with nothing in it: fewer than three points, or three or
    /// more that enclose no area.
    private static func closedLoop(_ loop: [PathAnchor]) -> [PathAnchor]? {
        var loop = loop
        if loop.count >= 2, let first = loop.first, let last = loop.last,
           hypot(last.point.x - first.point.x, last.point.y - first.point.y) < 1e-6 {
            loop[0].handleIn = last.handleIn
            loop.removeLast()
        }
        guard loop.count >= 3 else { return nil }
        let ring = PathContent(anchors: loop, isClosed: true)
        guard ring.enclosesAnArea else { return nil }
        return loop
    }

    /// What somebody would call this point if they had drawn it: a bend where
    /// its two handles run in one line through it, a corner anywhere else.
    ///
    /// Worth working out rather than defaulting, because it is what decides
    /// whether dragging one of its levers afterwards swings the other one
    /// round. A circle that came through an area operation untouched has four
    /// smooth points on it, and behaves like one.
    private static func kind(of anchor: PathAnchor) -> PathAnchorKind {
        guard let into = anchor.handleIn, let out = anchor.handleOut else { return .corner }
        let lengthIn = hypot(into.x, into.y), lengthOut = hypot(out.x, out.y)
        guard lengthIn > 0, lengthOut > 0 else { return .corner }
        // The two sides point opposite ways when the outline runs straight
        // through, so their unit vectors add to nothing.
        let sum = hypot(into.x / lengthIn + out.x / lengthOut,
                        into.y / lengthIn + out.y / lengthOut)
        return sum < 0.01 ? .smooth : .corner
    }

    /// Puts on everything about `other` that is not its geometry: both paints,
    /// the line's width, where it sits and what kind of line it is.
    ///
    /// The result of an area operation is always CLOSED and always wound for
    /// the nonzero rule, whatever the shapes that made it wore, so those two
    /// are the shape's own and are not taken from anybody.
    mutating func wear(_ other: PathContent) {
        paint = other.paint
        strokeWidth = other.strokeWidth
        strokePosition = other.strokePosition
        fill = other.fill
        lineEnd = other.lineEnd
        lineCorner = other.lineCorner
        linePattern = other.linePattern
    }
}

// MARK: - What it did, so nobody has to guess

/// What an area operation did, in numbers the app can turn into one sentence.
///
/// Pure values: it holds no layer and touches no document, so every sentence
/// it produces can be read in a test without an app around it.
public struct PathCombinePlan: Hashable, Sendable {
    /// Which of the four ran.
    public var operation: PathCombine.Operation
    /// How many shapes took part.
    public var takes: Int
    /// How many picked layers could not take part and were left exactly where
    /// they were: lines, locked rows, pictures, words.
    public var leftOut: Int
    /// The name of the layer that survived, whose fill, outline and effects the
    /// result is wearing. Empty when nothing ran.
    public var keeper: String
    /// How many loops the result is made of. Two or more is a hole, or a result
    /// in unconnected pieces.
    public var rings: Int
    /// Whether the answer was nothing at all, so the document was left alone.
    public var cameToNothing: Bool

    public init(operation: PathCombine.Operation, takes: Int = 0, leftOut: Int = 0,
                keeper: String = "", rings: Int = 0, cameToNothing: Bool = false) {
        self.operation = operation
        self.takes = takes
        self.leftOut = leftOut
        self.keeper = keeper
        self.rings = rings
        self.cameToNothing = cameToNothing
    }

    /// Whether anything actually happened.
    public var didAnything: Bool { takes >= 2 && !cameToNothing }

    /// The verdict at the head of the pill under the canvas.
    public var title: String {
        guard takes >= 2 else { return "Nothing to combine" }
        guard cameToNothing else { return operation.pastTense }
        switch operation {
        case .keepOverlap: return "Nothing to keep"
        default: return "Nothing left"
        }
    }

    /// The sentence under that verdict.
    ///
    /// On a result it carries exactly the things that are NOT on the canvas to
    /// be seen: which shape's look survived, because two overlapping circles of
    /// the same colour say nothing about which was underneath, and whether the
    /// result has a hole in it or came apart into pieces, which the picture
    /// only shows when the shapes happen to be filled.
    ///
    /// On nothing it carries why, because a command that changes nothing and
    /// says nothing reads as a command that is broken.
    public var detail: String {
        guard takes >= 2 else { return "Pick two shapes that have an inside" }
        if cameToNothing { return nothingDetail }
        var said = keeper.isEmpty
            ? "\(takes) shapes are now one path"
            : "\(takes) shapes are now one path, keeping \(keeper)'s fill, outline and effects"
        if rings > 1 {
            said += operation == .cutOut && rings == 2
                ? ". It has a hole in it"
                : ". It came out in \(rings) pieces"
        }
        if leftOut > 0 {
            said += leftOut == 1
                ? ". One thing you picked has no inside, so it was left alone"
                : ". \(leftOut) things you picked have no inside, so they were left alone"
        }
        return said
    }

    /// What it says when the answer was nothing at all.
    private var nothingDetail: String {
        switch operation {
        case .keepOverlap:
            return "These shapes do not overlap, so nothing was changed"
        case .cutOut:
            return "The cut would take the whole shape away, so nothing was changed"
        case .dropOverlap:
            return "These shapes cover each other exactly, so nothing was changed"
        case .join:
            return "There was nothing to join, so nothing was changed"
        }
    }
}

// MARK: - Carrying it across to the document

extension PhotonzDocument {

    /// The picked layers that can take part in an area operation, BOTTOM FIRST.
    ///
    /// A shape qualifies when it has an outline that encloses something: a
    /// path, a rectangle, an oval or a highlighter wash. A line does not, and
    /// neither does a picture, a piece of text or a locked row.
    ///
    /// They must be SIBLINGS, the same rule grouping follows, because a result
    /// belongs in one place in the stack and two layers in different groups
    /// have no one place. The bottom-most shape decides which list that is, and
    /// anything picked outside it is left alone.
    public func combinableLayers(ids: Set<UUID>) -> [UUID] {
        let ordered = ids.filter { combinableOutline(of: $0) != nil }
            .sorted { (path(of: $0)?.last ?? 0) < (path(of: $1)?.last ?? 0) }
        guard let bottom = ordered.first, let home = path(of: bottom)?.dropLast() else { return [] }
        return ordered.filter { path(of: $0)?.dropLast() == home }
    }

    /// The outline of one layer, in DOCUMENT coordinates and with any turn or
    /// flip baked into it, or nil where the layer has no inside to combine.
    ///
    /// A rectangle, an oval and a wash are traced as the outline they really
    /// are, so the four commands work on the shapes somebody actually drew
    /// rather than only on paths drawn with the Pen.
    ///
    /// A layer that has been TURNED is not where its own numbers say it is, so
    /// the turn is applied to the anchors here. That is what lets a rotated
    /// shape combine as the shape on the screen, and it is also why the result
    /// comes back unturned: the turn has become part of its outline.
    func combinableOutline(of id: UUID) -> PathContent? {
        guard let layer = layer(id: id), !layer.isLocked else { return nil }
        var source = layer
        if layer.path == nil, let turned = layer.turnedIntoPath() { source = turned }
        guard let content = source.path else { return nil }
        var outline = content.offsetBy(dx: source.frame.origin.x, dy: source.frame.origin.y)
        if !source.transform.isIdentity {
            let centre = CGPoint(x: source.frame.midX, y: source.frame.midY)
            outline = outline.transformed(by: source.transform.affineTransform(around: centre))
        }
        guard PathCombine.canTakePart(outline) else { return nil }
        return outline
    }

    /// The document as one of the four commands would leave it, with the plan
    /// that says what happened.
    ///
    /// The shape at the BOTTOM of the picked ones is the one that survives: it
    /// keeps its id, its slot in the stack, its name, its effects and its look,
    /// and its content becomes the combined outline. Everything above it is
    /// removed. That is one row changed and the rest gone, so undo has one
    /// thing to put back and the result sits exactly where the shape it came
    /// from sat.
    ///
    /// When the answer is NOTHING the document comes back untouched and the
    /// plan says so. Deleting both shapes and leaving a blank canvas is the one
    /// outcome nobody wants and is the easiest one to reach: Keep Overlap on
    /// two shapes that do not touch.
    public func combiningLayers(ids: Set<UUID>, _ operation: PathCombine.Operation)
        -> (document: PhotonzDocument, plan: PathCombinePlan) {
        var plan = PathCombinePlan(operation: operation)
        let taking = combinableLayers(ids: ids)
        plan.takes = taking.count
        plan.leftOut = ids.count - taking.count
        guard taking.count >= 2, let keeperID = taking.first,
              let keeper = layer(id: keeperID) else { return (self, plan) }
        plan.keeper = keeper.name

        let outlines = taking.compactMap { combinableOutline(of: $0) }
        guard outlines.count == taking.count else { return (self, plan) }
        guard let result = PathCombine.combine(outlines, operation) else {
            plan.cameToNothing = true
            return (self, plan)
        }
        plan.rings = result.ringCount

        var next = self
        next.removeLayers(ids: Set(taking.dropFirst()))
        next.updateLayer(id: keeperID) { layer in
            // A rectangle or a wash becomes a path first, which is what carries
            // a highlighter's mixing across into a setting it can keep
            // (`Layer.turnedIntoPath`). The turn is already baked into the
            // outline, so the layer lets go of it and its points become
            // draggable again.
            var base = layer.path == nil ? (layer.turnedIntoPath() ?? layer) : layer
            base.transform = .identity
            let local = result.offsetBy(dx: -base.frame.origin.x, dy: -base.frame.origin.y)
            base.content = .path(local)
            layer = PathBuilder.refit(base, content: local)
        }
        return (next, plan)
    }

    /// Runs one of the four over the picked layers, in ONE mutation, so the
    /// whole thing is one undo step whatever the shapes were.
    @discardableResult
    public mutating func combineLayers(ids: Set<UUID>,
                                       _ operation: PathCombine.Operation) -> PathCombinePlan {
        let (next, plan) = combiningLayers(ids: ids, operation)
        self = next
        return plan
    }
}
