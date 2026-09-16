import CoreGraphics
import Foundation

/// Joining several open outlines into ONE, welded where their ends meet
/// (`docs/design/vector-paths.md`, "Turn several shapes into one path").
///
/// Three lines drawn end to end are a triangle, not three lines in a bag. That
/// is the whole of what this file is for: given the outlines of everything
/// somebody picked, hand back as few outlines as the geometry allows, with runs
/// that meet welded into one continuous path and closed when the last end comes
/// back to the first.
///
/// **It is not the boolean operations.** Union, subtract and intersect combine
/// AREA, and three lines enclose no area at all, so a union of them produces
/// nothing. Joining ends and combining areas share the word "join" and are
/// different operations.
///
/// Everything here is geometry on values. Nothing draws, and nothing knows what
/// a layer is: `PhotonzDocument.turningLayersIntoPath(ids:)` is what carries it
/// across to the document.
public enum PathJoin {

    /// How near two ends have to be before they count as MEETING, in document
    /// points.
    ///
    /// A tolerance nobody can predict is worse than no tolerance, so this
    /// number is stated out loud in the question the command asks before it
    /// runs, and ends further apart than this are left alone rather than being
    /// guessed at. Two points is about half the width of the line most icons
    /// are drawn with: near enough that a hand-drawn corner reads as a corner,
    /// far enough from the next feature along that nothing joins by surprise.
    ///
    /// Ends that were snapped to the grid, to a guide or to a border already
    /// meet EXACTLY, and those weld without anything moving at all.
    public static let tolerance: CGFloat = 2

    /// One outline that came out of a join.
    public struct Run: Hashable, Sendable {
        /// The outline itself, in whatever space the paths were handed over in.
        public var path: PathContent
        /// Which of the paths handed in went into this one, by index, in the
        /// order the outline walks through them.
        public var sources: [Int]
        /// How many joints were welded across a real gap — ends that were near
        /// rather than touching, pulled together to the point half way between.
        /// Zero when every end met exactly.
        public var pulledTogether: Int
        /// Whether the outline came back to where it started and was closed, so
        /// it has an inside to paint.
        public var didClose: Bool

        public init(path: PathContent, sources: [Int],
                    pulledTogether: Int = 0, didClose: Bool = false) {
            self.path = path
            self.sources = sources
            self.pulledTogether = pulledTogether
            self.didClose = didClose
        }

        /// Whether this run is more than one of the paths handed in, or is one
        /// that closed: either way the outline changed and something has to be
        /// written back.
        public var changedAnything: Bool { sources.count > 1 || didClose }
    }

