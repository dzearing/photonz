import CoreGraphics
import Foundation

// The timing strip: one lap of the motion, a bar for every moving property.
//
// The Motion list in the side column can say WHAT changes and BY HOW MUCH, and
// it can say a start and a duration as two numbers. What it cannot say is how
// two parts of one drawing sit against each other IN TIME, because that is a
// comparison and a comparison needs width: the bell swings, the knob hanging
// off it swings a tenth of a second later, and the only way to see that is both
// bars on one ruler at once.
//
// Everything in this file is the arithmetic of that strip and none of it is the
// strip. The view is a thin shell over these types, which is both the rule for
// `PhotonzCore` and the reason a synthesized drag can be tested at all: SwiftUI
// gestures do not answer posted mouse events, so every number a drag decides
// has to be decidable without one.
//
// A note for the day the VIDEO timeline is built on this. The lanes, the bars,
// the drag and the gap readout are all the same job there and can be taken as
// they are. `MotionStripRuler` is the one thing that must NOT be shared: an
// icon strip measures ONE LAP with no end, so it leaves room past the loop mark
// for a bar to overrun into, while a video strip measures a document with a
// last frame and has nothing past it.

// MARK: - What is in the strip

/// One bar: one property of one layer, changing over time.
public struct MotionStripLane: Identifiable, Hashable, Sendable {
    public var layerID: UUID
    public var motionID: UUID
    /// What the lane is called down the left hand edge: the property's name,
    /// the same words the entry in the side column wears.
    public var title: String
    public var timing: MotionTiming
    /// The switch on the entry in the side column. A lane that is off keeps its
    /// bar and is drawn quiet, exactly the way the eye on an effect works.
    public var isOn: Bool

    public var id: UUID { motionID }

    public init(layerID: UUID, motionID: UUID, title: String,
                timing: MotionTiming, isOn: Bool) {
        self.layerID = layerID
        self.motionID = motionID
        self.title = title
        self.timing = timing
        self.isOn = isOn
    }
}

/// The lanes belonging to one layer, under a labelled hairline.
///
/// A layer row is a HEADING and not a bar: the layer itself does not occupy
/// time, the properties on it do. Drawing the layer as a bar of its own would
/// be a bar with no start and no duration, which is a bar that lies.
public struct MotionStripGroup: Identifiable, Hashable, Sendable {
    public var layerID: UUID
    public var layerName: String
    public var lanes: [MotionStripLane]

    public var id: UUID { layerID }

    public init(layerID: UUID, layerName: String, lanes: [MotionStripLane]) {
        self.layerID = layerID
        self.layerName = layerName
        self.lanes = lanes
    }
}

/// One end of some OTHER bar: what a drag can catch on, and what the gap
/// readout is measured from.
public struct MotionStripEdge: Hashable, Sendable {
    public var ms: Int
    /// The layer the edge belongs to, so the readout can say "90 ms after Bell
    /// body" rather than printing a number on its own.
    public var name: String
    /// True for the left hand end of a bar. Only ever used to prefer a start
    /// over a finish when the two are the same distance away, because lining a
    /// bar up with another bar's start is the far commoner thing to want.
    public var isStart: Bool

    public init(ms: Int, name: String, isStart: Bool) {
        self.ms = ms
        self.name = name
        self.isStart = isStart
    }
}

extension PhotonzDocument {

    /// Every moving property in the document, grouped under the layer it is on,
    /// in the order the layers themselves are in.
    ///
    /// The WHOLE document, unlike the Motion list in the side column, which
    /// speaks for the one layer you have picked. That difference is the reason
    /// the strip exists: a lag is a relationship between two layers, and a
    /// surface that can only see one of them can never show it.
    public func motionStrip() -> [MotionStripGroup] {
        allLayers.compactMap { layer in
            let motions = layer.motions ?? []
            guard !motions.isEmpty else { return nil }
            return MotionStripGroup(
                layerID: layer.id,
                layerName: layer.name,
                lanes: motions.map {
                    MotionStripLane(layerID: layer.id, motionID: $0.id,
                                    title: $0.property.title, timing: $0.timing, isOn: $0.isOn)
                })
        }
    }

    /// The ends of every bar except one: what the bar being dragged can catch
    /// on, and what its gap is measured from. The top of the lap is in here
    /// too, so that nought is as easy to come back to as any other bar.
    public func motionStripEdges(excluding motionID: UUID) -> [MotionStripEdge] {
        var edges = [MotionStripEdge(ms: 0, name: MotionStripCopy.topOfTheLap, isStart: true)]
        for group in motionStrip() {
            for lane in group.lanes where lane.motionID != motionID {
                edges.append(MotionStripEdge(ms: lane.timing.startMS, name: group.layerName,
                                             isStart: true))
                edges.append(MotionStripEdge(ms: lane.timing.endMS, name: group.layerName,
                                             isStart: false))
            }
        }
        return edges
    }
}

