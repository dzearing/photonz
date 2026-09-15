import CoreGraphics
import Foundation

/// Laying a path down with the Pen: click to drop a corner, press and drag to
/// pull a curve out of the point you are placing, close it by clicking where
/// you started or finish it open and get on with the next thing.
///
/// Every decision the gesture makes is here rather than in the canvas, because
/// the three that decide whether a pen feels right or wrong are all judgement
/// calls that want tests on them: how far the pointer has to travel before a
/// click becomes a drag, what the run to the pointer looks like before it is
/// committed, and how a path ends.
///
/// Session state only. Nothing here touches the document: the canvas takes the
/// `PathContent` an ending hands back and commits ONE layer through
/// `History.perform`, so a whole path is one undo step and the steps back
/// through its anchors happen in here (`undoLastAnchor`).
public struct PenSession: Equatable, Sendable {

    /// What a release of the mouse button did.
    public enum Outcome: Equatable, Sendable {
        /// An anchor landed and the path is still being drawn.
        case placed
        /// The path joined back to its first anchor and is finished.
        case closed(PathContent)
        /// An open path is finished, because the last anchor was clicked again.
        case finished(PathContent)
        /// The last anchor's handle was pulled back in, so the run leaving it
        /// goes straight. The path is still being drawn.
        case retracted
        /// A press aimed at the first anchor, but joining up there would have
        /// left a shape with no inside, so nothing happened and the path is
        /// exactly as it was. `hint(for:)` says why while the pointer is still
        /// sitting on the anchor.
        case refused
        /// Nothing happened (a release with no press behind it).
        case nothing
    }

    /// How far the pointer must travel, ON SCREEN, before a press becomes a
    /// drag that pulls handles out.
    ///
    /// The number every pen tool gets wrong in one direction or the other. Too
    /// small and an ordinary click wobbles a couple of points on its way down
    /// and leaves a curve nobody asked for; too large and a deliberate short
    /// handle does nothing. Four view points is what the rest of the app
    /// already calls the difference between a click and a drag
    /// (`AnnotationDrag.isClick`), so the pen does not invent a second answer
    /// to the same question.
    public static let dragThreshold: CGFloat = 4

    /// How near the pointer has to get to an anchor, ON SCREEN, for a click to
    /// land on that anchor rather than on the pixel under it. The same
    /// forgiveness a resize handle gets.
    public static let anchorTargetRadius: CGFloat = 8

    /// The anchors placed so far, in DOCUMENT coordinates. They become the
    /// layer's own coordinates when the path is committed.
    public private(set) var anchors: [PathAnchor] = []

    /// Where the pointer is now, in document coordinates. The run from the
    /// last anchor to here is what `previewPath` shows, so this is set on every
    /// mouse move and not only on a press.
    public var pointer: CGPoint?

    /// The canvas zoom, so the two tolerances above stay screen distances at
    /// any magnification.
    public var zoom: CGFloat = 1

    /// Whether shift is held, so the preview shows the constrained point
    /// rather than jumping to it at the moment of the click.
    public var constrained: Bool = false

    /// The lines a point lands on, or nil when nothing is pulling: the grid
    /// switched off, Snap to grid switched off, or a grid too fine to draw at
    /// this zoom. The canvas hands over the SAME lines a drag pulls to
    /// (`CanvasNSView.canvasNudgeGrid`), which is what keeps a point drawn
    /// with the Pen and an edge dragged with the mouse on the same paper.
    ///
    /// Only lines the canvas is actually DRAWING ever reach here. Pulling to
    /// invisible lines is what made snapping feel broken before, and a pen
    /// point that lands somewhere you cannot see a line is the same complaint
    /// with a different tool.
    public var grid: NudgeGrid?

    /// Whether ⌘ is held, which means "exactly where I put it": the one key
    /// that refuses the magnets everywhere on the canvas. Kept as state as
    /// well as passed to `press`, so pressing or releasing it moves the
    /// preview point there and then rather than at the next mouse move.
    public var free: Bool = false

