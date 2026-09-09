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
}