    /// Welds `paths` together wherever their ends meet.
    ///
    /// What comes back is one `Run` per outline, ordered by the SMALLEST source
    /// index in each, so a caller that hands its paths over topmost first gets
    /// them back in the same order.
    ///
    /// Three rules worth knowing:
    ///
    /// - **A closed outline has no free ends**, so a rectangle or an oval comes
    ///   straight back on its own. So does a path of fewer than two anchors,
    ///   which has no run to weld.
    /// - **The order they arrive in does not matter.** The open ones are walked
    ///   in a settled geometric order rather than the order they were picked,
    ///   so the same shapes always give the same outline. Nor does the
    ///   direction each was drawn in: a run whose far end is the one that meets
    ///   is turned round before it is carried on.
    /// - **The look comes from the lowest-numbered source in each run**, which
    ///   for a caller working topmost-first is the topmost shape. Corners where
    ///   two runs were welded are drawn round when the ends they replace were
    ///   round, so the picture does not change at the joint.
    public static func join(_ paths: [PathContent],
                            tolerance: CGFloat = PathJoin.tolerance) -> [Run] {
        var runs: [Run] = []
        var open: [Int] = []
        for (index, path) in paths.enumerated() {
            if path.isClosed || path.anchors.count < 2 {
                runs.append(Run(path: path, sources: [index]))
            } else {
                open.append(index)
            }
        }

        var remaining = open.sorted { endsKey(paths[$0]) < endsKey(paths[$1]) }
        while !remaining.isEmpty {
            let seed = remaining.removeFirst()
            var chain = paths[seed]
            var sources = [seed]
            var pulled = 0

            // Carry on from the far end for as long as something meets it, then
            // do the same at the near end. Growing one end never changes the
            // other, so one pass each is the whole walk.
            while let match = nextPiece(meeting: chain.anchors.last?.point,
                                        in: remaining, paths: paths, tolerance: tolerance) {
                remaining.removeAll { $0 == match.index }
                sources.append(match.index)
                if match.gap > 0 { pulled += 1 }
                chain = welded(match.piece, onto: chain)
            }
            while let match = nextPiece(meeting: chain.anchors.first?.point,
                                        in: remaining, paths: paths,
                                        tolerance: tolerance, fromFarEnd: true) {
                remaining.removeAll { $0 == match.index }
                sources.insert(match.index, at: 0)
                if match.gap > 0 { pulled += 1 }
                chain = welded(chain, onto: match.piece)
            }

            var didClose = false
            if let head = chain.anchors.first?.point, let tail = chain.anchors.last?.point,
               distance(head, tail) <= tolerance, let ring = closing(chain) {
                if distance(head, tail) > 0 { pulled += 1 }
                chain = ring
                didClose = true
            }

            if let owner = sources.min() {
                chain = chain.wearing(paths[owner],
                                      weldedCorners: sources.count > 1 || didClose)
            }
            runs.append(Run(path: chain, sources: sources,
                            pulledTogether: pulled, didClose: didClose))
        }

        return runs.sorted { ($0.sources.min() ?? 0) < ($1.sources.min() ?? 0) }
    }

    // MARK: - The walk

    /// The next piece whose end meets `point`, already turned the right way
    /// round, or nil when nothing is near enough.
    ///
    /// `fromFarEnd` asks for a piece to put IN FRONT of the chain, so it is the
    /// piece's finish that has to meet the point rather than its start.
    private static func nextPiece(meeting point: CGPoint?, in remaining: [Int],
                                  paths: [PathContent], tolerance: CGFloat,
                                  fromFarEnd: Bool = false)
        -> (index: Int, piece: PathContent, gap: CGFloat)? {
        guard let point else { return nil }
        for index in remaining {
            let piece = paths[index]
            guard let start = piece.anchors.first?.point,
                  let end = piece.anchors.last?.point else { continue }
            let near = fromFarEnd ? end : start
            let far = fromFarEnd ? start : end
            if distance(point, near) <= tolerance {
                return (index, piece, distance(point, near))
            }
            if distance(point, far) <= tolerance {
                return (index, piece.reversed(), distance(point, far))
            }
        }
        return nil
    }

    /// `chain` with `piece` carried on from its far end.
    ///
    /// The two anchors at the joint become ONE, sitting half way between where
    /// they were, so a near miss closes by moving each end by at most half the
    /// tolerance and ends that already met do not move at all. It arrives as a
    /// hard corner: two runs drawn separately met at an angle, and pretending
    /// they were always meant to flow through would bend both of them.
    private static func welded(_ piece: PathContent, onto chain: PathContent) -> PathContent {
        guard let arriving = chain.anchors.last, let leaving = piece.anchors.first,
              !chain.anchors.isEmpty else { return chain }
        var joint = arriving
        joint.point = midpoint(arriving.point, leaving.point)
        joint.handleOut = leaving.handleOut
        joint.kind = .corner
        var welded = chain
        welded.anchors[welded.anchors.count - 1] = joint
        welded.anchors.append(contentsOf: piece.anchors.dropFirst())
        return welded
    }

    /// The chain closed into a ring, or nil when closing it would enclose
    /// nothing — an outline that doubles back along its own line sweeps no
    /// area, and closing it would leave a layer on the canvas painting no
    /// pixels. The same rule the Pen already refuses to close on.
    private static func closing(_ chain: PathContent) -> PathContent? {
        guard chain.anchors.count >= 3, let head = chain.anchors.first,
              let tail = chain.anchors.last else { return nil }
        var joint = head
        joint.point = midpoint(head.point, tail.point)
        joint.handleIn = tail.handleIn
        joint.kind = .corner
        var ring = chain
        ring.anchors[0] = joint
        ring.anchors.removeLast()
        ring.isClosed = true
        return ring.enclosesAnArea ? ring : nil
    }