    /// The weight the line comes out at, set by the canvas from the frame the
    /// path is being drawn on (`IconStrokeWeight`).
    ///
    /// Set ONCE, as the first anchor goes down, and held for the whole path:
    /// the first press lets go of whatever was picked, so anything re-read
    /// halfway through a drawing would answer differently from one click to the
    /// next. Everything the session hands back wears it, which is what keeps
    /// the line under your hand the same weight as the line that lands.
    public var startingStrokeWidth: CGFloat = PathContent.defaultStrokeWidth

    /// The ink the line comes out in, set by the canvas from what the Pen is
    /// armed with on the tool bar (`AnnotationStyles.paint(for:)`).
    ///
    /// One paint for the whole path, edge and inside alike: a path is one ink,
    /// the line while it is open and the shape once it closes. Read at the same
    /// moment as the weight above and held for the whole drawing, so the colour
    /// under your hand is the colour that lands.
    public var startingPaint: Paint = Paint(hex: PathContent.defaultColorHex)

    /// The press in progress, nil between clicks.
    private var press: Press?

    /// What a press was aiming at, decided at the moment it went down so the
    /// gesture cannot change its mind halfway through a drag.
    enum Intent: Equatable, Sendable {
        /// Drop a new anchor here.
        case place
        /// Join back to the first anchor.
        case close
        /// End the open path on the anchor that is already there.
        case finish
        /// Pull the last anchor's outgoing handle back in, so the next run
        /// leaves straight.
        case retract
    }

    private struct Press: Equatable, Sendable {
        /// Where the anchor will land: already constrained, already snapped
        /// onto an existing anchor when the press was aimed at one.
        var origin: CGPoint
        /// The raw point pressed, which is what the drag threshold measures
        /// from — the pointer's own travel, not the anchor's.
        var raw: CGPoint
        /// The handle being pulled out, as an offset from `origin`.
        var handle: CGPoint?
        /// Latched once the threshold is crossed. A drag that wanders back to
        /// where it started is still a drag: letting it flip back would make
        /// the anchor flicker between a corner and a curve under the hand.
        var dragged: Bool
        /// Option held: this anchor's two sides are NOT to be tied together.
        /// One rule in two places — see `press`.
        var breaking: Bool
        var intent: Intent
    }

    public init() {}

    // MARK: - Where the gesture is

    /// Whether a path is being drawn right now, so the canvas knows to draw
    /// its chrome and the keyboard knows the pen owns Return, Escape and undo.
    public var isDrawing: Bool { !anchors.isEmpty || press != nil }

    /// Whether the button is down right now, which is what tells the handles
    /// being dragged out from the anchors already sitting there.
    public var isPressing: Bool { press != nil }

    /// Whether the click that is happening now is AIMED at closing the path:
    /// the pointer is on the first anchor and there is more than one anchor to
    /// join up.
    ///
    /// It asks about aim, not about the result. Whether joining up actually
    /// makes a shape is settled when the button comes up, because the press
    /// itself can decide it: pulling off the first anchor bows the run home,
    /// and that is what turns a flat pair of points into a leaf.
    public func wouldClose(at point: CGPoint, zoom: CGFloat) -> Bool {
        guard anchors.count >= 2, let first = anchors.first else { return false }
        return within(point, of: first.point, zoom: zoom)
    }

    /// Whether joining the path up right now would leave a shape with an
    /// inside, the pending closing curve included.
    ///
    /// The real question behind closing, and it is not a count. Two points
    /// with a curve on them are a leaf, a petal, an eye or a lens, and they
    /// close; two points on a straight line, or twenty of them, enclose
    /// nothing however they are joined, and they do not.
    public var closingEnclosesAnArea: Bool {
        guard anchors.count >= 2 else { return false }
        var pending: CGPoint?
        if let press, press.intent == .close, press.dragged { pending = press.handle }
        return content(Self.closed(anchors, arrivingOn: pending), closed: true)
            .enclosesAnArea
    }

    /// Whether the click that is happening now would END the open path: the
    /// pointer is back on the anchor just placed. Standard in every pen, and
    /// the way out for anyone who never thinks to press Return.
    public func wouldFinish(at point: CGPoint, zoom: CGFloat) -> Bool {
        guard anchors.count >= 2, let last = anchors.last else { return false }
        guard !wouldClose(at: point, zoom: zoom) else { return false }
        return within(point, of: last.point, zoom: zoom)
    }

