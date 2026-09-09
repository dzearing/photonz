import CoreGraphics

/// The line ⇧ holds a caliper on while one of its feet is being dragged.
///
/// One key, one idea, at both moments of a measurement's life: while you are
/// PLACING a caliper ⇧ holds the direction it is measuring in, and while you
/// are ADJUSTING one you have already placed it holds the line it is already
/// on. Either way the pointer is free to go where it likes and only where it
/// lands ALONG the held line is taken, so you change how long a measurement is
/// without changing what it is measuring across.
///
/// Which line is "the line it is on" has two possible readings — the line
/// through both feet, or the axis the measurement's mode names — and for every
/// caliper this app can draw they are the SAME line: `MeasureContent` keeps a
/// measurement's two feet level, and the only modes are horizontal and
/// vertical, so a caliper is always axis aligned. The two readings are kept
/// apart here anyway (`through:` for the mode's axis, `through:and:` for the
/// line two feet define) so that the day a measurement is free to sit at an
/// angle, holding it straight already means sliding along that angle.
public struct MeasureLineHold: Equatable, Sendable {
    /// A point the line passes through.
    public let origin: CGPoint
    /// The line's direction, unit length.
    public let direction: CGVector

    public init(origin: CGPoint, direction: CGVector) {
        let length = (direction.dx * direction.dx + direction.dy * direction.dy).squareRoot()
        self.origin = origin
        self.direction = length > 0
            ? CGVector(dx: direction.dx / length, dy: direction.dy / length)
            : CGVector(dx: 1, dy: 0)
    }

    /// The mode's own axis, through a point on it — normally the foot that is
    /// NOT moving, because that is what a held drag promises: the other end of
    /// the measurement does not move.
    public init(mode: MeasureMode, through point: CGPoint) {
        self.init(origin: point,
                  direction: mode == .horizontal ? CGVector(dx: 1, dy: 0) : CGVector(dx: 0, dy: 1))
    }

    /// The line two feet define. Falls back to the mode's axis when they are
    /// in the same place and so name no direction at all.
    public init(mode: MeasureMode, through a: CGPoint, and b: CGPoint) {
        let d = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        if d.dx == 0 && d.dy == 0 {
            self.init(mode: mode, through: a)
        } else {
            self.init(origin: a, direction: d)
        }
    }

    /// The direction this line runs in, as a measurement's mode names it.
    ///
    /// Read off the line that is DRAWN rather than off whatever mode happened
    /// to build it, because while a caliper is being PLACED the mode is the
    /// very thing the key is holding: the pointer is allowed to wander into
    /// the other direction and the answer must not change with it. Every line
    /// this app makes today is axis aligned, so this is exact; a line at an
    /// angle answers with the axis it most nearly runs along.
    public var axis: MeasureMode {
        abs(direction.dx) >= abs(direction.dy) ? .horizontal : .vertical
    }

    /// `p` pulled onto the line: the point of the line nearest to it. A point
    /// already on the line comes back untouched, so nothing jumps.
    public func project(_ p: CGPoint) -> CGPoint {
        let along = (p.x - origin.x) * direction.dx + (p.y - origin.y) * direction.dy
        return CGPoint(x: origin.x + direction.dx * along,
                       y: origin.y + direction.dy * along)
    }

    /// The held line after this mouse event, given the one it was holding.
    ///
    /// The key LATCHES a line the moment it goes down and drops it the moment
    /// it comes up. Latching matters: the line has to be the one the caliper is
    /// standing on when the key is pressed, and it must not then follow the
    /// foot the drag is moving. Dropping matters just as much — the drag hands
    /// straight back to the pointer, wherever the hand has taken it, so letting
    /// go mid drag costs nothing.
    public static func holding(_ existing: MeasureLineHold?, shiftDown: Bool,
                               mode: MeasureMode, fixedFoot: CGPoint) -> MeasureLineHold? {
        guard shiftDown else { return nil }
        return existing ?? MeasureLineHold(mode: mode, through: fixedFoot)
    }

    /// Where a dragged foot lands once the magnets have had their say and the
    /// held line has the last word, plus the guides that are still honest.
    ///
    /// The magnets are asked exactly what they are asked in a free drag, and
    /// then the landing is pulled back onto the held line. So a magnet ALONG
    /// the line still catches — which is the whole point, a held foot must
    /// still be able to land on an edge — while one that would pull the foot
    /// off the line is simply not taken. A guide is dropped with it: a lit
    /// yellow line that the foot did not actually land on claims a catch that
    /// is not drawn.
    public static func landing(snapped: CGPoint, guideX: CGFloat?, guideY: CGFloat?,
                               on line: MeasureLineHold?) -> (point: CGPoint,
                                                              guideX: CGFloat?, guideY: CGFloat?) {
        guard let line else { return (snapped, guideX, guideY) }
        let point = line.project(snapped)
        let tolerance: CGFloat = 0.0001
        return (point,
                abs(point.x - snapped.x) <= tolerance ? guideX : nil,
                abs(point.y - snapped.y) <= tolerance ? guideY : nil)
    }

    /// Where the far foot goes while a caliper is being PLACED, which direction
    /// it is measuring in, and the guides that are still honest.
    ///
    /// Placing is the other half of the same idea `landing` serves for a foot
    /// being adjusted, with one thing it has to survive that adjusting never
    /// does: the held thing here is WHICH DIRECTION the measurement is going
    /// to be, so the pointer crossing into the other direction must not change
    /// it. Free, the direction is chosen from where the pointer is on every
    /// move, which is what makes an unheld caliper flip; held, it is the one
    /// the key caught and the pointer is free to travel anywhere, only how far
    /// it got ALONG that direction being taken.
    ///
    /// Flattening the far foot onto the measuring axis and projecting it onto
    /// the held line are the same operation, so there is only one of them here.
    /// A free placement therefore lands exactly where it always did, magnets'
    /// guides included: `landing` hands those straight back when nothing is
    /// held.
    public static func placing(_ existing: MeasureLineHold?, shiftDown: Bool,
                               from foot1: CGPoint, toward pointer: CGPoint,
                               guideX: CGFloat? = nil,
                               guideY: CGFloat? = nil) -> Placement {
        // What the caliper is measuring right now with nothing holding it —
        // the direction the key takes if it goes down on this very event.
        let live = MeasureContent.dominantAxis(from: foot1, to: pointer)
        let hold = holding(existing, shiftDown: shiftDown, mode: live, fixedFoot: foot1)
        let mode = hold?.axis ?? live
        let landed = landing(snapped: pointer, guideX: guideX, guideY: guideY, on: hold)
        let line = hold ?? MeasureLineHold(mode: mode, through: foot1)
        return Placement(hold: hold, foot2: line.project(landed.point), mode: mode,
                         guideX: landed.guideX, guideY: landed.guideY)
    }

    /// One move's worth of placing a caliper: the line the key is holding (nil
    /// when it is not down), where the far foot lands, the direction the
    /// measurement is going in, and the guides worth lighting.
    public struct Placement: Equatable, Sendable {
        public let hold: MeasureLineHold?
        public let foot2: CGPoint
        public let mode: MeasureMode
        public let guideX: CGFloat?
        public let guideY: CGFloat?

        public init(hold: MeasureLineHold?, foot2: CGPoint, mode: MeasureMode,
                    guideX: CGFloat?, guideY: CGFloat?) {
            self.hold = hold
            self.foot2 = foot2
            self.mode = mode
            self.guideX = guideX
            self.guideY = guideY
        }
    }
}