    // MARK: - Arithmetic

    /// The settled order the open runs are walked in: each run keyed by its two
    /// ends, smaller one first, so turning a line round or picking it in a
    /// different order does not move it in the queue.
    private static func endsKey(_ path: PathContent) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        guard let start = path.anchors.first?.point,
              let end = path.anchors.last?.point else { return (0, 0, 0, 0) }
        let first = (start.y, start.x) <= (end.y, end.x) ? start : end
        let second = (start.y, start.x) <= (end.y, end.x) ? end : start
        return (first.y, first.x, second.y, second.x)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        a == b ? a : CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

// MARK: - Turning a path round, and dressing one

extension PathContent {

    /// The same outline walked the other way: the anchors in reverse, each
    /// one's two handles swapped, because the run that used to arrive at an
    /// anchor is the run that now leaves it.
    ///
    /// The shape drawn is identical. Only the direction changes, which is what
    /// lets a line drawn right to left be carried on from a line drawn left to
    /// right.
    public func reversed() -> PathContent {
        var flipped = self
        flipped.anchors = anchors.reversed().map {
            PathAnchor(point: $0.point, handleIn: $0.handleOut, handleOut: $0.handleIn,
                       kind: $0.kind)
        }
        return flipped
    }

    /// This outline wearing another's paints and line.
    ///
    /// `weldedCorners` says the outline gained corners where two runs were
    /// joined: those corners are drawn ROUND when the ends they replace were
    /// round, because a round cap on each of two lines meeting at a point
    /// paints exactly what one round join paints. Without that the picture
    /// would change at every joint the moment the shapes became one path.
    func wearing(_ other: PathContent, weldedCorners: Bool) -> PathContent {
        var dressed = self
        dressed.paint = other.paint
        dressed.strokeWidth = other.strokeWidth
        dressed.strokePosition = other.strokePosition
        dressed.fill = other.fill
        dressed.fillRule = other.fillRule
        dressed.lineEnd = other.lineEnd
        dressed.lineCorner = weldedCorners && other.lineEnd == .round ? .round : other.lineCorner
        dressed.linePattern = other.linePattern
        return dressed
    }

    /// Whether two outlines are painted alike, which is what decides whether
    /// joining them changes the picture beyond its shape.
    func looksLike(_ other: PathContent) -> Bool {
        paint == other.paint && strokeWidth == other.strokeWidth
            && strokePosition == other.strokePosition && fill == other.fill
            && linePattern == other.linePattern
    }
}

// MARK: - What the command would do, and doing it

/// What "Turn Into Path" over a selection would leave behind, worked out before
/// anything changes so the question can say it in plain words.
///
/// Pure counting: it holds no layers and mutates nothing, so the copy that
/// hangs off it can be read in a test without an app around it.
public struct TurnIntoPathPlan: Hashable, Sendable {
    /// How many picked layers the command acts on: every shape with an outline
    /// to find, plus any open path already picked alongside them, which can
    /// join onto the rest.
    public var takes: Int
    /// How many outlines you are left with. Fewer than `takes` when ends met.
    public var leaves: Int
    /// How many of those came back to where they started and closed, so they
    /// have an inside you can paint.
    public var closed: Int
    /// How many joints were welded across a gap rather than on a touch.
    public var pulledTogether: Int
    /// Whether the shapes that joined were not all painted alike, so the joined
    /// outline has to take one of their looks.
    public var mixedLooks: Bool
    /// The name of the row whose look and place the joined outline keeps.
    public var keeper: String
    /// How many of the picked layers are OPEN outlines, which are the only ones
    /// with free ends that could meet. Two rectangles have none, so a sentence
    /// about their ends not meeting would be nonsense.
    public var openRuns: Int = 0
    /// How many picked layers were swallowed by another. Working detail; the
    /// question reads `takes` and `leaves`.
    var absorbed: Int = 0