    /// Whether a click at `point` would land on `target`.
    ///
    /// It asks where the point would actually LAND, not where the pointer is,
    /// so the grid widens this rather than fighting it. Half a cell is wider
    /// than the eight points a click gets on its own: without this, circling
    /// back to the start of a shape on graph paper drops a second anchor
    /// exactly on top of the first one and the path never closes.
    private func within(_ point: CGPoint, of target: CGPoint, zoom: CGFloat) -> Bool {
        let scale = zoom > 0 ? zoom : 1
        let landing = onGrid(point)
        return hypot(landing.x - target.x, landing.y - target.y) * scale
            <= Self.anchorTargetRadius
    }

    // MARK: - The gesture

    /// The button went down at `point` (document coordinates).
    ///
    /// `breaking` is Option, and it means one thing in both places it can land:
    /// **do not tie this anchor's two sides together.** Dragging a new anchor
    /// out with it held gives a curve that LEAVES and a straight edge that
    /// ARRIVES; pressing it on the anchor just placed pulls that anchor's
    /// outgoing handle back in, so the next edge leaves straight. Those two
    /// between them are what makes a rounded corner — line, quarter round,
    /// line — drawable at all, and they are what Option does in every other
    /// pen, so nobody has to be told.
    public mutating func press(at point: CGPoint, constrained: Bool,
                               breaking: Bool = false, free: Bool = false,
                               zoom: CGFloat) {
        self.zoom = zoom
        self.constrained = constrained
        self.free = free
        pointer = point
        let aim = landing(at: point, constrained: constrained, breaking: breaking, zoom: zoom)
        press = Press(origin: aim.point, raw: point, handle: nil, dragged: false,
                      breaking: aim.isRetract ? true : breaking, intent: aim.intent)
    }

    // MARK: - Where the next press would land

    /// What a press at this point WOULD do, asked before the button goes down.
    ///
    /// This is the answer the canvas marks under the pointer while you are
    /// still just aiming. It exists so there is exactly one place that decides
    /// where a point goes: `press` is built out of it, so the mark drawn before
    /// the click and the anchor left by the click cannot disagree. Working the
    /// landing out a second way is how a mark becomes a lie, which is worse
    /// than no mark at all.
    public enum Landing: Equatable, Sendable {
        /// A new anchor, at this point: already on the grid, already held to
        /// its angle if ⇧ is down.
        case place(CGPoint)
        /// Joining back to the first anchor, which is where this sits.
        case close(CGPoint)
        /// Ending the open line on the anchor already at this point.
        case finish(CGPoint)
        /// Pulling the last anchor's outgoing handle back in, so the next run
        /// leaves straight. Its point is that anchor.
        case retract(CGPoint)

        /// Where it lands, whichever of the four it is.
        public var point: CGPoint {
            switch self {
            case .place(let p), .close(let p), .finish(let p), .retract(let p): p
            }
        }

        /// Whether the press would land on an anchor already on screen rather
        /// than putting a new one down. The canvas already rings those, so it
        /// does not mark them twice.
        public var isOnAnExistingAnchor: Bool {
            self != .place(point)
        }

        var isRetract: Bool { if case .retract = self { true } else { false } }

        var intent: Intent {
            switch self {
            case .place: .place
            case .close: .close
            case .finish: .finish
            case .retract: .retract
            }
        }
    }

    /// The GRID lines the point under the hand is standing on, while the
    /// button is down. Nil on an axis nothing pulled it onto, and nil on both
    /// between clicks.
    ///
    /// The canvas lights these the way a dragged box lights the lines its edge
    /// came to rest on: a grid line says "you are on this line of the paper",
    /// and the answer is the line already on screen rather than a second rule
    /// laid over it. An axis ⇧ is holding at an angle is NOT lit, because the
    /// angle owns that axis and the point is not on a line down it.
    public var pressGridLines: (x: CGFloat?, y: CGFloat?) {
        guard let origin = press?.origin, !free, let grid,
              grid.spacing.isFinite, grid.spacing > 0 else { return (nil, nil) }
        func line(_ value: CGFloat, countingFrom start: CGFloat) -> CGFloat? {
            let quantized = Snapping.quantized(value, to: grid.spacing, from: start)
            return abs(quantized - value) < 0.001 ? quantized : nil
        }
        return (line(origin.x, countingFrom: grid.origin.x),
                grid.axes.drawsRows ? line(origin.y, countingFrom: grid.origin.y) : nil)
    }

