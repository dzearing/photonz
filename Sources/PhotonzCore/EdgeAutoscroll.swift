import CoreGraphics

/// A drag held near the edge of something that scrolls carries on into it:
/// the timeline's box, a clip or a zoom bar along time, a track carried by its
/// header up and down the tracks.
///
/// Inside a band along each edge the view scrolls towards that edge, nought at
/// the band's inner edge and gathering speed towards the edge itself, as the
/// cube of how far in the pointer is. The cube is what keeps it gentle: across
/// the inner half of the band it never passes an eighth of top speed, so a
/// hand that drifts into the band creeps rather than lurches, and only the
/// last few points reach for top speed. At the edge, and anywhere past it
/// (outside the window too), it holds top speed.
public struct EdgeAutoscroll: Hashable, Sendable {
    /// How far in from each edge the band reaches, in points.
    public var band: CGFloat
    /// Points a second, at the edge and past it.
    public var topSpeed: CGFloat

    public init(band: CGFloat, topSpeed: CGFloat) {
        self.band = band
        self.topSpeed = topSpeed
    }

    /// Along time on the timeline: a lane and a half's worth a second at
    /// the edge, so a ten minute recording opened out to two minutes across
    /// crosses in a little over three seconds whatever the window's width. A
    /// third of the way into the band it is under a tenth of a lane a second,
    /// slow enough to stop on any clip. Never slower than 800 points a second
    /// at the edge.
    public static func time(laneWidth: CGFloat) -> EdgeAutoscroll {
        EdgeAutoscroll(band: 40, topSpeed: max(800, laneWidth * 1.5))
    }

    /// Up and down the tracks, whose rows are a few dozen points tall.
    public static let rows = EdgeAutoscroll(band: 24, topSpeed: 600)

    /// How far into a band `position` is, along a view `length` long: minus
    /// one at the near edge (and before it), one at the far edge (and past
    /// it), nought anywhere outside both bands. Nought throughout a view too
    /// small to hold two bands.
    public func depth(at position: CGFloat, along length: CGFloat) -> CGFloat {
        guard band > 0, length > band * 2 else { return 0 }
        if position < band { return -min(1, (band - position) / band) }
        if position > length - band { return min(1, (position - (length - band)) / band) }
        return 0
    }

    /// The speed for a depth, in points a second, signed as the depth is.
    public func speed(forDepth depth: CGFloat) -> CGFloat {
        let clamped = min(max(depth, -1), 1)
        return topSpeed * clamped * clamped * clamped
    }

    /// Points a second at `position`: negative towards the near edge.
    public func speed(at position: CGFloat, along length: CGFloat) -> CGFloat {
        speed(forDepth: depth(at: position, along: length))
    }

    /// The same, for a drag that has to leave a band before that band
    /// scrolls (`Arming`). Past the edge always scrolls.
    public func speed(at position: CGFloat, along length: CGFloat, arming: Arming) -> CGFloat {
        let depth = depth(at: position, along: length)
        if depth < 0, !arming.armsNear, position >= 0 { return 0 }
        if depth > 0, !arming.armsFar, position <= length { return 0 }
        return speed(forDepth: depth)
    }

    /// How far to scroll in one frame of `seconds`.
    public func travel(at position: CGFloat, along length: CGFloat, seconds: Double) -> CGFloat {
        speed(at: position, along: length) * CGFloat(seconds)
    }

    /// Where a scroll at `offset` lands after one frame with the pointer at
    /// `position` down a `viewport`, never before the start or past the end of
    /// content `contentLength` long.
    public func scrolled(offset: CGFloat, contentLength: CGFloat, viewport: CGFloat,
                         at position: CGFloat, seconds: Double, arming: Arming = .armed) -> CGFloat {
        let furthest = max(0, contentLength - viewport)
        let step = speed(at: position, along: viewport, arming: arming) * CGFloat(seconds)
        return min(max(offset + step, 0), furthest)
    }

    /// Which bands a drag may scroll from. A press that starts inside a band
    /// would otherwise scroll the moment it began, before the hand has gone
    /// anywhere: that band waits until the pointer has been outside it once.
    /// The other band, and anywhere past the edge, scroll as usual.
    public struct Arming: Hashable, Sendable {
        public private(set) var armsNear: Bool
        public private(set) var armsFar: Bool

        public static let armed = Arming(armsNear: true, armsFar: true)

        public init(armsNear: Bool, armsFar: Bool) {
            self.armsNear = armsNear
            self.armsFar = armsFar
        }

        public init(startingAt position: CGFloat, along length: CGFloat, band: CGFloat) {
            armsNear = position >= band
            armsFar = position <= length - band
        }

        public mutating func moved(to position: CGFloat, along length: CGFloat, band: CGFloat) {
            if position >= band { armsNear = true }
            if position <= length - band { armsFar = true }
        }
    }
}