    public init(takes: Int = 0, leaves: Int = 0, closed: Int = 0,
                pulledTogether: Int = 0, mixedLooks: Bool = false, keeper: String = "",
                openRuns: Int = 0) {
        self.takes = takes
        self.leaves = leaves
        self.closed = closed
        self.pulledTogether = pulledTogether
        self.mixedLooks = mixedLooks
        self.keeper = keeper
        self.openRuns = openRuns
    }

    /// Whether the command would do anything at all.
    public var isEmpty: Bool { takes == 0 }

    /// Whether any two of the picked shapes would become one.
    public var joinsAnything: Bool { leaves < takes }
}

extension PhotonzDocument {

    /// The document as "Turn Into Path" would leave it, with the plan that says
    /// what happened.
    ///
    /// Two things happen, in this order. Every picked shape that has an outline
    /// to find becomes a path, which is the whole of what the command used to
    /// do to ONE layer. Then every picked outline that is still open is offered
    /// to `PathJoin`: runs that meet end to end are welded into one path, and a
    /// run that comes back to where it started is closed, so three lines that
    /// meet become one triangle you can fill.
    ///
    /// The outline that survives a weld is the TOPMOST of the ones that made
    /// it: it keeps its id, its slot in the stack, its effects and its look, so
    /// undo has one row to put back and the picture does not change colour. It
    /// keeps its name too, unless that name was one the app wrote, in which
    /// case it becomes "Path" — "Line 3" is a poor name for a triangle.
    ///
    /// The question's wording uses the names the rows were wearing BEFORE any
    /// of this. A shape stops calling itself a shape the moment it becomes a
    /// path, so by the time a survivor is picked its row already says something
    /// the person has never seen and cannot find in the list.
    ///
    /// What does NOT join: a rectangle or an oval, which is closed and has no
    /// free ends; a layer somebody has locked; a layer that has been rotated or
    /// flipped, whose outline is not where its anchors say it is; and anything
    /// whose ends are further apart than the tolerance. All of those simply
    /// stay their own layer, which is the honest answer while a path holds one
    /// outline and not several.
    public func turningLayersIntoPath(ids: Set<UUID>,
                                      tolerance: CGFloat = PathJoin.tolerance)
        -> (document: PhotonzDocument, plan: TurnIntoPathPlan) {
        var next = self
        var plan = TurnIntoPathPlan()
        // What every row SAYS before any of this happens, because that is the
        // name the question is allowed to use. Turning a shape into a path
        // renames it off the shape it stopped being, so by the time the weld
        // picks a survivor its row already reads "Path 2" — a name the person
        // has never seen and cannot look for in the list.
        let namesBefore = Dictionary(allLayers.map { ($0.id, $0.displayName) },
                                     uniquingKeysWith: { first, _ in first })
        // Bottom of the stack first, so a batch of shapes takes its Path, Path
        // 2, Path 3 in the order they are stacked rather than in whatever order
        // a set happens to hand them over. A command that numbers rows
        // differently on two identical documents is a command nobody can write
        // a test for.
        let inOrder = ids.sorted {
            (path(of: $0) ?? []).lexicographicallyPrecedes(path(of: $1) ?? [])
        }
        for id in inOrder where layer(id: id)?.canTurnIntoPath == true {
            next.turnLayerIntoPath(id: id)
            plan.takes += 1
        }

        // Everything picked that is now an OPEN outline can take part in a
        // join, grouped by the list it lives in: only layers side by side in
        // the same group can become one, exactly as only siblings can be
        // grouped together.
        var byParent: [[Int]: [UUID]] = [:]
        var alreadyPaths: Set<UUID> = []
        for id in ids {
            guard let candidate = next.layer(id: id), let outline = candidate.path,
                  !outline.isClosed, outline.anchors.count >= 2,
                  !candidate.isLocked, candidate.transform.isIdentity,
                  let slot = next.path(of: id) else { continue }
            if layer(id: id)?.canTurnIntoPath != true { alreadyPaths.insert(id) }
            plan.openRuns += 1
            byParent[Array(slot.dropLast()), default: []].append(id)
        }

        var welded: Set<UUID> = []
        for parent in byParent.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            guard let members = byParent[parent] else { continue }
            next.join(members, tolerance: tolerance, named: namesBefore,
                      into: &plan, welded: &welded)
        }
        // A path already on the canvas only counts as one of the layers the
        // command acts on when it actually took part in a weld: picking a path
        // that touches nothing alongside a rectangle is a selection of one
        // shape, and asks the one-shape question.
        plan.takes += alreadyPaths.intersection(welded).count
        plan.leaves = max(0, plan.takes - plan.absorbed)
        return (next, plan)
    }