    /// Where a press at `point` would land and what it would do. Reads nothing
    /// but the session's own state, so it is safe to ask on every mouse move.
    public func landing(at point: CGPoint, constrained: Bool,
                        breaking: Bool = false, zoom: CGFloat) -> Landing {
        if breaking, let last = anchors.last, within(point, of: last.point, zoom: zoom) {
            return .retract(last.point)
        }
        if wouldClose(at: point, zoom: zoom), let first = anchors.first {
            return .close(first.point)
        }
        if wouldFinish(at: point, zoom: zoom), let last = anchors.last {
            return .finish(last.point)
        }
        return .place(place(point, constrained: constrained))
    }

    /// The pointer moved while the button is down.
    public mutating func drag(to point: CGPoint, constrained: Bool, zoom: CGFloat) {
        guard var press else { return }
        self.zoom = zoom
        self.constrained = constrained
        pointer = point
        let scale = zoom > 0 ? zoom : 1
        if hypot(point.x - press.raw.x, point.y - press.raw.y) * scale >= Self.dragThreshold {
            press.dragged = true
        }
        if press.dragged {
            var handle = CGPoint(x: point.x - press.origin.x, y: point.y - press.origin.y)
            if constrained { handle = Self.snappedToFortyFive(handle) }
            press.handle = handle
        }
        self.press = press
    }

    /// The button came up: the anchor lands, or the path ends.
    public mutating func release() -> Outcome {
        guard let press else { return .nothing }
        self.press = nil
        switch press.intent {
        case .place:
            let handle = press.dragged ? press.handle : nil
            anchors.append(Self.anchor(at: press.origin, handle: handle,
                                       breaking: press.breaking))
            return .placed
        case .retract:
            guard !anchors.isEmpty else { return .retracted }
            anchors[anchors.count - 1].handleOut = nil
            anchors[anchors.count - 1].kind = .corner
            return .retracted
        case .close:
            let joined = Self.closed(anchors, arrivingOn: press.handle)
            let content = content(joined, closed: true)
            // Nothing is taken away when the answer is no: the path stays open
            // and untouched, down to the handle the refused drag would have
            // left on the first anchor.
            guard content.enclosesAnArea else { return .refused }
            anchors = []
            return .closed(content)
        case .finish:
            let content = content(anchors, closed: false)
            anchors = []
            return .finished(content)
        }
    }

    /// A drag on the first anchor while closing shapes the run ARRIVING back at
    /// the start, so a shape can come round into its own beginning on a curve.
    ///
    /// Only that side is touched. The other side is the run to the second
    /// anchor, drawn several clicks ago, and closing a path is no reason to
    /// change a curve that is already on screen.
    private static func closed(_ anchors: [PathAnchor],
                               arrivingOn handle: CGPoint?) -> [PathAnchor] {
        guard let handle, !anchors.isEmpty else { return anchors }
        var joined = anchors
        joined[0].handleIn = CGPoint(x: -handle.x, y: -handle.y)
        // Intent, not geometry: it is only a promise to keep two handles in
        // line when there are two of them. Arriving curved and leaving straight
        // is a half-smooth corner and stays one.
        if joined[0].handleOut != nil { joined[0].kind = .smooth }
        return joined
    }

    /// Return: keep what has been drawn as an open path. Nil when there is not
    /// enough of one to keep — a single point is not a shape.
    public mutating func finish() -> PathContent? {
        press = nil
        guard anchors.count >= 2 else {
            anchors = []
            return nil
        }
        let content = content(anchors, closed: false)
        anchors = []
        return content
    }

    /// Escape: throw the path away. Nothing was ever in the document, so there
    /// is nothing to undo afterwards.
    public mutating func discard() {
        anchors = []
        press = nil
    }

