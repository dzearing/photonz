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

    /// The press in progress, nil between clicks.
    private var press: Press?

    /// What a press was aiming at, decided at the moment it went down so the
    /// gesture cannot change its mind halfway through a drag.
    private enum Intent: Equatable, Sendable {
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

    /// Whether the click that is happening now would CLOSE the path: the
    /// pointer is on the first anchor and there are enough anchors for the
    /// result to have an inside.
    public func wouldClose(at point: CGPoint, zoom: CGFloat) -> Bool {
        guard anchors.count >= 3, let first = anchors.first else { return false }
        return within(point, of: first.point, zoom: zoom)
    }

    /// Whether the click that is happening now would END the open path: the
    /// pointer is back on the anchor just placed. Standard in every pen, and
    /// the way out for anyone who never thinks to press Return.
    public func wouldFinish(at point: CGPoint, zoom: CGFloat) -> Bool {
        guard anchors.count >= 2, let last = anchors.last else { return false }
        guard !wouldClose(at: point, zoom: zoom) else { return false }
        return within(point, of: last.point, zoom: zoom)
    }

    private func within(_ point: CGPoint, of target: CGPoint, zoom: CGFloat) -> Bool {
        let scale = zoom > 0 ? zoom : 1
        return hypot(point.x - target.x, point.y - target.y) * scale <= Self.anchorTargetRadius
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
                               breaking: Bool = false, zoom: CGFloat) {
        self.zoom = zoom
        self.constrained = constrained
        pointer = point
        if breaking, let last = anchors.last, within(point, of: last.point, zoom: zoom) {
            press = Press(origin: last.point, raw: point, handle: nil, dragged: false,
                          breaking: true, intent: .retract)
            return
        }
        if wouldClose(at: point, zoom: zoom), let first = anchors.first {
            press = Press(origin: first.point, raw: point, handle: nil, dragged: false,
                          breaking: breaking, intent: .close)
            return
        }
        if wouldFinish(at: point, zoom: zoom), let last = anchors.last {
            press = Press(origin: last.point, raw: point, handle: nil, dragged: false,
                          breaking: breaking, intent: .finish)
            return
        }
        press = Press(origin: place(point, constrained: constrained), raw: point,
                      handle: nil, dragged: false, breaking: breaking, intent: .place)
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
            applyClosingHandle(press.handle)
            let content = content(anchors, closed: true)
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
    private mutating func applyClosingHandle(_ handle: CGPoint?) {
        guard let handle, !anchors.isEmpty else { return }
        anchors[0].handleIn = CGPoint(x: -handle.x, y: -handle.y)
        // Intent, not geometry: it is only a promise to keep two handles in
        // line when there are two of them. Arriving curved and leaving straight
        // is a half-smooth corner and stays one.
        if anchors[0].handleOut != nil { anchors[0].kind = .smooth }
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
            var closing = self
            closing.applyClosingHandle(press.dragged ? press.handle : nil)
            return content(closing.anchors, closed: true)
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
        guard constrained, let last = anchors.last else { return point }
        let offset = Self.snappedToFortyFive(CGPoint(x: point.x - last.point.x,
                                                     y: point.y - last.point.y))
        return CGPoint(x: last.point.x + offset.x, y: last.point.y + offset.y)
    }

    /// The same offset turned onto the nearest multiple of 45 degrees, at the
    /// length it already had.
    static func snappedToFortyFive(_ offset: CGPoint) -> CGPoint {
        let length = hypot(offset.x, offset.y)
        guard length > 0 else { return offset }
        let step = CGFloat.pi / 4
        let angle = (atan2(offset.y, offset.x) / step).rounded() * step
        return CGPoint(x: cos(angle) * length, y: sin(angle) * length)
    }

    /// A path wearing what a freshly drawn shape wears. An OPEN path carries no
    /// fill at all: it is a line, and offering it an inside it does not have is
    /// how a panel ends up with a row that does nothing.
    private func content(_ anchors: [PathAnchor], closed: Bool) -> PathContent {
        PathContent(anchors: anchors, isClosed: closed,
                    fill: closed ? Paint(hex: PathContent.defaultColorHex) : nil)
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
    public static func hint(for session: PenSession) -> String {
        switch session.anchors.count {
        case 0:
            return "Click to place a corner. Press and drag to pull a curve out of it."
        case 1:
            return "Click the next point, or press and drag for a curve. Esc starts over."
        case 2:
            return "Keep clicking points. Return finishes the line, Esc discards it."
        default:
            return "Click the first point to close the shape. "
                + "Return finishes it open, Esc discards it."
        }
    }
}