    /// Welds one list of sibling outlines together, writing the result back.
    private mutating func join(_ members: [UUID], tolerance: CGFloat,
                               named namesBefore: [UUID: String],
                               into plan: inout TurnIntoPathPlan,
                               welded: inout Set<UUID>) {
        // Topmost first, so the outline that survives a weld is the one nearest
        // the front — the row a person thinks of as "the" shape.
        let ordered = members.sorted { (path(of: $0)?.last ?? 0) > (path(of: $1)?.last ?? 0) }
        let outlines = ordered.compactMap { id -> PathContent? in
            guard let layer = layer(id: id), let outline = layer.path else { return nil }
            return outline.offsetBy(dx: layer.frame.origin.x, dy: layer.frame.origin.y)
        }
        guard outlines.count == ordered.count else { return }

        for run in PathJoin.join(outlines, tolerance: tolerance) {
            plan.absorbed += run.sources.count - 1
            plan.pulledTogether += run.pulledTogether
            if run.didClose { plan.closed += 1 }
            guard run.changedAnything, let owner = run.sources.min() else { continue }
            let keeper = ordered[owner]
            welded.formUnion(run.sources.map { ordered[$0] })
            // The name in the question is the row whose look the joined outline
            // takes, so the first MIXED run owns it: naming a run that matched
            // would point at the wrong row.
            if run.sources.contains(where: { !outlines[$0].looksLike(outlines[owner]) }) {
                if !plan.mixedLooks { plan.keeper = namesBefore[keeper] ?? "" }
                plan.mixedLooks = true
            } else if plan.keeper.isEmpty, !plan.mixedLooks {
                plan.keeper = namesBefore[keeper] ?? ""
            }
            removeLayers(ids: Set(run.sources.filter { $0 != owner }.map { ordered[$0] }))
            // "Line 3" is a poor name for a triangle, and by now it is already
            // gone: every shape that took part stopped calling itself a shape
            // as it became a path (`turnLayerIntoPath`), so the survivor is
            // "Path 3" and the two it absorbed have just been deleted. All that
            // is left is to close the gap they left, which is why the keeper's
            // own name is the one name that does not count as taken: three
            // lines welded into one triangle leave a row reading "Path", not
            // "Path 3" with no Path or Path 2 anywhere in the list. A name a
            // person typed is theirs and is never in this at all.
            let keeperName = layer(id: keeper)?.name ?? ""
            let renamed = run.sources.count > 1 && LayerNaming.isAutoName(keeperName)
                ? LayerNaming.firstFree(base: PathBuilder.defaultName,
                                        taken: Set(allLayers.lazy
                                            .filter { $0.id != keeper }.map(\.name)))
                : nil
            updateLayer(id: keeper) { layer in
                let local = run.path.offsetBy(dx: -layer.frame.origin.x, dy: -layer.frame.origin.y)
                layer = PathBuilder.refit(layer, content: local)
                if let renamed { layer.name = renamed }
            }
        }
    }

    /// Turns every picked shape into a path and welds the ones whose ends meet,
    /// in ONE mutation, so the whole batch is one undo step
    /// (`turningLayersIntoPath(ids:)` says what it would do first).
    @discardableResult
    public mutating func turnLayersIntoPath(ids: Set<UUID>,
                                            tolerance: CGFloat = PathJoin.tolerance)
        -> TurnIntoPathPlan {
        let (next, plan) = turningLayersIntoPath(ids: ids, tolerance: tolerance)
        self = next
        return plan
    }
}

// MARK: - The question several shapes ask first