    /// Command Z while drawing: step back one anchor rather than losing the
    /// path. False once there is nothing left to step back through, which is
    /// how the keystroke falls through to the document's own undo.
    @discardableResult
    public mutating func undoLastAnchor() -> Bool {
        press = nil
        guard !anchors.isEmpty else { return false }
        anchors.removeLast()
        return true
    }

    // MARK: - What the canvas draws

    /// The path as it stands including the anchor being placed right now, so a
    /// handle being dragged out bends the run BEHIND it while the button is
    /// still down. Nil when nothing has been drawn.
    public var livePath: PathContent? {
        guard let press else {
            return anchors.isEmpty ? nil : content(anchors, closed: false)
        }
        switch press.intent {
        case .place:
            let handle = press.dragged ? press.handle : nil
            let pending = Self.anchor(at: press.origin, handle: handle,
                                      breaking: press.breaking)
            return content(anchors + [pending], closed: false)
        case .retract:
            var retracted = anchors
            if !retracted.isEmpty {
                retracted[retracted.count - 1].handleOut = nil
                retracted[retracted.count - 1].kind = .corner
            }
            return retracted.isEmpty ? nil : content(retracted, closed: false)
        case .close:
            return content(Self.closed(anchors,
                                       arrivingOn: press.dragged ? press.handle : nil),
                           closed: true)
        case .finish:
            return anchors.isEmpty ? nil : content(anchors, closed: false)
        }
    }

    /// What the canvas shows between clicks: the path so far plus the run to
    /// the pointer, which is the curve about to be committed. The run is shown
    /// closing back onto the first anchor when a click there would close, so
    /// the shape you would get is on screen before you commit to it.
    public var previewPath: PathContent? {
        if press != nil { return livePath }
        guard !anchors.isEmpty else { return nil }
        guard let pointer else { return content(anchors, closed: false) }
        if wouldClose(at: pointer, zoom: zoom) { return content(anchors, closed: true) }
        if wouldFinish(at: pointer, zoom: zoom) { return content(anchors, closed: false) }
        let reach = PathAnchor(point: place(pointer, constrained: constrained))
        return content(anchors + [reach], closed: false)
    }

    /// The anchor a press leaves behind: a plain corner when nothing was
    /// dragged, a smooth anchor with two mirrored handles when something was,
    /// and a half-smooth one when Option said the two sides are not tied.
    private static func anchor(at point: CGPoint, handle: CGPoint?,
                               breaking: Bool) -> PathAnchor {
        guard let handle else { return PathAnchor(point: point) }
        return PathAnchor(point: point,
                          handleIn: breaking ? nil : CGPoint(x: -handle.x, y: -handle.y),
                          handleOut: handle,
                          kind: breaking ? .corner : .smooth)
    }

    /// Where an anchor placed at `point` actually lands: on the pointer, or on
    /// the nearest of the usual angles from the last anchor while shift is
    /// held. The distance travelled is kept, which is how every constrained
    /// drag in the app behaves (`AnnotationDrag.end`).
    private func place(_ point: CGPoint, constrained: Bool) -> CGPoint {
        guard constrained, let last = anchors.last else { return onGrid(point) }
        let offset = Self.snappedToFortyFive(CGPoint(x: point.x - last.point.x,
                                                     y: point.y - last.point.y))
        let held = CGPoint(x: last.point.x + offset.x, y: last.point.y + offset.y)
        // The angle owns the point, the way it does for every constrained drag
        // on the canvas, so the grid only gets the axis the angle left free. A
        // level run from a point already on a line therefore ends on a
        // crossing — which is most of what ⇧ is for on graph paper — while a
        // diagonal keeps the 45 degrees the key is holding it at.
        let landed = onGrid(held)
        if offset.y == 0 { return CGPoint(x: landed.x, y: held.y) }
        if offset.x == 0 { return CGPoint(x: held.x, y: landed.y) }
        return held
    }