/// The few words the strip says, in one place so the view and the tests agree.
public enum MotionStripCopy {
    public static let topOfTheLap = "the start"
    public static let title = "One cycle"
}

// MARK: - The ruler

/// What the numbers along the top of the strip mean.
///
/// It measures ONE LAP and then some. The room past the lap is not decoration:
/// a motion that starts late finishes after the loop has already restarted, and
/// that overrun is the thing the dashed line is there to let you see. With the
/// ruler ending exactly at the lap there would be nowhere to draw it and the
/// bar would simply be clipped, which reads as a bug rather than as a fact
/// about the animation.
public struct MotionStripRuler: Hashable, Sendable {
    /// How long one lap is.
    public let cycleMS: Double
    /// How much time the strip's width covers, lap and headroom together.
    public let spanMS: Double

    /// How much room past the end of the lap, as a share of the lap. A third is
    /// enough to draw a bar that overruns by a tenth of a second and still
    /// leaves the lap itself the great majority of the width.
    static let headroom = 1.0 / 3

    public init(cycleMS: Int) {
        let cycle = Double(max(1, cycleMS))
        self.cycleMS = cycle
        self.spanMS = cycle * (1 + Self.headroom)
    }

    /// Where a millisecond falls across the strip's width, nought at the left
    /// edge and one at the right.
    public func fraction(ofMS ms: Double) -> Double { ms / spanMS }

    /// The other way round: the millisecond a fraction of the width lands on.
    public func ms(atFraction fraction: Double) -> Double { fraction * spanMS }

    /// Where the dashed line goes: the moment the lap starts over.
    public var repeatsFraction: Double { fraction(ofMS: cycleMS) }

    /// One number written along the top.
    public struct Tick: Hashable, Sendable {
        public let ms: Double
        public let label: String
    }

    /// The numbers along the top, evenly spaced on a step a person would say
    /// out loud. Only the last one carries the unit, because a row reading
    /// "0ms 200ms 400ms" is a row of units with some numbers in it.
    public var ticks: [Tick] {
        let step = Self.step(for: spanMS)
        var values: [Double] = []
        var ms = 0.0
        while ms <= spanMS + 0.001 {
            values.append(ms)
            ms += step
        }
        return values.enumerated().map { index, ms in
            let number = MotionStripRuler.number(ms)
            return Tick(ms: ms, label: index == values.count - 1 ? "\(number) ms" : number)
        }
    }

    /// A step that gives between four and nine numbers, chosen off the 1, 2, 5
    /// ladder so every one of them is round.
    static func step(for span: Double) -> Double {
        let target = span / 6
        let magnitude = pow(10, (log10(max(target, 1))).rounded(.down))
        for multiple in [1.0, 2.0, 2.5, 5.0, 10.0] {
            let step = multiple * magnitude
            if step >= target { return step }
        }
        return magnitude * 10
    }

    static func number(_ ms: Double) -> String {
        ms == ms.rounded() ? String(Int(ms.rounded())) : String(format: "%g", ms)
    }
}

// MARK: - Dragging a bar

/// A bar under a hand.
///
/// It holds the timing the bar had when it was GRABBED and works every answer
/// out from that, so the numbers can never creep: a drag that adds its delta to
/// wherever the bar got to last would drift a little further every frame, which
/// is exactly the bug that makes a timeline feel slippery.
public struct MotionStripDrag: Hashable, Sendable {

    /// Which part of the bar is in the hand.
    public enum Grab: Hashable, Sendable {
        /// The bar itself: it moves, keeping its length.
        case body
        /// Its left hand end: the start moves and the finish stays put.
        case start
        /// Its right hand end: the finish moves and the start stays put.
        case end
    }

    /// A bar is never shorter than this. A motion of nought milliseconds is a
    /// division by nought in the frame loop, and one of a single millisecond is
    /// a bar too thin to ever grab again.
    public static let shortestMS = 10

    public let grab: Grab
    /// The timing the bar had when it was taken hold of.
    public let timing: MotionTiming
    /// The ends of every other bar, and the top of the lap.
    public let others: [MotionStripEdge]
    /// How close a drop has to land to catch on one of those.
    public let snapWithinMS: Int

    public init(grab: Grab, timing: MotionTiming,
                others: [MotionStripEdge] = [], snapWithinMS: Int = 0) {
        self.grab = grab
        self.timing = timing
        self.others = others
        self.snapWithinMS = snapWithinMS
    }