/// The question asked before SEVERAL shapes become one path.
///
/// `TurnIntoPathPrompt` is the one-shape question and is unchanged. This is its
/// plural, and it carries one thing the singular never had to: the ANSWER. Four
/// shapes can come out as one path or as three, they can close or stay open,
/// and two ends can be welded across a two point gap. None of that is
/// guessable from the canvas beforehand, so the question says it before you
/// press the button rather than leaving you to work out what happened
/// afterwards.
///
/// Pure copy: it holds a `TurnIntoPathPlan` and nothing else, so every sentence
/// can be read in a test without an app around it.
public struct TurnIntoPathQuestion: Hashable, Sendable {
    public var plan: TurnIntoPathPlan
    /// How near ends had to be to count as meeting, so the sentence that says
    /// "within 2 pt" and the arithmetic that welded them cannot drift apart.
    public var tolerance: CGFloat

    public init(plan: TurnIntoPathPlan, tolerance: CGFloat = PathJoin.tolerance) {
        self.plan = plan
        self.tolerance = tolerance
    }

    /// The question for this selection, or nil when there is nothing to turn or
    /// only one shape to turn — one shape asks `TurnIntoPathPrompt` as it
    /// always has.
    public init?(plan: TurnIntoPathPlan, tolerance: CGFloat = PathJoin.tolerance,
                 pluralOnly: Bool) {
        guard !pluralOnly || plan.takes > 1 else { return nil }
        self.init(plan: plan, tolerance: tolerance)
    }

    /// "both shapes", "these 3 shapes" — the same rule `CrowdWords` follows,
    /// because nobody says "these 2 shapes".
    private var subject: String {
        plan.takes == 2 ? "both shapes" : "these \(plan.takes) shapes"
    }

    private var gap: String {
        let rounded = (tolerance * 100).rounded() / 100
        let text = rounded == rounded.rounded()
            ? String(Int(rounded)) : String(format: "%g", Double(rounded))
        return "\(text) pt"
    }

    public var title: String {
        plan.leaves == 1
            ? "Turn \(subject) into one path?"
            : "Turn \(subject) into \(plan.leaves) paths?"
    }

    /// What you gain, then what happens to the ends, then what it costs, then
    /// the way back. The gain is what you came for and the rest is what you
    /// could not have known.
    public var message: String {
        var parts = ["Every point on them becomes yours to move, curve or delete."]
        if plan.leaves == 1 {
            parts.append("Their ends meet, so they join into one outline.")
        } else if plan.joinsAnything {
            parts.append("The ones whose ends meet join into one outline, "
                + "and the rest stay as they are.")
        } else if plan.openRuns > 1 {
            parts.append("No two of their ends are within \(gap) of each other, "
                + "so they stay separate outlines.")
        } else {
            // A rectangle and an oval are closed and have no free ends at all,
            // so there is nothing to say about ends meeting.
            parts.append("Each becomes its own path.")
        }
        if plan.pulledTogether == 1 {
            parts.append("One pair of ends was near rather than touching, "
                + "within \(gap), and has been pulled together.")
        } else if plan.pulledTogether > 1 {
            parts.append("\(plan.pulledTogether) pairs of ends were near rather than touching, "
                + "within \(gap), and have been pulled together.")
        }
        if plan.closed == 1 {
            parts.append(plan.leaves == 1
                ? "It comes back to where it started, so it closes and you can paint inside it."
                : "One of them comes back to where it started, so it closes "
                    + "and you can paint inside it.")
        } else if plan.closed > 1 {
            parts.append("\(plan.closed) of them come back to where they started, "
                + "so they close and you can paint inside them.")
        }
        if plan.mixedLooks, !plan.keeper.isEmpty {
            parts.append("They are not all painted alike, so the joined outline takes "
                + "\u{201C}\(plan.keeper)\u{201D}\u{2019}s colour and line.")
        }
        parts.append("They stop being shapes, so the controls only a shape has go.")
        parts.append("Undo puts it back.")
        return parts.joined(separator: " ")
    }

    public var confirm: String { TurnIntoPathPrompt(name: "", subject: .rectangle).confirm }
    public var cancel: String { "Cancel" }
}