    /// Where a point put down at `point` really lands: on the nearest crossing
    /// of the grid the canvas is drawing, or exactly where it was put when
    /// nothing is pulling or ⌘ says so.
    ///
    /// A grid of columns draws nothing across the canvas, so there is no line
    /// across to land on and the vertical stays where the hand put it.
    private func onGrid(_ point: CGPoint) -> CGPoint {
        guard !free, let grid, grid.spacing.isFinite, grid.spacing > 0 else { return point }
        return CGPoint(
            x: Snapping.quantized(point.x, to: grid.spacing, from: grid.origin.x),
            y: grid.axes.drawsRows
                ? Snapping.quantized(point.y, to: grid.spacing, from: grid.origin.y)
                : point.y)
    }

    /// The same offset turned onto the nearest multiple of 45 degrees, at the
    /// length it already had.
    static func snappedToFortyFive(_ offset: CGPoint) -> CGPoint {
        let length = hypot(offset.x, offset.y)
        guard length > 0 else { return offset }
        let step = CGFloat.pi / 4
        let angle = (atan2(offset.y, offset.x) / step).rounded() * step
        // Rounded onto the axis rather than left a billionth of a point off
        // it: a level run has to BE level, or the grid cannot tell which axis
        // the angle is holding and a "straight" edge lands off the paper.
        let x = cos(angle) * length
        let y = sin(angle) * length
        return CGPoint(x: abs(x) < 1e-9 * length ? 0 : x,
                       y: abs(y) < 1e-9 * length ? 0 : y)
    }

    /// A path wearing what a freshly drawn shape wears. An OPEN path carries no
    /// fill at all: it is a line, and offering it an inside it does not have is
    /// how a panel ends up with a row that does nothing.
    private func content(_ anchors: [PathAnchor], closed: Bool) -> PathContent {
        PathContent(anchors: anchors, isClosed: closed,
                    paint: startingPaint,
                    strokeWidth: startingStrokeWidth,
                    fill: closed ? startingPaint : nil)
    }

    /// The layer a finished path becomes, boxed round the shape it covers and
    /// left where it was drawn.
    public static func layer(from content: PathContent) -> Layer {
        PathBuilder.layer(content, at: content.bounds.origin)
    }

    // MARK: - The words on screen

    /// What the chip under the canvas says while the Pen is in hand.
    public static let hintTitle = "Pen"

    /// One line saying what to do next, which changes as the path grows.
    ///
    /// The last line is the one that matters: Return and Escape both end a
    /// path and they do OPPOSITE things with it, so the difference is written
    /// down rather than left to be discovered by losing a drawing.
    ///
    /// The FIRST line carries the way out, for the Pen picked up and not yet
    /// used: nothing else on screen says how to put it down again without a
    /// trip to the tool bar. (A finished shape puts it down by itself —
    /// `EditorState.addPath` hands back to Select — so this line is about the
    /// gap before the first click, not the gap between one shape and the next.)
    public static func hint(for session: PenSession) -> String {
        if let reason = session.flatCloseReason { return reason }
        switch session.anchors.count {
        case 0:
            return "Click to place a corner, or press and drag for a curve. "
                + "Esc puts the Pen down."
        case 1:
            return "Click the next point, or press and drag for a curve. Esc starts over."
        default:
            // Not a count. Two points with a curve on them can close and the
            // line says so; twenty points in a row cannot and it does not
            // offer something that will be refused.
            return session.closingEnclosesAnArea
                ? "Click the first point to close the shape. "
                    + "Return finishes it open, Esc discards it."
                : "Keep clicking points. Return finishes the line, Esc discards it."
        }
    }

    /// Why joining up here will not work, said while the pointer is sitting on
    /// the first anchor of a path that closing would leave flat.
    ///
    /// It arrives BEFORE the click that would be refused rather than after it,
    /// which is the difference between an app that explains itself and one
    /// that goes quiet. It also names the way out, because pulling off the
    /// anchor instead of clicking it bows the run home and makes the shape
    /// that was missing.
    var flatCloseReason: String? {
        guard let pointer, let first = anchors.first, anchors.count >= 2 else { return nil }
        guard within(pointer, of: first.point, zoom: zoom) else { return nil }
        guard !closingEnclosesAnArea else { return nil }
        return "These points are in a line, so joining them up has no inside. "
            + "Drag off this point to curve the shape closed, or click a point off the line."
    }
}