    /// What the timing becomes when the hand has moved this many milliseconds,
    /// with nothing caught on.
    public func moved(byMS delta: Int) -> MotionTiming {
        switch grab {
        case .body:
            return MotionTiming(startMS: max(0, timing.startMS + delta),
                                durationMS: timing.durationMS)
        case .end:
            return MotionTiming(startMS: timing.startMS,
                                durationMS: max(Self.shortestMS, timing.durationMS + delta))
        case .start:
            // The finish is the fixed point, which is what makes this feel like
            // pulling one end of a thing rather than moving the whole thing.
            let finish = timing.endMS
            let start = min(max(0, timing.startMS + delta), finish - Self.shortestMS)
            return MotionTiming(startMS: start, durationMS: finish - start)
        }
    }

    /// Where the bar lands, and what it caught on to get there.
    public struct Landing: Hashable, Sendable {
        public let timing: MotionTiming
        public let snappedTo: MotionStripEdge?
    }

    /// The drop: the same arithmetic as `moved(byMS:)`, and then a look at
    /// whether the end that moved came down near another bar's end.
    ///
    /// The catching is deliberately SHORT — a handful of milliseconds — because
    /// the job this strip exists for is putting the knob ninety milliseconds
    /// behind the bell, and a snap wide enough to be helpful for lining things
    /// up would eat exactly that.
    public func landing(byMS delta: Int) -> Landing {
        let free = moved(byMS: delta)
        guard snapWithinMS > 0, !others.isEmpty else {
            return Landing(timing: free, snappedTo: nil)
        }
        let moving = grab == .end ? free.endMS : free.startMS
        let nearest = others
            .filter { abs($0.ms - moving) <= snapWithinMS }
            // Nearest wins; a tie goes to a start, because lining up with where
            // something BEGINS is the far commoner thing to want.
            .min { a, b in
                let da = abs(a.ms - moving), db = abs(b.ms - moving)
                return da == db ? (a.isStart && !b.isStart) : da < db
            }
        guard let nearest, nearest.ms != moving else {
            return Landing(timing: free, snappedTo: nil)
        }
        return Landing(timing: moved(byMS: delta + (nearest.ms - moving)), snappedTo: nearest)
    }
}

// MARK: - What a drag does to the lap

/// What the drag leaves the lap's length as.
///
/// The rule is one sentence and it is the whole of why the lap is writable at
/// all: **a bar dragged past the end of the lap holds the lap where it was and
/// overruns it; a bar dragged back inside it hands the lap back to following
/// the longest motion.**
///
/// Without the first half nothing could ever run past the restart, because the
/// lap would simply grow to swallow it — and a bar still finishing while the
/// loop has already begun again IS what a lag in something that repeats looks
/// like. Without the second half, one drag out and back would leave a held
/// number behind that nobody asked for and that would then refuse to grow for
/// the next motion added.
public enum MotionStripCycle {

    /// - Parameters:
    ///   - held: how long the lap was when the bar was taken hold of.
    ///   - automatic: how long it would be now if nobody had written one down,
    ///     which is the end of the longest motion after the drag.
    ///   - current: what the document has written down now, nil for following.
    /// - Returns: what to write down, nil for going back to following.
    public static func after(drag held: Int, automatic: Int, current: Int?) -> Int? {
        // Something now runs past the lap: hold the lap, let it overrun.
        if automatic > held { return held }
        // The written number and the automatic one agree, so there is nothing
        // for the written one to say: hand it back.
        if current == automatic { return nil }
        return current
    }
}

// MARK: - The number between two bars

/// The lag: how far the bar in the hand starts from the nearest end of any
/// other bar, and what that other bar is called.
///
/// The mock drew one bracket from the left edge of the strip to the bar's
/// start, which only reads as a lag because in its example the bell happens to
/// start at nought. With five bars on the strip that number says nothing at
/// all. So this measures to the NEAREST OTHER EDGE and names it, which is the
/// relationship a person is actually making while they drag.
public struct MotionStripGap: Hashable, Sendable {
    /// How far after that edge this bar starts. Negative means before it.
    public let ms: Int
    /// The millisecond it is measured from, so the bracket knows where to
    /// start being drawn.
    public let fromMS: Int
    public let name: String

    public init?(startMS: Int, others: [MotionStripEdge]) {
        guard let nearest = others.min(by: { abs($0.ms - startMS) < abs($1.ms - startMS) })
        else { return nil }
        self.ms = startMS - nearest.ms
        self.fromMS = nearest.ms
        self.name = nearest.name
    }

    /// What the little label over the bracket says.
    public var reading: String {
        if ms == 0 { return "together with \(name)" }
        return "\(abs(ms)) ms \(ms > 0 ? "after" : "before") \(name)"
    }
}
